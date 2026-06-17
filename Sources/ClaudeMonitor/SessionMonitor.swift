import Foundation
import Combine
import AppKit
import ApplicationServices

// MARK: - Session Model

struct Session: Codable, Identifiable, Equatable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int64
    let procStart: String
    let version: String
    let peerProtocol: Int?
    let kind: String?
    let entrypoint: String?
    let status: String
    let updatedAt: Int64

    var id: Int { pid }

    private enum CodingKeys: String, CodingKey {
        case pid, sessionId, cwd, startedAt, procStart, version
        case peerProtocol, kind, entrypoint, status, updatedAt
    }

    /// 成员构造器（测试与合成事件时使用）
    init(pid: Int, sessionId: String, cwd: String, startedAt: Int64,
         procStart: String, version: String, peerProtocol: Int?,
         kind: String?, entrypoint: String?, status: String, updatedAt: Int64) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = startedAt
        self.procStart = procStart
        self.version = version
        self.peerProtocol = peerProtocol
        self.kind = kind
        self.entrypoint = entrypoint
        self.status = status
        self.updatedAt = updatedAt
    }

    /// 自定义解码：pid 为关键标识（缺失则放弃该会话）；其余字段缺失时给默认值，
    /// 增强对 Claude Code session JSON 格式变更的向前兼容。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pid = try c.decode(Int.self, forKey: .pid)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        startedAt = try c.decodeIfPresent(Int64.self, forKey: .startedAt) ?? 0
        procStart = try c.decodeIfPresent(String.self, forKey: .procStart) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        peerProtocol = try c.decodeIfPresent(Int.self, forKey: .peerProtocol)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        entrypoint = try c.decodeIfPresent(String.self, forKey: .entrypoint)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }

    /// 从 cwd 路径提取项目名称
    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// 项目路径的简短显示（最多显示最后两级目录）
    var shortPath: String {
        let components = cwd.split(separator: "/")
        if components.count <= 2 { return cwd }
        return "..." + components.suffix(2).joined(separator: "/")
    }

    var isBusy: Bool { status == "busy" }

    // MARK: - Hooks 精准状态

    /// 从 hooks 状态文件读取精准状态
    /// 返回: "tool_call" / "waiting_permission" / "stopped" / "error" / nil(未安装 hooks)
    var hookStatus: String? {
        let prefix = String(sessionId.prefix(12))
        let path = "/tmp/claude-monitor/state-\(prefix).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hookSt = json["status"] as? String,
              let timestamp = json["timestamp"] as? Int64
        else { return nil }

        // 状态文件超过 120 秒未更新 → 视为过期
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if now - timestamp > 120_000 { return nil }

        return hookSt
    }
}

// MARK: - Session Status

enum SessionStatus: String {
    case busy = "busy"
    case idle = "idle"
    case unknown = "unknown"

    var label: String {
        switch self {
        case .busy: return "处理中"
        case .idle: return "等待输入"
        case .unknown: return "未知"
        }
    }
}

// MARK: - Session Monitor

final class SessionMonitor: ObservableObject {
    @Published var sessions: [Session] = []

    /// 会话列表变化时回调（用于面板自动调整大小）
    var onSessionsChanged: (() -> Void)?

    /// 通知管理器（由 AppDelegate 注入）
    weak var notificationManager: NotificationManager?

    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private let sessionsDir: String
    private let queue = DispatchQueue(label: "com.claudemonitor.watcher", qos: .utility)

    /// 上一帧每个会话的显示状态。状态转换以「上一帧 vs 当前帧」对比为准，
    /// 而非对旧数据实时重算 —— 否则 hooks 写入的 state 文件变化无法被捕获，
    /// 任务完成等通知会大面积漏发。
    private var lastDisplayedStatus: [Int: DisplayStatus] = [:]
    /// 是否已完成首轮加载。首轮只填充缓存、不发射事件，避免把已存在会话误报为「新启动」。
    private var hasInitialized = false

    init() {
        sessionsDir = NSHomeDirectory() + "/.claude/sessions"
    }

    deinit {
        source?.cancel()
        pollTimer?.invalidate()
    }

    func start() {
        reloadSessions()
        startFileWatcher()
        startPolling()
    }

    // MARK: - File Watching

    private func startFileWatcher() {
        let fd = open(sessionsDir, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.reloadSessions()
            }
        }

        let fileDescriptor = fd
        source?.setCancelHandler {
            close(fileDescriptor)
        }

        source?.resume()
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reloadSessions()
        }
    }

    // MARK: - Session Loading

    func reloadSessions() {
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            self.sessions = []
            return
        }

        let jsonFiles = files.filter { $0.hasSuffix(".json") }
        var loaded: [Session] = []

        for file in jsonFiles {
            let path = (sessionsDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            do {
                loaded.append(try JSONDecoder().decode(Session.self, from: data))
            } catch {
                print("[SessionMonitor] 解码失败 \(file): \(error)")
            }
        }

        loaded.sort { $0.startedAt < $1.startedAt }

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // 当前帧每个会话的显示状态
        let newStatusMap = Dictionary(uniqueKeysWithValues:
            loaded.map { ($0.pid, $0.displayStatus(now: now)) })

        // 上一帧的会话对象（会话结束时用于回填信息）
        let prevSessionMap = Dictionary(uniqueKeysWithValues:
            self.sessions.map { ($0.pid, $0) })

        self.sessions = loaded

        // 首轮加载：只初始化缓存，不发射事件，避免把已存在会话误报为「新启动」
        if !hasInitialized {
            hasInitialized = true
            lastDisplayedStatus = newStatusMap
            notificationManager?.cleanupState(forActivePids: Set(loaded.map(\.pid)))
            onSessionsChanged?()
            return
        }

        // 检测新会话：上一帧没有、当前帧有的 pid
        for session in loaded where lastDisplayedStatus[session.pid] == nil {
            let newStatus = newStatusMap[session.pid] ?? .offline
            notificationManager?.handleEvent(MonitoredEvent(
                type: .sessionStarted,
                session: session,
                previousDisplayStatus: nil,
                newDisplayStatus: newStatus
            ))
        }

        // 检测状态转换：两帧都存在的 pid，对比缓存的上一帧状态（而非实时重算）
        for session in loaded {
            let newStatus = newStatusMap[session.pid] ?? .offline
            if let oldStatus = lastDisplayedStatus[session.pid], oldStatus != newStatus {
                let eventType = mapTransition(oldStatus, newStatus)
                if eventType == .taskStarted {
                    notificationManager?.recordTaskStart(pid: session.pid)
                }
                notificationManager?.handleEvent(MonitoredEvent(
                    type: eventType,
                    session: session,
                    previousDisplayStatus: oldStatus,
                    newDisplayStatus: newStatus
                ))
            }
        }

        // 检测结束的会话：上一帧有、当前帧没有的 pid
        for (pid, oldStatus) in lastDisplayedStatus where newStatusMap[pid] == nil {
            if let oldSession = prevSessionMap[pid] {
                notificationManager?.handleEvent(MonitoredEvent(
                    type: .sessionEnded,
                    session: oldSession,
                    previousDisplayStatus: oldStatus,
                    newDisplayStatus: .offline
                ))
            }
        }

        // 更新缓存为当前帧
        lastDisplayedStatus = newStatusMap

        // 清理通知管理器中已消失会话的残留状态（防抖表 / 任务时长表）
        notificationManager?.cleanupState(forActivePids: Set(loaded.map(\.pid)))

        // 通知面板调整大小
        onSessionsChanged?()
    }

    // MARK: - Status Transition Mapping

    private func mapTransition(_ from: DisplayStatus, _ to: DisplayStatus) -> NotificationEventType {
        if to == .needsAttention { return .needsAttention }
        if from == .busy && to == .idle { return .taskCompleted }
        if from == .idle && to == .busy { return .taskStarted }
        if from == .needsAttention && to == .busy { return .taskStarted }
        if from == .needsAttention && to == .idle { return .taskCompleted }
        if to == .offline { return .error }
        return .taskStarted
    }

    // MARK: - Quick Open - Parent App Detection

    enum ParentApp {
        case terminal, iterm, warp, cursor, vscode, idea, unknown

        var name: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm: return "iTerm"
            case .warp: return "Warp"
            case .cursor: return "Cursor"
            case .vscode: return "VS Code"
            case .idea: return "IntelliJ IDEA"
            case .unknown: return "Terminal"
            }
        }
    }

    /// 检测会话的父应用程序
    /// 优先用 NSRunningApplication 的 bundle id / 进程名匹配（可靠），
    /// 兜底用 ps comm 字符串匹配。
    func detectParentApp(pid: Int) -> ParentApp {
        var currentPid = pid
        var depth = 0

        while currentPid > 1 && depth < 15 {
            if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)) {
                let bid = app.bundleIdentifier ?? ""
                let name = app.localizedName ?? ""
                if bid.contains("todesktop.230313") || name.contains("Cursor") { return .cursor }
                if bid.hasPrefix("com.microsoft.VSCode") || name == "Code" { return .vscode }
                if bid.contains("iterm") || bid.contains("iTerm") || name.contains("iTerm") { return .iterm }
                if bid.contains("warp") || bid.contains("Warp") || name.contains("Warp") { return .warp }
                if bid == "com.apple.Terminal" || name == "Terminal" { return .terminal }
                if bid.contains("intellij") || bid.contains("idea") || name.contains("IntelliJ") { return .idea }
            }

            // 兜底：ps comm 字符串匹配
            let command = getProcessCommand(pid: currentPid)
            if command.contains("Cursor") { return .cursor }
            if command.contains("Code Helper") || command.hasSuffix("Code") { return .vscode }
            if command.contains("iTerm") { return .iterm }
            if command.contains("Warp") { return .warp }
            if command.contains("Terminal") { return .terminal }
            if command.contains("idea") || command.contains("IntelliJ") { return .idea }

            let ppid = getPPID(pid: currentPid)
            if ppid <= 1 { break }
            currentPid = ppid
            depth += 1
        }

        return .terminal
    }

    /// 点击会话 → 切换到对应的终端窗口/标签页
    /// 进程树遍历与 ps 调用均为同步阻塞，放到后台线程避免点击卡顿主线程。
    func openSession(_ session: Session) {
        let pid = session.pid
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let parentApp = self.detectParentApp(pid: pid)
            let tty = self.getTTY(pid: pid)
            DispatchQueue.main.async {
                self.activate(session: session, parentApp: parentApp, tty: tty)
            }
        }
    }

    /// 实际激活窗口的逻辑（在主线程执行）
    private func activate(session: Session, parentApp: ParentApp, tty: String) {
        switch parentApp {
        case .terminal:
            activateTerminalTab(tty: tty)
        case .iterm:
            activateITermSession(tty: tty)
        case .warp:
            activateRunningApp("dev.warp.Warp-Stable")
        case .cursor:
            if !activateAppWindowAX(
                bundleId: "com.todesktop.230313mzl4w4u92",
                projectName: session.projectName
            ) {
                activateRunningApp("com.todesktop.230313mzl4w4u92")
            }
        case .vscode:
            if !activateAppWindowAX(
                bundleId: "com.microsoft.VSCode",
                projectName: session.projectName
            ) {
                activateRunningApp("com.microsoft.VSCode")
            }
        case .idea:
            activateRunningApp("com.jetbrains.intellij")
        case .unknown:
            // 后备：尝试 Terminal，再打开 Finder
            if !activateTerminalTab(tty: tty) {
                NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
            }
        }
    }

    /// 获取进程的 TTY
    private func getTTY(pid: Int) -> String {
        runProcess("/bin/ps", arguments: ["-o", "tty=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Terminal.app 激活指定标签页

    @discardableResult
    private func activateTerminalTab(tty: String) -> Bool {
        guard !tty.isEmpty else { return false }

        // TTY 格式: "ttys045" → 在 AppleScript 中匹配 "/dev/ttys045"
        let escapedTTY = tty.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "/dev/\(escapedTTY)" then
                        set selected of t to true
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """

        return runAppleScript(script)
    }

    // MARK: - iTerm2 激活指定 session

    @discardableResult
    private func activateITermSession(tty: String) -> Bool {
        guard !tty.isEmpty else { return false }

        let escapedTTY = tty.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s contains "\(escapedTTY)" then
                            select s
                            set index of w to 1
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """

        return runAppleScript(script)
    }

    // MARK: - 激活正在运行的应用

    @discardableResult
    private func activateRunningApp(_ bundleId: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let app = apps.first {
            return app.activate()
        }
        return false
    }

    // MARK: - Accessibility API 窗口激活（Cursor / VS Code）

    /// 用 Accessibility API 激活标题匹配 projectName 的窗口。
    /// 不经过 System Events（AppleScript），改用进程内 AX API，只需「辅助功能」权限——
    /// 该权限对 ad-hoc 签名的 app 可正常弹框/手动授权，绕开自动化权限对 ad-hoc 不弹框的死结。
    @discardableResult
    private func activateAppWindowAX(bundleId: String, projectName: String) -> Bool {
        // 未授权则弹系统引导框（辅助功能权限对 ad-hoc app 可稳定授予）
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): kCFBooleanTrue] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            diagLog("AX 辅助功能未授权 → 已弹引导，请到 系统设置>隐私与安全性>辅助功能 允许 ClaudeMonitor")
        }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let target = apps.first(where: { $0.activationPolicy == .regular }) ?? apps.first else {
            diagLog("AX \(bundleId): 未找到运行中进程，fallback activate")
            return activateRunningApp(bundleId)
        }
        _ = target.activate()

        let appEl = AXUIElementCreateApplication(target.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            diagLog("AX \(bundleId): 无法列举窗口（辅助功能未授权或 app 不支持），fallback activate")
            return activateRunningApp(bundleId)
        }

        var titles: [String] = []
        for w in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else { continue }
            titles.append(title)
            if title.contains(projectName) {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                diagLog("AX 激活 \(bundleId)/\"\(projectName)\" → 命中窗口 \"\(title)\"，已 AXRaise")
                return true
            }
        }
        diagLog("AX \(bundleId): 窗口标题 [\(titles.joined(separator: " | "))] 均不含 \"\(projectName)\"")
        return false
    }

    /// 激活应用的指定窗口（通过窗口标题匹配项目名称）
    ///
    /// 针对 Electron 应用（Cursor / VS Code）：
    /// - 用 `perform action "AXRaise"` 提升目标窗口 z-order（实测对 Cursor 有效），
    ///   用 try 包裹避免单步抛错导致整段脚本失败。
    ///   注：`set index` 对 System Events 的 Electron 窗口只读（报 -10006），不可用；
    ///   Terminal/iTerm 能用 set index 是因为走应用自身的 AppleScript 字典。
    /// - 返回值表示「是否匹配到目标窗口」，而非「脚本是否执行出错」——
    ///   否则匹配失败或 AXRaise 抛错会让外层 fallback 到 activateRunningApp，激活错误的窗口。
    @discardableResult
    private func activateAppWindow(bundleId: String, processName: String, projectName: String) -> Bool {
        let escaped = projectName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "\(bundleId)"
            activate
        end tell
        delay 0.15
        set matched to false
        set matchedName to ""
        tell application "System Events"
            tell process "\(processName)"
                repeat with w in every window
                    if name of w contains "\(escaped)" then
                        set matchedName to name of w
                        try
                            perform action "AXRaise" of w
                        end try
                        set matched to true
                        exit repeat
                    end if
                end repeat
            end tell
        end tell
        return (matched as string) & "|" & matchedName
        """

        let result = runAppleScriptValue(script)
        if let result = result {
            let parts = result.split(separator: Character("|"), maxSplits: 1, omittingEmptySubsequences: false)
            let matched = String(parts.first ?? "") == "true"
            let winName = parts.count > 1 ? String(parts[1]) : ""
            diagLog("激活 \(processName)/\"\(projectName)\" → matched=\(matched) window=\"\(winName)\"")
            return matched
        }
        diagLog("激活 \(processName)/\"\(projectName)\" → AppleScript 执行失败（疑似权限被拒），fallback 将激活任意窗口")
        return false
    }

    /// 诊断日志：同时 print 并追加到 /tmp/claude-monitor/activate.log。
    /// open 启动的安装版里 print 仅到 stdout 看不到，落盘才能排查 AppleScript/TCC 权限问题。
    private func diagLog(_ message: String) {
        print("[SessionMonitor] \(message)")
        let dir = "/tmp/claude-monitor"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/activate.log"
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: path)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path),
               let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// 执行 AppleScript 并返回脚本本身的字符串返回值（执行出错时返回 nil）。
    /// 与 runAppleScript 不同：后者只返回「是否执行出错」，拿不到脚本 return 的真实内容。
    private func runAppleScriptValue(_ source: String) -> String? {
        guard let appleScript = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&error)
        if let error = error {
            diagLog("AppleScript error: \(error)")
            return nil
        }
        return descriptor.stringValue
    }

    /// 在终端中打开路径（用于右键菜单的备选选项）
    func openTerminal(at path: String) {
        let terminals: [(String, String)] = [
            ("Warp", "dev.warp.Warp-Stable"),
            ("iTerm", "com.googlecode.iterm2"),
            ("Terminal", "com.apple.Terminal"),
        ]

        for (_, bundleId) in terminals {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                openAppByBundleId(bundleId, at: path)
                return
            }
        }

        openAppleTerminal(at: path)
    }

    /// 使用命令行工具打开 IDE（用于右键菜单）
    func openInApp(_ command: String, at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, path]

        do {
            try process.run()
        } catch {
            let bundleIdMap: [String: String] = [
                "cursor": "com.todesktop.230313mzl4w4u92",
                "code": "com.microsoft.VSCode",
                "idea": "com.jetbrains.intellij",
            ]
            if let bundleId = bundleIdMap[command] {
                openAppByBundleId(bundleId, at: path)
            }
        }
    }

    /// 通过 Bundle ID 打开应用
    private func openAppByBundleId(_ bundleId: String, at path: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            openAppleTerminal(at: path)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: appURL,
            configuration: config
        )
    }

    /// 使用 AppleScript 打开 Terminal.app
    private func openAppleTerminal(at path: String) {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escaped)'"
        end tell
        """

        runAppleScript(script)
    }

    /// 执行 AppleScript
    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        if let appleScript = NSAppleScript(source: source) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                return false
            }
            return true
        }
        return false
    }

    // MARK: - Process Helpers

    private func getPPID(pid: Int) -> Int {
        let output = runProcess("/bin/ps", arguments: ["-o", "ppid=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }

    private func getProcessCommand(pid: Int) -> String {
        runProcess("/bin/ps", arguments: ["-o", "comm=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runProcess(_ path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

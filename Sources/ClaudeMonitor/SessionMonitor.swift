import Foundation
import Combine
import AppKit

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

    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private let sessionsDir: String
    private let queue = DispatchQueue(label: "com.claudemonitor.watcher", qos: .utility)

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
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let session = try? JSONDecoder().decode(Session.self, from: data)
            {
                loaded.append(session)
            }
        }

        loaded.sort { $0.startedAt < $1.startedAt }

        let oldMap = Dictionary(uniqueKeysWithValues: self.sessions.map { ($0.pid, $0.status) })
        self.sessions = loaded

        for session in loaded {
            if let oldStatus = oldMap[session.pid], oldStatus != session.status {
                self.sendNotification(session: session, from: oldStatus)
            }
        }

        let currentPids = Set(loaded.map(\.pid))
        for (pid, _) in oldMap where !currentPids.contains(pid) {
            self.sendSessionEndNotification(pid: pid)
        }
    }

    // MARK: - Notifications

    private func sendNotification(session: Session, from oldStatus: String) {
        let notification = NSUserNotification()
        notification.title = "Claude Code"

        if session.isBusy {
            notification.informativeText = "\(session.projectName) 开始处理..."
        } else {
            notification.informativeText = "\(session.projectName) 已完成，等待输入"
            notification.soundName = NSUserNotificationDefaultSoundName
        }
        notification.identifier = "claude-\(session.pid)"

        NSUserNotificationCenter.default.deliver(notification)
    }

    private func sendSessionEndNotification(pid: Int) {
        let notification = NSUserNotification()
        notification.title = "Claude Code"
        notification.informativeText = "会话已结束"
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.identifier = "claude-end-\(pid)"

        NSUserNotificationCenter.default.deliver(notification)
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
    func detectParentApp(pid: Int) -> ParentApp {
        var currentPid = pid
        var depth = 0

        while currentPid > 1 && depth < 15 {
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
    func openSession(_ session: Session) {
        let parentApp = detectParentApp(pid: session.pid)
        let tty = getTTY(pid: session.pid)

        switch parentApp {
        case .terminal:
            activateTerminalTab(tty: tty)
        case .iterm:
            activateITermSession(tty: tty)
        case .warp:
            activateRunningApp("dev.warp.Warp-Stable")
        case .cursor:
            activateRunningApp("com.todesktop.230313mzl4w4u92")
        case .vscode:
            activateRunningApp("com.microsoft.VSCode")
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

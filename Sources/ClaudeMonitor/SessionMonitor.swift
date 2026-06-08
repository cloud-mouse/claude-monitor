import Foundation
import Combine

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
        let url = URL(fileURLWithPath: cwd)
        return url.lastPathComponent
    }

    /// 项目路径的简短显示（最多显示最后两级目录）
    var shortPath: String {
        let components = cwd.split(separator: "/")
        if components.count <= 2 {
            return cwd
        }
        return "..." + components.suffix(2).joined(separator: "/")
    }

    var isBusy: Bool { status == "busy" }
}

// MARK: - Session Status Color

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
            // 短暂延迟避免连续快速更新
            Thread.sleep(forTimeInterval: 0.2)
            DispatchQueue.main.async {
                self?.reloadSessions()
            }
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    private func startPolling() {
        // 每 2 秒轮询作为后备
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reloadSessions()
        }
    }

    // MARK: - Session Loading

    func reloadSessions() {
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            DispatchQueue.main.async { self.sessions = [] }
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

        DispatchQueue.main.async {
            let oldMap = Dictionary(uniqueKeysWithValues: self.sessions.map { ($0.pid, $0.status) })
            self.sessions = loaded

            // 检测状态变化并发送通知
            for session in loaded {
                if let oldStatus = oldMap[session.pid], oldStatus != session.status {
                    self.sendNotification(session: session, from: oldStatus)
                }
            }

            // 检测会话结束
            let currentPids = Set(loaded.map(\.pid))
            for (pid, status) in oldMap where !currentPids.contains(pid) {
                self.sendSessionEndNotification(pid: pid, lastStatus: status)
            }
        }
    }

    // MARK: - Notifications

    private func sendNotification(session: Session, from oldStatus: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"

        if session.isBusy {
            content.body = "\(session.projectName) 开始处理..."
        } else {
            content.body = "\(session.projectName) 已完成，等待输入"
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "claude-\(session.pid)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func sendSessionEndNotification(pid: Int, lastStatus: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "会话 \(pid) 已结束"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "claude-end-\(pid)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Quick Open

import AppKit

extension SessionMonitor {
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

        var bundleId: String? {
            switch self {
            case .terminal: return "com.apple.Terminal"
            case .iterm: return "com.googlecode.iterm2"
            case .warp: return "dev.warp.Warp-Stable"
            case .cursor: return "com.todesktop.230313mzl4w4u92"
            case .vscode: return "com.microsoft.VSCode"
            case .idea: return "com.jetbrains.intellij"
            case .unknown: return nil
            }
        }

        var icon: String {
            switch self {
            case .terminal: return "terminal"
            case .iterm: return "terminal"
            case .warp: return "terminal"
            case .cursor: return "cursor"
            case .vscode: return "vscode"
            case .idea: return "idea"
            case .unknown: return "terminal"
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

    /// 快捷打开会话所在的终端/IDE
    func openSession(_ session: Session) {
        let parentApp = detectParentApp(pid: session.pid)

        switch parentApp {
        case .cursor:
            openInApp("cursor", at: session.cwd)
        case .vscode:
            openInApp("code", at: session.cwd)
        case .idea:
            openInApp("idea", at: session.cwd)
        default:
            openTerminal(at: session.cwd)
        }
    }

    /// 在终端中打开指定路径
    func openTerminal(at path: String) {
        // 尝试检测最合适的终端
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

        // 最终后备：用 AppleScript 打开 Terminal
        openAppleTerminal(at: path)
    }

    /// 使用命令行工具打开 IDE
    func openInApp(_ command: String, at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, path]

        do {
            try process.run()
        } catch {
            // 如果命令行工具不可用，尝试用 bundle ID 打开
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

    /// 使用 AppleScript 打开 Terminal.app 并 cd 到指定目录
    private func openAppleTerminal(at path: String) {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) > 0 then
                do script "cd '\(escaped)'" in front window
            else
                do script "cd '\(escaped)'"
            end if
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
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

// MARK: - UNUserNotificationCenter

import UserNotifications

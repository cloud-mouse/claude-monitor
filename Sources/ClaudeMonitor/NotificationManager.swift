import Foundation
import AppKit
import UserNotifications

// MARK: - Monitored Event

/// 会话状态变化事件，由 SessionMonitor 发射
struct MonitoredEvent {
    let type: NotificationEventType
    let session: Session
    let previousDisplayStatus: DisplayStatus?
    let newDisplayStatus: DisplayStatus
}

// MARK: - Notification Manager

final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var settings: NotificationSettings

    private weak var monitor: SessionMonitor?
    private let queue = DispatchQueue(label: "com.claudemonitor.notifications", qos: .utility)

    /// 防抖：同一会话同一事件在 2 秒内不重复发送
    private var lastEventTime: [String: Date] = [:]

    init(monitor: SessionMonitor) {
        self.settings = NotificationSettings.load()
        self.monitor = monitor
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
    }

    // MARK: - Settings

    func updateSettings(_ transform: (inout NotificationSettings) -> Void) {
        transform(&settings)
        settings.save()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: MonitoredEvent) {
        guard settings.globalEnabled else { return }

        guard let eventConfig = settings.events[event.type],
              eventConfig.enabled
        else { return }

        // 项目过滤
        guard settings.projectFilter.matches(event.session.projectName) else { return }

        // 防抖
        let dedupKey = "\(event.session.pid)-\(event.type.rawValue)"
        if let lastTime = lastEventTime[dedupKey],
           Date().timeIntervalSince(lastTime) < 2.0 { return }
        lastEventTime[dedupKey] = Date()

        for channel in eventConfig.channels {
            switch channel {
            case .systemNotification:
                deliverSystemNotification(event, config: eventConfig)
            case .sound:
                playSound(config: eventConfig)
            case .webhook:
                fireWebhook(event)
            case .script:
                runScript(event)
            }
        }
    }

    // MARK: - System Notification

    private func deliverSystemNotification(_ event: MonitoredEvent, config: EventConfig) {
        // 优先尝试 UNUserNotificationCenter（需要签名 + 授权）
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                self.deliverUNNotification(event, config: config)
            } else {
                // 回退到 NSUserNotificationCenter（无需授权，未签名应用可用）
                self.deliverLegacyNotification(event, config: config)
            }
        }
    }

    private func deliverUNNotification(_ event: MonitoredEvent, config: EventConfig) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Monitor"
        content.subtitle = event.session.projectName
        content.body = describeEvent(event)
        content.threadIdentifier = "session-\(event.session.sessionId)"
        content.categoryIdentifier = "SESSION_EVENT"
        content.userInfo = [
            "pid": event.session.pid,
            "sessionId": event.session.sessionId,
            "cwd": event.session.cwd,
        ]

        let request = UNNotificationRequest(
            identifier: "claude-\(event.session.pid)-\(event.type.rawValue)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] UN通知失败: \(error.localizedDescription)")
            }
        }
    }

    @available(macOS, deprecated: 11.0, message: "Use UNUserNotificationCenter")
    private func deliverLegacyNotification(_ event: MonitoredEvent, config: EventConfig) {
        let notification = NSUserNotification()
        notification.title = "Claude Monitor"
        notification.subtitle = event.session.projectName
        notification.informativeText = describeEvent(event)
        notification.identifier = "claude-\(event.session.pid)-\(event.type.rawValue)"

        if config.channels.contains(.sound) {
            notification.soundName = NSUserNotificationDefaultSoundName
        }

        NSUserNotificationCenter.default.deliver(notification)
    }

    private func registerNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_SESSION",
            title: "打开项目",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "SESSION_EVENT",
            actions: [openAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Sound

    private func playSound(config: EventConfig) {
        if let soundName = config.soundName, !soundName.isEmpty {
            NSSound(named: soundName)?.play()
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Webhook

    private func fireWebhook(_ event: MonitoredEvent) {
        let config = settings.webhook
        guard !config.url.isEmpty, let url = URL(string: config.url) else { return }

        let body: String
        if config.bodyTemplate.isEmpty {
            let dict: [String: String] = [
                "event": event.type.rawValue,
                "project": event.session.projectName,
                "status": event.newDisplayStatus.label,
                "previousStatus": event.previousDisplayStatus?.label ?? "none",
                "path": event.session.cwd,
                "duration": formatDuration(event),
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                  let str = String(data: data, encoding: .utf8) else { return }
            body = str
        } else {
            body = substituteTemplate(config.bodyTemplate, event: event)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("[NotificationManager] Webhook 错误: \(error.localizedDescription)")
            }
        }.resume()
    }

    // MARK: - Script

    private func runScript(_ event: MonitoredEvent) {
        let config = settings.script
        guard !config.path.isEmpty else { return }

        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [config.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            if config.passAsEnvironment {
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "CLAUDE_EVENT": event.type.rawValue,
                    "CLAUDE_PROJECT": event.session.projectName,
                    "CLAUDE_STATUS": event.newDisplayStatus.label,
                    "CLAUDE_PREVIOUS_STATUS": event.previousDisplayStatus?.label ?? "none",
                    "CLAUDE_PATH": event.session.cwd,
                    "CLAUDE_SESSION_ID": event.session.sessionId,
                    "CLAUDE_PID": "\(event.session.pid)",
                    "CLAUDE_DURATION": self.formatDuration(event),
                ]) { $1 }
            } else {
                let pipe = Pipe()
                process.standardInput = pipe
                let json = self.buildEventJSON(event)
                if let data = json.data(using: .utf8) {
                    pipe.fileHandleForWriting.write(data)
                    try? pipe.fileHandleForWriting.close()
                }
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
            } catch {
                print("[NotificationManager] 脚本执行错误: \(error)")
            }
        }
    }

    // MARK: - Test Helpers

    /// 发送测试通知（从设置面板调用）
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Claude Monitor"
        content.subtitle = "测试项目"
        content.body = "这是一条测试通知 — 通知功能工作正常 ✅"
        content.sound = .default
        content.categoryIdentifier = "SESSION_EVENT"
        content.userInfo = ["test": true]

        let request = UNNotificationRequest(
            identifier: "claude-test-\(UUID().uuidString.prefix(8))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 发送测试 Webhook
    func sendTestWebhook() {
        guard !settings.webhook.url.isEmpty else { return }
        let testSession = Session(
            pid: 0, sessionId: "test-session", cwd: "/tmp/test-project",
            startedAt: Int64(Date().timeIntervalSince1970 * 1000 - 300_000),
            procStart: "", version: "test", peerProtocol: nil, kind: nil,
            entrypoint: nil, status: "idle",
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let event = MonitoredEvent(
            type: .taskCompleted, session: testSession,
            previousDisplayStatus: .busy, newDisplayStatus: .idle
        )
        fireWebhook(event)
    }

    /// 发送测试脚本
    func sendTestScript() {
        guard !settings.script.path.isEmpty else { return }
        let testSession = Session(
            pid: 0, sessionId: "test-session", cwd: "/tmp/test-project",
            startedAt: Int64(Date().timeIntervalSince1970 * 1000 - 300_000),
            procStart: "", version: "test", peerProtocol: nil, kind: nil,
            entrypoint: nil, status: "idle",
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let event = MonitoredEvent(
            type: .taskCompleted, session: testSession,
            previousDisplayStatus: .busy, newDisplayStatus: .idle
        )
        runScript(event)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if userInfo["test"] as? Bool == true {
            completionHandler()
            return
        }

        if response.actionIdentifier == UNNotificationDefaultActionIdentifier ||
           response.actionIdentifier == "OPEN_SESSION" {
            if let pid = userInfo["pid"] as? Int,
               let session = monitor?.sessions.first(where: { $0.pid == pid }) {
                monitor?.openSession(session)
            } else if let cwd = userInfo["cwd"] as? String {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
            }
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Helpers

    private func describeEvent(_ event: MonitoredEvent) -> String {
        switch event.type {
        case .taskCompleted:
            let dur = formatDuration(event)
            return "任务完成\(dur.isEmpty ? "" : " (\(dur))")"
        case .taskStarted:
            return "任务开始执行"
        case .needsAttention:
            return "等待你的输入"
        case .sessionStarted:
            return "会话已启动"
        case .sessionEnded:
            let dur = formatDuration(event)
            return "会话已结束\(dur.isEmpty ? "" : " (\(dur))")"
        case .error:
            return "会话发生错误"
        }
    }

    func formatDuration(_ event: MonitoredEvent) -> String {
        let startMs = event.session.startedAt
        let endMs: Int64
        if event.type == .sessionEnded || event.type == .taskCompleted {
            endMs = Int64(Date().timeIntervalSince1970 * 1000)
        } else {
            endMs = event.session.updatedAt
        }
        let seconds = max(0, (endMs - startMs) / 1000)
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        let remainSeconds = seconds % 60
        if minutes < 60 { return "\(minutes)分\(remainSeconds)秒" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)小时\(remainMinutes)分"
    }

    private func substituteTemplate(_ template: String, event: MonitoredEvent) -> String {
        var result = template
        let replacements: [String: String] = [
            "{project}": event.session.projectName,
            "{status}": event.newDisplayStatus.label,
            "{previousStatus}": event.previousDisplayStatus?.label ?? "none",
            "{duration}": formatDuration(event),
            "{path}": event.session.cwd,
            "{sessionId}": event.session.sessionId,
            "{pid}": "\(event.session.pid)",
            "{event}": event.type.rawValue,
        ]
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    private func buildEventJSON(_ event: MonitoredEvent) -> String {
        let dict: [String: String] = [
            "event": event.type.rawValue,
            "project": event.session.projectName,
            "status": event.newDisplayStatus.label,
            "previousStatus": event.previousDisplayStatus?.label ?? "none",
            "path": event.session.cwd,
            "sessionId": event.session.sessionId,
            "pid": "\(event.session.pid)",
            "duration": formatDuration(event),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

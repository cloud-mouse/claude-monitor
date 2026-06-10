import Foundation

// MARK: - Event Types

/// 触发通知的事件类型
enum NotificationEventType: String, Codable, CaseIterable {
    case taskCompleted     // busy -> idle：任务完成
    case taskStarted       // idle -> busy：任务开始
    case needsAttention    // 进入待确认状态（权限提示 / 新输出）
    case sessionStarted    // 新会话出现
    case sessionEnded      // 会话结束
    case error             // 会话出错

    var label: String {
        switch self {
        case .taskCompleted:  return "任务完成"
        case .taskStarted:    return "任务开始"
        case .needsAttention: return "待确认"
        case .sessionStarted: return "会话启动"
        case .sessionEnded:   return "会话结束"
        case .error:          return "发生错误"
        }
    }

    var description: String {
        switch self {
        case .taskCompleted:  return "Claude 完成任务，等待下一条指令"
        case .taskStarted:    return "Claude 开始执行任务"
        case .needsAttention: return "Claude 等待用户授权或确认"
        case .sessionStarted: return "新的 Claude Code 会话启动"
        case .sessionEnded:   return "Claude Code 会话已结束"
        case .error:          return "Claude Code 会话遇到错误"
        }
    }
}

// MARK: - Channel Types

/// 通知渠道
enum NotificationChannel: String, Codable, CaseIterable {
    case systemNotification  // macOS 系统通知
    case sound               // 声音提醒
    case webhook             // HTTP POST（飞书 / Slack 等）
    case script              // 自定义脚本

    var label: String {
        switch self {
        case .systemNotification: return "系统通知"
        case .sound:              return "声音"
        case .webhook:            return "Webhook"
        case .script:             return "脚本"
        }
    }
}

// MARK: - Per-Event Configuration

/// 单个事件的通知配置
struct EventConfig: Codable, Equatable {
    var enabled: Bool
    var channels: [NotificationChannel]
    var soundName: String?

    static func defaults(for type: NotificationEventType) -> EventConfig {
        switch type {
        case .taskCompleted:
            return EventConfig(enabled: true, channels: [.systemNotification, .sound], soundName: nil)
        case .needsAttention:
            return EventConfig(enabled: true, channels: [.systemNotification, .sound], soundName: nil)
        case .sessionEnded:
            return EventConfig(enabled: true, channels: [.systemNotification], soundName: nil)
        default:
            return EventConfig(enabled: false, channels: [.systemNotification], soundName: nil)
        }
    }
}

// MARK: - Webhook Configuration

struct WebhookConfig: Codable, Equatable {
    var url: String = ""
    var bodyTemplate: String = ""
    var contentType: String = "application/json"

    /// 默认飞书卡片模板
    static var defaultTemplate: String {
        """
        {"msg_type":"interactive","card":{"elements":[{"tag":"div","text":{"tag":"plain_text","content":"🤖 {project}: {status}"}}]}}
        """
    }
}

// MARK: - Script Configuration

struct ScriptConfig: Codable, Equatable {
    var path: String = ""
    /// true = 环境变量传参，false = stdin JSON
    var passAsEnvironment: Bool = true
}

// MARK: - Project Filter

struct ProjectFilter: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        case all
        case include
        case exclude

        var label: String {
            switch self {
            case .all:     return "所有项目"
            case .include: return "仅包含"
            case .exclude: return "排除"
            }
        }
    }

    var mode: Mode = .all
    /// 项目名称列表（用于 include/exclude 匹配）
    var projects: [String] = []

    func matches(_ projectName: String) -> Bool {
        switch mode {
        case .all:
            return true
        case .include:
            return projects.contains(projectName)
        case .exclude:
            return !projects.contains(projectName)
        }
    }
}

// MARK: - Notification Settings

struct NotificationSettings: Codable, Equatable {
    var globalEnabled: Bool = true
    var events: [NotificationEventType: EventConfig]
    var webhook: WebhookConfig = WebhookConfig()
    var script: ScriptConfig = ScriptConfig()
    var projectFilter: ProjectFilter = ProjectFilter()

    private static let storageKey = "ClaudeMonitor.notificationSettings"

    init() {
        var events: [NotificationEventType: EventConfig] = [:]
        for type in NotificationEventType.allCases {
            events[type] = EventConfig.defaults(for: type)
        }
        self.events = events
    }

    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return NotificationSettings()
        }
        do {
            return try JSONDecoder().decode(NotificationSettings.self, from: data)
        } catch {
            print("[NotificationSettings] Failed to decode settings: \(error)")
            return NotificationSettings()
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("[NotificationSettings] Failed to encode settings: \(error)")
        }
    }
}

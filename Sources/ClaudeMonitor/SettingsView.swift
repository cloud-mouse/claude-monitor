import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MasterToggleSection()
                Divider()
                EventsSection()
                Divider()
                SoundSection()
                Divider()
                WebhookSection()
                Divider()
                ScriptSection()
                Divider()
                ProjectFilterSection()
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 480)
        .environmentObject(notificationManager)
    }
}

// MARK: - Master Toggle

private struct MasterToggleSection: View {
    @EnvironmentObject var nm: NotificationManager

    var body: some View {
        HStack {
            Image(systemName: "bell.fill")
                .foregroundColor(nm.settings.globalEnabled ? .green : .secondary)
            Text("启用消息通知")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Toggle("", isOn: Binding(
                get: { nm.settings.globalEnabled },
                set: { val in nm.updateSettings { $0.globalEnabled = val } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .opacity(nm.settings.globalEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Events Section

private struct EventsSection: View {
    @EnvironmentObject var nm: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "list.bullet.clipboard", title: "事件规则")

            ForEach(NotificationEventType.allCases, id: \.self) { eventType in
                EventRow(eventType: eventType)
            }
        }
    }
}

private struct EventRow: View {
    let eventType: NotificationEventType
    @EnvironmentObject var nm: NotificationManager

    private var config: EventConfig {
        nm.settings.events[eventType] ?? EventConfig.defaults(for: eventType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: Binding(
                    get: { config.enabled },
                    set: { newVal in
                        nm.updateSettings { settings in
                            settings.events[eventType]?.enabled = newVal
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(eventType.label)
                            .font(.system(size: 13, weight: .medium))
                        Text(eventType.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            if config.enabled {
                ChannelPicker(eventType: eventType, config: config)
                    .padding(.leading, 49)
            }
        }
    }
}

private struct ChannelPicker: View {
    let eventType: NotificationEventType
    let config: EventConfig
    @EnvironmentObject var nm: NotificationManager

    var body: some View {
        HStack(spacing: 12) {
            ForEach(NotificationChannel.allCases, id: \.self) { channel in
                ChannelChip(
                    channel: channel,
                    isOn: config.channels.contains(channel),
                    onToggle: { enable in
                        nm.updateSettings { settings in
                            var channels = settings.events[eventType]?.channels ?? []
                            if enable {
                                if !channels.contains(channel) { channels.append(channel) }
                            } else {
                                channels.removeAll { $0 == channel }
                            }
                            settings.events[eventType]?.channels = channels
                        }
                    }
                )
            }
        }
    }
}

private struct ChannelChip: View {
    let channel: NotificationChannel
    let isOn: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button(action: { onToggle(!isOn) }) {
            HStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.system(size: 9))
                Text(channel.label)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
            .foregroundColor(isOn ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch channel {
        case .systemNotification: return "bell"
        case .sound: return "speaker.wave.2"
        case .webhook: return "network"
        case .script: return "terminal"
        }
    }
}

// MARK: - Sound Section

private struct SoundSection: View {
    @EnvironmentObject var nm: NotificationManager
    @State private var availableSounds: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "speaker.wave.2", title: "声音")

            HStack {
                Text("提示音")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: Binding(
                    get: { nm.settings.events[.taskCompleted]?.soundName ?? "default" },
                    set: { val in nm.updateSettings { settings in
                        for key in settings.events.keys {
                            settings.events[key]?.soundName = val == "default" ? nil : val
                        }
                    }}
                )) {
                    Text("默认").tag("default")
                    ForEach(availableSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .frame(width: 150)
            }

            Button("测试声音") {
                NSSound.beep()
            }
            .font(.system(size: 11))
        }
        .onAppear {
            loadSounds()
        }
    }

    private func loadSounds() {
        let soundDir = "/System/Library/Sounds"
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: soundDir) {
            availableSounds = files
                .filter { $0.hasSuffix(".aiff") }
                .map { $0.replacingOccurrences(of: ".aiff", with: "") }
                .sorted()
        }
    }
}

// MARK: - Webhook Section

private struct WebhookSection: View {
    @EnvironmentObject var nm: NotificationManager
    @State private var testResult: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "network", title: "Webhook")

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 12, weight: .medium))
                TextField("https://open.feishu.cn/open-apis/bot/v2/hook/...", text: Binding(
                    get: { nm.settings.webhook.url },
                    set: { val in nm.updateSettings { $0.webhook.url = val } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Body 模板")
                    .font(.system(size: 12, weight: .medium))
                TextEditor(text: Binding(
                    get: { nm.settings.webhook.bodyTemplate },
                    set: { val in nm.updateSettings { $0.webhook.bodyTemplate = val } }
                ))
                .font(.system(size: 10, design: .monospaced))
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

                Text("可用变量: {project} {status} {previousStatus} {duration} {path} {event} {sessionId} {pid}")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("使用默认模板") {
                    nm.updateSettings { $0.webhook.bodyTemplate = WebhookConfig.defaultTemplate }
                }
                .font(.system(size: 11))

                Spacer()

                Button("测试 Webhook") {
                    testResult = "发送中…"
                    nm.sendTestWebhook { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success: testResult = "✅ 发送成功"
                            case .failure(let error): testResult = "❌ \(error.localizedDescription)"
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { testResult = "" }
                        }
                    }
                }
                .font(.system(size: 11))
                .disabled(nm.settings.webhook.url.isEmpty)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Script Section

private struct ScriptSection: View {
    @EnvironmentObject var nm: NotificationManager
    @State private var testResult: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "terminal", title: "自定义脚本")

            VStack(alignment: .leading, spacing: 4) {
                Text("脚本路径")
                    .font(.system(size: 12, weight: .medium))
                TextField("/path/to/script.sh", text: Binding(
                    get: { nm.settings.script.path },
                    set: { val in nm.updateSettings { $0.script.path = val } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("传参方式")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: Binding(
                    get: { nm.settings.script.passAsEnvironment },
                    set: { val in nm.updateSettings { $0.script.passAsEnvironment = val } }
                )) {
                    Text("环境变量").tag(true)
                    Text("stdin JSON").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            if nm.settings.script.passAsEnvironment {
                VStack(alignment: .leading, spacing: 2) {
                    Text("可用环境变量:")
                        .font(.system(size: 10, weight: .medium))
                    Text("CLAUDE_EVENT, CLAUDE_PROJECT, CLAUDE_STATUS, CLAUDE_PREVIOUS_STATUS, CLAUDE_PATH, CLAUDE_SESSION_ID, CLAUDE_PID, CLAUDE_DURATION")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("测试脚本") {
                    testResult = "执行中…"
                    nm.sendTestScript { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success: testResult = "✅ 执行成功"
                            case .failure(let error): testResult = "❌ \(error.localizedDescription)"
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { testResult = "" }
                        }
                    }
                }
                .font(.system(size: 11))
                .disabled(nm.settings.script.path.isEmpty)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Project Filter Section

private struct ProjectFilterSection: View {
    @EnvironmentObject var nm: NotificationManager
    @State private var projectText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "folder.badge.gearshape", title: "项目过滤")

            Picker("", selection: Binding(
                get: { nm.settings.projectFilter.mode },
                set: { val in nm.updateSettings { $0.projectFilter.mode = val } }
            )) {
                ForEach(ProjectFilter.Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if nm.settings.projectFilter.mode != .all {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目名称（逗号分隔）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("project-a, project-b", text: $projectText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: projectText) { newText in
                            let projects = newText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            nm.updateSettings { $0.projectFilter.projects = projects }
                        }
                }
            }
        }
        .onAppear {
            projectText = nm.settings.projectFilter.projects.joined(separator: ", ")
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

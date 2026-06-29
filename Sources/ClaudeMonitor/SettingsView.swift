import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard { MasterToggleSection() }
                SettingsCard { EventsSection() }
                SettingsCard { SoundSection() }
                SettingsCard { WebhookSection() }
                SettingsCard { ScriptSection() }
                SettingsCard { ProjectFilterSection() }
            }
            .padding(22)
        }
        .frame(minWidth: 400, minHeight: 480)
        .background(SettingsGlass.windowBackground)
        .environmentObject(notificationManager)
    }
}

// MARK: - Signal Glass Settings Tokens

private enum SettingsGlass {
    static let accent = Color(red: 0.24, green: 0.83, blue: 0.78)
    static let ink = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let muted = Color(red: 0.38, green: 0.42, blue: 0.48)
    static let panel = Color.white.opacity(0.72)
    static let panelStroke = Color.black.opacity(0.08)
    static let windowBackground = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.97, blue: 0.96),
            Color(red: 0.89, green: 0.93, blue: 0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SettingsGlass.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(SettingsGlass.panelStroke, lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.055), radius: 18, x: 0, y: 8)
            )
    }
}

private struct GlassInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.64))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
                    )
            )
    }
}

private struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(SettingsGlass.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.62))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7))
            )
    }
}

// MARK: - Master Toggle

private struct MasterToggleSection: View {
    @EnvironmentObject var nm: NotificationManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(nm.settings.globalEnabled ? SettingsGlass.accent : SettingsGlass.muted)
                .frame(width: 30, height: 30)
                .background(Circle().fill(SettingsGlass.accent.opacity(nm.settings.globalEnabled ? 0.16 : 0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text("启用消息通知")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsGlass.ink)
                Text("统一控制系统通知、声音、Webhook 与脚本")
                    .font(.system(size: 11))
                    .foregroundColor(SettingsGlass.muted)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { nm.settings.globalEnabled },
                set: { val in nm.updateSettings { $0.globalEnabled = val } }
            ))
            .toggleStyle(.switch)
            .tint(SettingsGlass.accent)
            .labelsHidden()
        }
        .opacity(nm.settings.globalEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Events Section

private struct EventsSection: View {
    @EnvironmentObject var nm: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
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
        VStack(alignment: .leading, spacing: 8) {
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SettingsGlass.ink)
                        Text(eventType.description)
                            .font(.system(size: 11))
                            .foregroundColor(SettingsGlass.muted)
                    }
                }
                .toggleStyle(.switch)
                .tint(SettingsGlass.accent)
            }

            if config.enabled {
                ChannelPicker(eventType: eventType, config: config)
                    .padding(.leading, 48)
            }
        }
    }
}

private struct ChannelPicker: View {
    let eventType: NotificationEventType
    let config: EventConfig
    @EnvironmentObject var nm: NotificationManager

    var body: some View {
        HStack(spacing: 8) {
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
                    .font(.system(size: 9, weight: .semibold))
                Text(channel.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isOn ? SettingsGlass.accent.opacity(0.18) : Color.white.opacity(0.52))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isOn ? SettingsGlass.accent.opacity(0.55) : Color.black.opacity(0.10), lineWidth: 0.7)
            )
            .foregroundColor(isOn ? SettingsGlass.ink : SettingsGlass.muted)
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "speaker.wave.2", title: "声音")

            HStack {
                Text("提示音")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SettingsGlass.ink)
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
            .modifier(GlassButtonModifier())
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "network", title: "Webhook")

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SettingsGlass.ink)
                TextField("https://open.feishu.cn/open-apis/bot/v2/hook/...", text: Binding(
                    get: { nm.settings.webhook.url },
                    set: { val in nm.updateSettings { $0.webhook.url = val } }
                ))
                .font(.system(size: 12, design: .monospaced))
                .modifier(GlassInputModifier())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Body 模板")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SettingsGlass.ink)
                TextEditor(text: Binding(
                    get: { nm.settings.webhook.bodyTemplate },
                    set: { val in nm.updateSettings { $0.webhook.bodyTemplate = val } }
                ))
                .font(.system(size: 10, design: .monospaced))
                .frame(height: 60)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.64))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("可用变量: {project} {status} {previousStatus} {duration} {path} {event} {sessionId} {pid}")
                    .font(.system(size: 10))
                    .foregroundColor(SettingsGlass.muted)
            }

            HStack {
                Button("使用默认模板") {
                    nm.updateSettings { $0.webhook.bodyTemplate = WebhookConfig.defaultTemplate }
                }
                .modifier(GlassButtonModifier())

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
                .modifier(GlassButtonModifier())
                .disabled(nm.settings.webhook.url.isEmpty)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.system(size: 10))
                        .foregroundColor(SettingsGlass.muted)
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "terminal", title: "自定义脚本")

            VStack(alignment: .leading, spacing: 4) {
                Text("脚本路径")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SettingsGlass.ink)
                TextField("/path/to/script.sh", text: Binding(
                    get: { nm.settings.script.path },
                    set: { val in nm.updateSettings { $0.script.path = val } }
                ))
                .font(.system(size: 12, design: .monospaced))
                .modifier(GlassInputModifier())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("传参方式")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SettingsGlass.ink)
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
                        .foregroundColor(SettingsGlass.ink)
                    Text("CLAUDE_EVENT, CLAUDE_PROJECT, CLAUDE_STATUS, CLAUDE_PREVIOUS_STATUS, CLAUDE_PATH, CLAUDE_SESSION_ID, CLAUDE_PID, CLAUDE_DURATION")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(SettingsGlass.muted)
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
                .modifier(GlassButtonModifier())
                .disabled(nm.settings.script.path.isEmpty)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.system(size: 10))
                        .foregroundColor(SettingsGlass.muted)
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
        VStack(alignment: .leading, spacing: 12) {
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
                        .foregroundColor(SettingsGlass.muted)
                    TextField("project-a, project-b", text: $projectText)
                        .font(.system(size: 12))
                        .modifier(GlassInputModifier())
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SettingsGlass.accent)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SettingsGlass.ink)
        }
    }
}

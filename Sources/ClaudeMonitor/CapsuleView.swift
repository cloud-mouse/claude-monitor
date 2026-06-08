import SwiftUI

// MARK: - Capsule View (Root)

struct CapsuleView: View {
    @ObservedObject var monitor: SessionMonitor
    @State private var hoveredSession: Int?

    var body: some View {
        HStack(spacing: 0) {
            // Claude 标识图标
            claudeIcon

            // 分隔线
            CapsuleDivider()

            // 会话列表
            if monitor.sessions.isEmpty {
                emptyState
            } else if monitor.sessions.count == 1 {
                singleSessionView(monitor.sessions[0])
            } else {
                multiSessionView
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(capsuleBackground)
    }

    // MARK: - Claude Icon

    private var claudeIcon: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.8), .indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 28, height: 28)
            .overlay(
                Text("C")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
            .padding(.trailing, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.gray.opacity(0.6))
                .frame(width: 8, height: 8)

            Text("No Claude sessions")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Single Session

    private func singleSessionView(_ session: Session) -> some View {
        SessionPill(session: session, isSingle: true) {
            monitor.openSession(session)
        }
        .contextMenu {
            sessionContextMenu(session)
        }
    }

    // MARK: - Multi Session

    private var multiSessionView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(monitor.sessions) { session in
                    SessionPill(session: session, isSingle: false) {
                        monitor.openSession(session)
                    }
                    .contextMenu {
                        sessionContextMenu(session)
                    }
                }
            }
        }
        .frame(maxWidth: 350)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        Button("打开所在终端 / IDE") {
            monitor.openSession(session)
        }

        Divider()

        Button("在 Terminal 中打开") {
            monitor.openTerminal(at: session.cwd)
        }

        let parentApp = monitor.detectParentApp(pid: session.pid)
        if parentApp == .cursor || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil {
            Button("在 Cursor 中打开") {
                monitor.openInApp("cursor", at: session.cwd)
            }
        }

        if parentApp == .vscode || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil {
            Button("在 VS Code 中打开") {
                monitor.openInApp("code", at: session.cwd)
            }
        }

        Divider()

        Button("在 Finder 中显示") {
            NSWorkspace.shared.selectFile(session.cwd, inFileViewerRootedAtPath: "")
        }

        Button("拷贝路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.cwd, forType: .string)
        }
    }

    // MARK: - Background (由 NSVisualEffectView 提供，这里只用描边)

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: 25, style: .continuous)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Session Pill

struct SessionPill: View {
    let session: Session
    let isSingle: Bool
    let onTap: () -> Void

    @State private var isPulsing = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // 状态指示灯
            statusDot

            // 项目名
            Text(isSingle ? session.shortPath : session.projectName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            // 单会话模式显示状态文字
            if isSingle {
                Text(session.isBusy ? "处理中..." : "空闲")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(statusColor.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(pillBackground)
        .clipShape(Capsule())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            isPulsing = session.isBusy
        }
        .onChange(of: session.status) { newStatus in
            withAnimation(.easeInOut(duration: 0.3)) {
                isPulsing = newStatus == "busy"
            }
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: isSingle ? 10 : 8, height: isSingle ? 10 : 8)
            .overlay(
                Circle()
                    .fill(statusColor.opacity(0.4))
                    .frame(width: isSingle ? 16 : 14, height: isSingle ? 16 : 14)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            )
            .shadow(color: statusColor.opacity(0.5), radius: isPulsing ? 6 : 2)
    }

    // MARK: - Colors

    private var statusColor: Color {
        switch session.status {
        case "busy": return .orange
        case "idle": return .green
        default: return .gray
        }
    }

    // MARK: - Background

    private var pillBackground: some View {
        Capsule()
            .fill(statusColor.opacity(isHovered ? 0.2 : 0.12))
    }
}

// MARK: - Divider

struct CapsuleDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 20)
            .padding(.trailing, 4)
    }
}

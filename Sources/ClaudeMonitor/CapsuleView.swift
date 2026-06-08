import SwiftUI

// MARK: - Capsule View

struct CapsuleView: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        HStack(spacing: 4) {
            if monitor.sessions.isEmpty {
                emptyState
            } else {
                ForEach(monitor.sessions) { session in
                    SessionPill(session: session) {
                        monitor.openSession(session)
                    }
                    .contextMenu { sessionContextMenu(session) }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .fixedSize()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text("No sessions")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        Button("切换到所在窗口") { monitor.openSession(session) }
        Divider()
        Button("在 Terminal 中打开") { monitor.openTerminal(at: session.cwd) }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil {
            Button("在 Cursor 中打开") { monitor.openInApp("cursor", at: session.cwd) }
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil {
            Button("在 VS Code 中打开") { monitor.openInApp("code", at: session.cwd) }
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
}

// MARK: - Session Pill

struct SessionPill: View {
    let session: Session
    let onTap: () -> Void

    @State private var isPulsing = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            // 状态灯
            statusDot
                .frame(width: 7, height: 7)

            // 项目名
            Text(session.projectName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(pillBackground)
        .clipShape(Capsule())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onAppear { isPulsing = session.isBusy }
        .onChange(of: session.status) { newStatus in
            withAnimation(.easeInOut(duration: 0.3)) { isPulsing = newStatus == "busy" }
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        ZStack {
            // 脉冲光环
            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(isPulsing ? 1.6 : 0.8)
                .opacity(isPulsing ? 0 : 0.5)

            // 实心灯
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(isPulsing ? 0.6 : 0.3), radius: isPulsing ? 4 : 1)
        }
        .animation(isPulsing ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isPulsing)
    }

    private var statusColor: Color {
        switch session.status {
        case "busy": return Color(red: 1.0, green: 0.65, blue: 0.2)   // 温暖橙
        case "idle": return Color(red: 0.35, green: 0.85, blue: 0.45)  // 清新绿
        default: return Color.gray
        }
    }

    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(statusColor.opacity(isHovered ? 0.15 : 0.06))
            )
    }
}

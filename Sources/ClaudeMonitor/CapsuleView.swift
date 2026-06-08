import SwiftUI

// MARK: - Display Status

/// 精细化的会话显示状态
enum DisplayStatus {
    case busy            // 🟠 繁忙：Claude 正在执行任务
    case needsAttention  // 🔴 需要确认：刚变为 idle，很可能需要用户授权/确认
    case idle            // 🟢 空闲：任务完成，等待下一条指令
    case offline         // ⚪ 离线：进程已结束

    var color: Color {
        switch self {
        case .busy:           return Color(red: 1.0, green: 0.6, blue: 0.15)  // 温暖橙
        case .needsAttention: return Color(red: 1.0, green: 0.25, blue: 0.25) // 警示红
        case .idle:           return Color(red: 0.3, green: 0.78, blue: 0.42)  // 清新绿
        case .offline:        return Color.gray
        }
    }

    var label: String {
        switch self {
        case .busy:           return "处理中"
        case .needsAttention: return "待确认"
        case .idle:           return "空闲"
        case .offline:        return "离线"
        }
    }

    var shouldBlink: Bool {
        switch self {
        case .needsAttention: return true
        default: return false
        }
    }
}

// MARK: - Session + DisplayStatus

extension Session {
    /// 计算显示状态（优先使用 hooks 精准状态，后备使用时间估算）
    /// - Parameter now: 当前时间戳（毫秒）
    func displayStatus(now: Int64) -> DisplayStatus {
        // 1. 优先使用 hooks 精准状态（需要安装 hooks）
        if let hook = hookStatus {
            switch hook {
            case "tool_call":          return .busy            // 🟠 正在调用工具
            case "waiting_permission": return .needsAttention  // 🔴 等待用户授权
            case "stopped":            return .idle            // 🟢 完成响应
            case "error":              return .offline         // ⚪ 出错
            default: break
            }
        }

        // 2. 后备：基于 session JSON 的 status + 时间估算
        switch status {
        case "busy":
            return .busy
        case "idle":
            let idleMs = now - updatedAt
            if idleMs < 30_000 {
                return .needsAttention   // 刚变为 idle，可能需要确认
            }
            return .idle                 // 闲置超过 30 秒，任务完成
        default:
            return .offline
        }
    }
}

// MARK: - Capsule View

struct CapsuleView: View {
    @ObservedObject var monitor: SessionMonitor

    /// 当前时间戳（毫秒），每秒刷新一次用于计算 displayStatus
    @State private var now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    var body: some View {
        HStack(spacing: 4) {
            if monitor.sessions.isEmpty {
                emptyState
            } else {
                ForEach(monitor.sessions) { session in
                    let status = session.displayStatus(now: now)
                    SessionPill(session: session, displayStatus: status) {
                        monitor.openSession(session)
                    }
                    .contextMenu { sessionContextMenu(session) }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .fixedSize()
        .onAppear { updateTime() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateTime()
        }
    }

    private func updateTime() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
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
    let displayStatus: DisplayStatus
    let onTap: () -> Void

    @State private var isBlinking = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            // 状态灯
            statusDot

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
        .onAppear {
            isBlinking = displayStatus.shouldBlink
        }
        .onChange(of: displayStatus) { newStatus in
            withAnimation(.easeInOut(duration: 0.3)) {
                isBlinking = newStatus.shouldBlink
            }
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        ZStack {
            // 外圈脉冲光环（需要确认时闪烁）
            Circle()
                .fill(displayStatus.color.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(isBlinking ? 2.0 : 0.5)
                .opacity(isBlinking ? 0 : 0.4)

            // 实心灯
            Circle()
                .fill(displayStatus.color)
                .frame(width: 7, height: 7)
                .shadow(color: displayStatus.color.opacity(isBlinking ? 0.8 : 0.25), radius: isBlinking ? 6 : 1)
        }
        .animation(
            isBlinking
                ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.3),
            value: isBlinking
        )
    }

    // MARK: - Pill Background

    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(displayStatus.color.opacity(isHovered ? 0.15 : 0.06))
            )
    }
}

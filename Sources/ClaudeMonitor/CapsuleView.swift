import SwiftUI
import AppKit

// MARK: - Display Status

/// 精细化的会话显示状态
enum DisplayStatus: Int {
    case needsAttention = 0  // 🔴 需要确认：等待用户授权/确认
    case busy            = 1 // 🟠 繁忙：Claude 正在执行任务
    case idle            = 2 // 🟢 空闲：任务完成，等待下一条指令
    case offline         = 3 // ⚪ 离线：进程已结束

    var color: Color {
        switch self {
        case .busy:           return SignalGlass.busy
        case .needsAttention: return SignalGlass.attention
        case .idle:           return SignalGlass.idle
        case .offline:        return SignalGlass.offline
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

// MARK: - Signal Glass Design Tokens

private enum SignalGlass {
    static let shellTop = Color(red: 0.13, green: 0.16, blue: 0.20)
    static let shellBottom = Color(red: 0.04, green: 0.07, blue: 0.08)
    static let accent = Color(red: 0.24, green: 0.83, blue: 0.78)
    static let busy = Color(red: 1.0, green: 0.62, blue: 0.18)
    static let attention = Color(red: 1.0, green: 0.30, blue: 0.36)
    static let idle = Color(red: 0.21, green: 0.78, blue: 0.42)
    static let offline = Color(red: 0.61, green: 0.64, blue: 0.69)
    static let text = Color.white.opacity(0.92)
    static let mutedText = Color.white.opacity(0.58)
}

// MARK: - Session + DisplayStatus

extension Session {
    /// 计算显示状态（优先使用 hooks 精准状态，后备使用时间估算）
    func displayStatus(now: Int64) -> DisplayStatus {
        if let hook = hookStatus {
            switch hook {
            case "tool_call":
                // Hook 说在调用工具，但 session 可能已经变为 idle/waiting
                // 此时信任 session 状态（Claude 已完成当前工具调用，等待下一步）
                if status == "idle" {
                    let idleMs = now - updatedAt
                    if idleMs < 30_000 {
                        return .needsAttention
                    }
                    return .idle
                }
                if status == "waiting" {
                    return .needsAttention
                }
                return .busy
            case "waiting_permission": return .needsAttention
            case "waiting_input":      return .needsAttention
            case "stopped":            return .idle
            case "error":              return .offline
            default: break
            }
        }

        switch status {
        case "busy":
            return .busy
        case "idle":
            let idleMs = now - updatedAt
            if idleMs < 30_000 {
                return .needsAttention
            }
            return .idle
        case "waiting":
            return .needsAttention
        default:
            return .offline
        }
    }
}

// MARK: - Sorted Session Helper

private struct SortedSession: Identifiable {
    let session: Session
    let status: DisplayStatus
    var id: Int { session.pid }
}

// MARK: - Signal Glass Shell

private struct SignalGlassShell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                SignalGlass.shellTop.opacity(0.82),
                                SignalGlass.shellBottom.opacity(0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(SignalGlass.accent.opacity(0.08), lineWidth: 1.4)
                            .blur(radius: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 12)
                    .shadow(color: SignalGlass.accent.opacity(0.08), radius: 22, x: 0, y: 0)
            )
    }
}

// MARK: - Scroll Notification

extension Notification.Name {
    static let capsuleScroll = Notification.Name("capsuleScroll")
}

// MARK: - Content Width Preference Key

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Mini Scroll Bar

struct MiniScrollBar: View {
    let trackWidth: CGFloat
    let contentWidth: CGFloat
    let visibleWidth: CGFloat
    @Binding var offset: CGFloat

    @State private var dragStartOffset: CGFloat = 0
    @State private var dragActive: Bool = false

    private var maxScroll: CGFloat { max(0, contentWidth - visibleWidth) }
    private var thumbWidth: CGFloat {
        max(10, trackWidth * min(1, visibleWidth / contentWidth))
    }

    private var thumbX: CGFloat {
        guard maxScroll > 0 else { return 0 }
        return (-offset / maxScroll) * (trackWidth - thumbWidth)
    }

    var body: some View {
        Capsule()
            .fill(SignalGlass.accent.opacity(0.45))
            .frame(width: thumbWidth, height: 3)
            .offset(x: thumbX)
            .frame(width: trackWidth, height: 5, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !dragActive {
                            dragStartOffset = offset
                            dragActive = true
                        }
                        let thumbRange = trackWidth - thumbWidth
                        guard thumbRange > 0, maxScroll > 0 else { return }
                        let startThumbX = (-dragStartOffset / maxScroll) * thumbRange
                        let newThumbX = max(0, min(startThumbX + value.translation.width, thumbRange))
                        offset = -(newThumbX / thumbRange) * maxScroll
                    }
                    .onEnded { _ in dragActive = false }
            )
    }
}

// MARK: - Capsule View

struct CapsuleView: View {
    @ObservedObject var monitor: SessionMonitor

    @State private var now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    // 滚动状态
    @State private var scrollOffset: CGFloat = 0
    @State private var measuredContentWidth: CGFloat = 0
    @State private var contentDragStart: CGFloat = 0
    @State private var contentDragActive: Bool = false

    private let scrollVisibleWidth: CGFloat = 224

    /// 按优先级排序的会话列表
    private var sortedSessions: [SortedSession] {
        monitor.sessions.map { s in
            SortedSession(session: s, status: s.displayStatus(now: now))
        }
        .sorted { a, b in
            if a.status.rawValue != b.status.rawValue {
                return a.status.rawValue < b.status.rawValue
            }
            return a.session.updatedAt > b.session.updatedAt
        }
    }

    var body: some View {
        Group {
            if monitor.sessions.isEmpty {
                emptyState
            } else {
                islandContent
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { updateTime() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateTime()
        }
        .onChange(of: monitor.sessions.count) { _ in
            scrollOffset = 0
        }
    }

    private func updateTime() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Island Content

    @ViewBuilder
    private var islandContent: some View {
        let sorted = sortedSessions

        if measuredContentWidth > scrollVisibleWidth {
            scrollableCards(sorted)
                .modifier(SignalGlassShell())
        } else {
            cardStack(sorted)
                .fixedSize()
                .background(contentWidthReader)
                .modifier(SignalGlassShell())
        }
    }

    // MARK: - Scrollable Cards (content overflows)

    private func scrollableCards(_ sorted: [SortedSession]) -> some View {
        VStack(spacing: 4) {
            // 卡片区域
            ZStack(alignment: .leading) {
                cardStack(sorted)
                    .fixedSize()
                    .background(contentWidthReader)
                    .offset(x: scrollOffset)
            }
            .frame(width: scrollVisibleWidth, alignment: .leading)
            .clipped()
            .padding(.horizontal, 2)
            .padding(.top, 1)
            .simultaneousGesture(contentDragGesture)

            // 迷你滚动条
            MiniScrollBar(
                trackWidth: min(50, scrollVisibleWidth - 20),
                contentWidth: measuredContentWidth,
                visibleWidth: scrollVisibleWidth,
                offset: $scrollOffset
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleScroll)) { note in
            if let delta = note.userInfo?["delta"] as? CGFloat {
                let maxS = max(0, measuredContentWidth - scrollVisibleWidth)
                scrollOffset = max(-maxS, min(0, scrollOffset + delta))
            }
        }
    }

    private var contentWidthReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ContentWidthKey.self, value: geo.size.width)
        }
        .onPreferenceChange(ContentWidthKey.self) { measuredContentWidth = $0 }
    }

    private var contentDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !contentDragActive {
                    contentDragStart = scrollOffset
                    contentDragActive = true
                }
                let maxS = max(0, measuredContentWidth - scrollVisibleWidth)
                scrollOffset = max(-maxS, min(0, contentDragStart + value.translation.width))
            }
            .onEnded { _ in contentDragActive = false }
    }

    private func cardStack(_ sorted: [SortedSession]) -> some View {
        let primaryId = sorted.first?.id

        return HStack(spacing: 7) {
            ForEach(sorted) { item in
                SessionPill(
                    session: item.session,
                    displayStatus: item.status,
                    isPrimary: item.id == primaryId
                ) {
                    monitor.openSession(item.session)
                }
                .contextMenu { sessionContextMenu(item.session) }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(SignalGlass.offline)
                .frame(width: 6, height: 6)
                .shadow(color: SignalGlass.offline.opacity(0.35), radius: 4)
            Text("No sessions")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(SignalGlass.mutedText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
        .modifier(SignalGlassShell())
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
    let isPrimary: Bool
    let onTap: () -> Void

    @State private var isBlinking = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            // 状态灯
            statusDot

            // 项目名
            Text(session.projectName)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(SignalGlass.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(pillBackground)
        .clipShape(Capsule())
        .contentShape(Capsule())
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
        .brightness(isHovered ? 0.06 : 0)
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        ZStack {
            // 外圈脉冲光环（需要确认时闪烁）
            Circle()
                .stroke(displayStatus.color.opacity(0.42), lineWidth: 1)
                .frame(width: 17, height: 17)
                .scaleEffect(isBlinking ? 1.9 : 0.72)
                .opacity(isBlinking ? 0.08 : 0.24)

            // 实心灯
            Circle()
                .fill(displayStatus.color)
                .frame(width: 7.5, height: 7.5)
                .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 0.6))
                .shadow(
                    color: displayStatus.color.opacity(isBlinking ? 0.85 : 0.36),
                    radius: isBlinking ? 7 : 3
                )
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
            .fill(isPrimary ? SignalGlass.accent.opacity(0.14) : Color.white.opacity(0.075))
            .overlay(
                Capsule()
                    .fill(displayStatus.color.opacity(isHovered ? 0.13 : 0.055))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isPrimary ? SignalGlass.accent.opacity(0.34) : Color.white.opacity(0.10),
                        lineWidth: 0.8
                    )
            )
    }
}

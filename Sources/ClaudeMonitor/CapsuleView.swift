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
    func displayStatus(now: Int64) -> DisplayStatus {
        if let hook = hookStatus {
            switch hook {
            case "tool_call":          return .busy
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
            .fill(Color.white.opacity(0.25))
            .frame(width: thumbWidth, height: 3)
            .offset(x: thumbX)
            .frame(width: trackWidth, height: 5, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.08)))
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

    private let scrollVisibleWidth: CGFloat = 180

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
        } else {
            cardStack(sorted)
                .fixedSize()
                .background(contentWidthReader)
        }
    }

    // MARK: - Scrollable Cards (content overflows)

    private func scrollableCards(_ sorted: [SortedSession]) -> some View {
        VStack(spacing: 5) {
            // 卡片区域
            ZStack(alignment: .leading) {
                cardStack(sorted)
                    .fixedSize()
                    .background(contentWidthReader)
                    .offset(x: scrollOffset)
            }
            .frame(width: scrollVisibleWidth, alignment: .leading)
            .clipped()
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .simultaneousGesture(contentDragGesture)

            // 迷你滚动条
            MiniScrollBar(
                trackWidth: min(50, scrollVisibleWidth - 20),
                contentWidth: measuredContentWidth,
                visibleWidth: scrollVisibleWidth,
                offset: $scrollOffset
            )
            .padding(.horizontal, 6)
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
        HStack(spacing: 4) {
            ForEach(sorted) { item in
                SessionPill(session: item.session, displayStatus: item.status) {
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
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text("No sessions")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fixedSize()
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

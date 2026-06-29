import AppKit
import SwiftUI

// MARK: - Floating Panel

final class FloatingPanel: NSPanel {
    private let monitor: SessionMonitor
    private var dragStart: NSPoint?
    private var isDragging = false
    private let snapDistance: CGFloat = 15
    private var hostingView: NSHostingView<CapsuleView>?

    private static let positionKey = "ClaudeMonitor.capsulePosition"

    init(monitor: SessionMonitor) {
        self.monitor = monitor

        // 初始尺寸较小，后续自动调整
        let initialSize = NSSize(width: 238, height: 48)
        let rect = NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        setupContent()
        restorePosition()
        NSApp.activate(ignoringOtherApps: true)

        // 监听会话变化后自动调整尺寸
        monitor.onSessionsChanged = { [weak self] in
            self?.resizeToFit()
        }
    }

    // MARK: - Content Setup

    private func setupContent() {
        guard let contentView else { return }

        // 毛玻璃背景
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 28
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.backgroundColor = NSColor(calibratedWhite: 0.04, alpha: 0.16).cgColor
        visualEffect.frame = contentView.bounds
        visualEffect.autoresizingMask = [.width, .height]

        // SwiftUI 内容
        let capsuleView = CapsuleView(monitor: monitor)
        let hosting = NSHostingView(rootView: capsuleView)
        hosting.frame = contentView.bounds
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting

        visualEffect.addSubview(hosting)
        contentView.addSubview(visualEffect)
    }

    // MARK: - Auto Resize

    private func resizeToFit() {
        guard let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fitSize = hostingView.fittingSize
        guard fitSize.width > 0, fitSize.height > 0 else { return }

        // 加上边框内边距
        let targetSize = NSSize(
            width: max(132, min(fitSize.width + 10, 286)),
            height: max(44, fitSize.height + 6)
        )

        var newFrame = frame
        // 以中心点为锚点调整宽度
        let center = NSPoint(x: frame.midX, y: frame.midY)
        newFrame.origin.x = center.x - targetSize.width / 2
        newFrame.origin.y = center.y - targetSize.height / 2
        newFrame.size = targetSize

        setFrame(newFrame, display: true)
    }

    // MARK: - Position

    private func restorePosition() {
        if let saved = loadPosition() {
            setFrameOrigin(clampToVisibleScreen(saved))
        } else if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - frame.width / 2
            let y = sf.maxY - frame.height - 6
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// 把保存的坐标约束到某个可见屏幕内，避免拔插显示器/改分辨率后胶囊跑到屏幕外不可见
    private func clampToVisibleScreen(_ point: NSPoint) -> NSPoint {
        let size = frame.size
        guard let sf = (screenContaining(point: point) ?? NSScreen.main)?.visibleFrame else {
            return point
        }
        var p = point
        p.x = max(sf.minX, min(p.x, sf.maxX - size.width))
        p.y = max(sf.minY, min(p.y, sf.maxY - size.height))
        return p
    }

    private func savePosition(_ point: NSPoint) {
        UserDefaults.standard.set([point.x, point.y], forKey: Self.positionKey)
    }

    private func loadPosition() -> NSPoint? {
        guard let arr = UserDefaults.standard.array(forKey: Self.positionKey) as? [CGFloat],
              arr.count == 2 else { return nil }
        return NSPoint(x: arr[0], y: arr[1])
    }

    // MARK: - Drag & Snap

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y

        if !isDragging && (abs(dx) > 2 || abs(dy) > 2) {
            isDragging = true
        }

        if isDragging {
            var frame = self.frame
            let screenPoint = NSEvent.mouseLocation
            frame.origin.x = screenPoint.x - start.x
            frame.origin.y = screenPoint.y - start.y

            // 使用鼠标当前所在的屏幕，而非固定用主屏幕
            if let screen = screenContaining(point: screenPoint) {
                let sf = screen.visibleFrame
                frame.origin.x = max(sf.minX, min(frame.origin.x, sf.maxX - frame.width))
                frame.origin.y = max(sf.minY, min(frame.origin.y, sf.maxY - frame.height))
            }
            setFrame(frame, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            snapToEdge()
            savePosition(frame.origin)
        }
        dragStart = nil
        isDragging = false
    }

    /// 找到包含指定全局坐标的屏幕（用于多屏幕拖拽）
    private func screenContaining(point: NSPoint) -> NSScreen? {
        // 优先精确匹配：坐标在屏幕 visibleFrame 内
        for screen in NSScreen.screens {
            if screen.visibleFrame.contains(point) {
                return screen
            }
        }
        // 兜底：选距离最近的屏幕
        var closest: NSScreen?
        var minDist = CGFloat.greatestFiniteMagnitude
        for screen in NSScreen.screens {
            let sf = screen.visibleFrame
            let cx = max(sf.minX, min(point.x, sf.maxX))
            let cy = max(sf.minY, min(point.y, sf.maxY))
            let dist = hypot(point.x - cx, point.y - cy)
            if dist < minDist {
                minDist = dist
                closest = screen
            }
        }
        return closest ?? NSScreen.main
    }

    private func snapToEdge() {
        guard let screen = screenContaining(point: NSPoint(x: frame.midX, y: frame.midY)) else { return }
        let sf = screen.visibleFrame
        let frame = self.frame
        var newFrame = frame
        var snapped = false

        if abs(frame.minX - sf.minX) < snapDistance {
            newFrame.origin.x = sf.minX; snapped = true
        }
        if abs(frame.maxX - sf.maxX) < snapDistance {
            newFrame.origin.x = sf.maxX - frame.width; snapped = true
        }
        if abs(frame.maxY - sf.maxY) < snapDistance {
            newFrame.origin.y = sf.maxY - frame.height; snapped = true
        }
        if abs(frame.minY - sf.minY) < snapDistance {
            newFrame.origin.y = sf.minY; snapped = true
        }

        if snapped && newFrame != frame {
            setFrame(newFrame, display: true, animate: true)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Scroll Event Forwarding

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            let delta = event.scrollingDeltaX != 0
                ? event.scrollingDeltaX
                : -event.scrollingDeltaY
            if delta != 0 {
                NotificationCenter.default.post(
                    name: .capsuleScroll,
                    object: nil,
                    userInfo: ["delta": delta]
                )
            }
        }
        super.sendEvent(event)
    }
}

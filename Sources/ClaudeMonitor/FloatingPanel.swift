import AppKit
import SwiftUI

// MARK: - Floating Panel

final class FloatingPanel: NSPanel {
    private let monitor: SessionMonitor
    private var dragStart: NSPoint?
    private var isDragging = false
    private let snapDistance: CGFloat = 20

    private static let positionKey = "ClaudeMonitor.capsulePosition"

    init(monitor: SessionMonitor) {
        self.monitor = monitor

        let initialSize = NSSize(width: 460, height: 56)
        let rect = NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 窗口配置
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        // 居中或恢复上次位置
        restorePosition()

        // 构建内容视图
        setupContent()

        // 确保显示
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Content Setup

    private func setupContent() {
        guard let contentView else { return }

        // 毛玻璃背景
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 25
        visualEffect.layer?.masksToBounds = true
        visualEffect.frame = contentView.bounds
        visualEffect.autoresizingMask = [.width, .height]

        // SwiftUI 内容
        let capsuleView = CapsuleView(monitor: monitor)
        let hostingView = NSHostingView(rootView: capsuleView)
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]

        visualEffect.addSubview(hostingView)
        contentView.addSubview(visualEffect)
    }

    // MARK: - Position Persistence

    private func restorePosition() {
        if let saved = loadPosition() {
            setFrameOrigin(saved)
        } else if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - frame.width / 2
            let y = sf.maxY - frame.height - 8
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
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

            // 限制在屏幕内
            if let screen = NSScreen.main {
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

    // MARK: - Edge Snapping

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let frame = self.frame

        var newFrame = frame
        var snapped = false

        if abs(frame.minX - sf.minX) < snapDistance {
            newFrame.origin.x = sf.minX
            snapped = true
        }
        if abs(frame.maxX - sf.maxX) < snapDistance {
            newFrame.origin.x = sf.maxX - frame.width
            snapped = true
        }
        if abs(frame.maxY - sf.maxY) < snapDistance {
            newFrame.origin.y = sf.maxY - frame.height
            snapped = true
        }
        if abs(frame.minY - sf.minY) < snapDistance {
            newFrame.origin.y = sf.minY
            snapped = true
        }

        if snapped && newFrame != frame {
            setFrame(newFrame, display: true, animate: true)
        }
    }

    // MARK: - Window Behavior

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

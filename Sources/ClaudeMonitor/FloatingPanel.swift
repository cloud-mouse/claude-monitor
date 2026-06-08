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

        // 初始大小
        let initialSize = NSSize(width: 420, height: 52)
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
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false

        // 居中或恢复上次位置
        restorePosition()

        // 创建 SwiftUI 宿主视图
        let capsuleView = CapsuleView(monitor: monitor)
        let hostingView = NSHostingView(rootView: capsuleView)
        hostingView.frame = contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView?.addSubview(hostingView)

        // 跟踪区域以接收鼠标事件
        setupTrackingArea()
    }

    // MARK: - Position Persistence

    private func restorePosition() {
        if let saved = loadPosition() {
            setFrameOrigin(saved)
        } else {
            center()
            // 默认放在屏幕顶部居中
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let panelWidth = frame.width
                let x = screenFrame.midX - panelWidth / 2
                let y = screenFrame.maxY - frame.height - 10
                setFrameOrigin(NSPoint(x: x, y: y))
            }
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

    // MARK: - Mouse Tracking

    private func setupTrackingArea() {
        // 鼠标事件由 NSPanel 直接处理，无需额外 tracking area
    }

    // MARK: - Drag & Snap

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        isDragging = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }

        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y

        // 最小拖动阈值，避免误触
        if !isDragging && (abs(dx) > 2 || abs(dy) > 2) {
            isDragging = true
        }

        if isDragging {
            var frame = self.frame
            let screenPoint = NSEvent.mouseLocation

            // 计算新位置（以鼠标点击点为锚点）
            frame.origin.x = screenPoint.x - start.x
            frame.origin.y = screenPoint.y - start.y

            // 确保窗口不超出屏幕边界
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
        super.mouseUp(with: event)
    }

    // MARK: - Edge Snapping

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let frame = self.frame

        var newFrame = frame
        var snapped = false

        // 吸附到左边缘
        if abs(frame.minX - sf.minX) < snapDistance {
            newFrame.origin.x = sf.minX
            snapped = true
        }
        // 吸附到右边缘
        if abs(frame.maxX - sf.maxX) < snapDistance {
            newFrame.origin.x = sf.maxX - frame.width
            snapped = true
        }
        // 吸附到顶部边缘
        if abs(frame.maxY - sf.maxY) < snapDistance {
            newFrame.origin.y = sf.maxY - frame.height
            snapped = true
        }
        // 吸附到底部边缘
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

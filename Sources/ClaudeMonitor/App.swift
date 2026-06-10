import AppKit
import SwiftUI
import UserNotifications

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let monitor = SessionMonitor()
    let notificationManager: NotificationManager
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    override init() {
        self.notificationManager = NotificationManager(monitor: monitor)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[AppDelegate] 通知授权失败: \(error.localizedDescription)")
            } else {
                print("[AppDelegate] 通知授权结果: \(granted ? "已授权" : "被拒绝")")
                // 授权后立即发一条测试通知
                if granted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.notificationManager.sendTestNotification()
                    }
                }
            }
        }

        // 接入通知管理器
        monitor.notificationManager = notificationManager

        setupStatusBarItem()
        monitor.start()

        panel = FloatingPanel(monitor: monitor)
        panel?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panel?.orderFrontRegardless()
        return true
    }

    // MARK: - Status Bar Item

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "circle.hexagonpath",
                                accessibilityDescription: "Claude Monitor")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示/隐藏面板", action: #selector(togglePanel), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "设置...", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关于 Claude Monitor", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            panel?.orderFrontRegardless()
        }
    }

    // MARK: - Settings Window

    @objc private func showSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(notificationManager: notificationManager)
        let hosting = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Monitor 设置"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 480)

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - About

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "Claude Monitor",
                .applicationVersion: "1.0.0",
                .version: "1",
            ]
        )
    }
}

// MARK: - Entry Point

@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

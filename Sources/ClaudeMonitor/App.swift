import AppKit
import SwiftUI
import UserNotifications

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let monitor = SessionMonitor()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 请求通知权限
        requestNotificationPermission()

        // 创建菜单栏图标
        setupStatusBarItem()

        // 启动会话监控
        monitor.start()

        // 创建悬浮面板
        panel = FloatingPanel(monitor: monitor)
        panel?.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panel?.orderFrontRegardless()
        return true
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                print("通知权限请求失败: \(error)")
            }
        }
    }

    // MARK: - Status Bar Item

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.hexagonpath", accessibilityDescription: "Claude Monitor")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()

        menu.addItem(withTitle: "显示/隐藏面板", action: #selector(togglePanel), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关于 Claude Monitor", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            panel?.orderFrontRegardless()
        }
    }

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

import AppKit
import SwiftUI

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let monitor = SessionMonitor()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

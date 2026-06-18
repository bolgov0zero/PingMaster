import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    let monitoringService = MonitoringService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        monitoringService.startAll()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        if let button = statusItem?.button {
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusIcon),
                                               name: .hostStatusChanged, object: nil)
    }

    @objc func updateStatusIcon() {
        let allAvailable = monitoringService.hosts.allSatisfy { $0.isAvailable }
        let color: NSColor = monitoringService.hosts.isEmpty || allAvailable ? .systemGreen : .systemRed

        let size = CGSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        statusItem?.button?.image = image
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showRightMenu()
        } else {
            showLeftMenu()
        }
    }

    private func showLeftMenu() {
        let menu = NSMenu()
        let hosts = monitoringService.hosts

        if hosts.isEmpty {
            let item = NSMenuItem(title: "Нет хостов", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for host in hosts {
                let dot = host.isAvailable ? "🟢" : "🔴"
                let latency = host.lastLatency.map { String(format: " — %.0f ms", $0) } ?? " — –"
                let title = "\(dot)  \(host.name)\(latency)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func showRightMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "PingMaster"
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

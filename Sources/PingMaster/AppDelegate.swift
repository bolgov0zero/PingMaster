import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var mainWindow: NSWindow?
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
        let hosts = monitoringService.hosts
        let color: NSColor
        if hosts.isEmpty {
            color = .white
        } else if hosts.allSatisfy({ $0.isAvailable }) {
            color = .systemGreen
        } else {
            color = .systemRed
        }

        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
        image.unlockFocus()
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

    private func dotImage(available: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let img = NSImage(size: size)
        img.lockFocus()
        (available ? NSColor.systemGreen : NSColor.systemRed).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func showLeftMenu() {
        let menu = NSMenu()
        let hosts = monitoringService.hosts.filter { $0.showInMenu }

        if hosts.isEmpty {
            let item = NSMenuItem(title: "Нет хостов", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for host in hosts {
                let history = monitoringService.latencyHistory[host.id] ?? []
                let item = NSMenuItem()
                let address = host.address
                let view = SparklineMenuItemView(host: host, history: history) { [weak self] in
                    self?.openTerminalForAddress(address)
                }
                item.view = view
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Ping все", action: #selector(forcePing), keyEquivalent: ""))
        }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func showRightMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(openMain), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func forcePing() {
        monitoringService.pingAll()
    }

    func openTerminalForAddress(_ address: String) {
        let script = "tell application \"Terminal\" to do script \"ping \(address)\"\ntell application \"Terminal\" to activate"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    @objc func openMain() {
        if mainWindow == nil {
            mainWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            mainWindow?.title = "PingMaster"
            mainWindow?.contentView = NSHostingView(rootView: MainTabView())
            mainWindow?.center()
            mainWindow?.isReleasedWhenClosed = false
            mainWindow?.delegate = self
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        MonitoringService.shared.stopDashboardPolling()
    }
}

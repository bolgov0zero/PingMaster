import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var mainWindow: NSWindow?
    let monitoringService = MonitoringService.shared

    private var hostPanel: NSPanel?
    private var detailPanel: NSPanel?
    private var panelMonitor: Any?
    private var panelClosedAt: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationManager.shared.requestAuthorization()
        setupStatusItem()
        monitoringService.startAll()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        let downCount = hosts.filter { !$0.isAvailable }.count
        let color: NSColor
        if hosts.isEmpty {
            color = .white
        } else if downCount == 0 {
            color = .systemGreen
        } else {
            color = .systemRed
        }

        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageOnly
        button.title = ""

        // Optional two-line count (up / down), composited with the dot in a
        // single image so the text is vertically centered on the dot.
        if GlobalSettings.shared.showCountInIcon && !hosts.isEmpty {
            button.image = countIcon(dotColor: color, up: hosts.count - downCount, down: downCount)
        } else {
            let image = NSImage(size: NSSize(width: 16, height: 16))
            image.lockFocus()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
            image.unlockFocus()
            image.isTemplate = false
            button.image = image
        }
    }

    private func countIcon(dotColor: NSColor, up: Int, down: Int) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let l1 = NSAttributedString(string: "\(up) up", attributes: attrs)
        let l2 = NSAttributedString(string: "\(down) down", attributes: attrs)

        let textW = ceil(max(l1.size().width, l2.size().width))
        let lineH: CGFloat = 10
        let dotD: CGFloat = 11
        let gap: CGFloat = 4
        let h: CGFloat = 21
        let w = dotD + gap + textW

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: (h - dotD) / 2, width: dotD, height: dotD)).fill()

        let tx = dotD + gap
        let blockBottom = (h - lineH * 2) / 2
        l1.draw(at: NSPoint(x: tx, y: blockBottom + lineH))
        l2.draw(at: NSPoint(x: tx, y: blockBottom))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showRightMenu()
        } else {
            togglePanel()
        }
    }

    // MARK: - Custom host panel

    private func togglePanel() {
        if let panel = hostPanel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Ignore the re-open that would follow closing via the outside-click
        // monitor when the status button itself was clicked.
        if Date().timeIntervalSince(panelClosedAt) < 0.25 { return }

        let root = MenuPanelView()

        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.hidesOnDeactivate = false

        // Position below the status item button.
        var panelOrigin = NSPoint(x: 8, y: 100)
        if let buttonWindow = statusItem?.button?.window {
            let bf = buttonWindow.frame
            let x = bf.midX - size.width / 2
            let y = bf.minY - size.height - 6
            let screenMaxX = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame.maxX ?? x + size.width
            let clampedX = min(max(x, 8), screenMaxX - size.width - 8)
            panelOrigin = NSPoint(x: clampedX, y: y)
            panel.setFrameOrigin(panelOrigin)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hostPanel = panel

        // Detail card floats to the left of the list, top-aligned.
        PanelHoverState.shared.hostID = nil
        let detailHosting = NSHostingView(rootView: DetailCardView())
        detailHosting.layoutSubtreeIfNeeded()
        let dSize = detailHosting.fittingSize
        detailHosting.frame = NSRect(origin: .zero, size: dSize)
        let dPanel = NSPanel(contentRect: detailHosting.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        dPanel.isFloatingPanel = true
        dPanel.level = .popUpMenu
        dPanel.backgroundColor = .clear
        dPanel.isOpaque = false
        dPanel.hasShadow = true
        dPanel.contentView = detailHosting
        dPanel.hidesOnDeactivate = false
        let dx = max(8, panelOrigin.x - dSize.width - 8)
        let dy = panelOrigin.y + size.height - dSize.height
        dPanel.setFrameOrigin(NSPoint(x: dx, y: dy))
        dPanel.order(.above, relativeTo: panel.windowNumber)
        detailPanel = dPanel

        // Close when clicking outside.
        panelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        if let m = panelMonitor { NSEvent.removeMonitor(m); panelMonitor = nil }
        detailPanel?.orderOut(nil)
        detailPanel = nil
        hostPanel?.orderOut(nil)
        hostPanel = nil
        panelClosedAt = Date()
    }

    private func openTerminalCommand(_ command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command)\"\ntell application \"Terminal\" to activate"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func showRightMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Настройки", action: #selector(openMain), keyEquivalent: "")
        // Use a custom selector (not terminate:) so macOS doesn't auto-add icon.
        let quit = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
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
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 780),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            mainWindow?.title = "PingMaster"
            mainWindow?.contentView = NSHostingView(rootView: MainTabView())
            mainWindow?.contentMinSize = NSSize(width: 700, height: 760)
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
        // Stop the dashboard's continuous ping when the window is closed.
        LivePinger.shared.stop()
    }
}


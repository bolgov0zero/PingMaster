import Cocoa

class SparklineMenuItemView: NSView {
    private let host: Host
    private var history: [LatencyPoint]
    private let onSelect: () -> Void
    private var refreshTimer: Timer?

    private var isHighlighted = false
    private let barCount = 10
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 1
    private let barMaxHeight: CGFloat = 14
    private let sidePadding: CGFloat = 10
    private let nameWidth: CGFloat = 100
    private let latencyWidth: CGFloat = 46
    private let uptimeWidth: CGFloat = 38

    init(host: Host, history: [LatencyPoint], onSelect: @escaping () -> Void) {
        self.host = host
        self.history = history
        self.onSelect = onSelect
        let sparkWidth = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
        let totalWidth = sidePadding + 12 + 6 + nameWidth + 6 + sparkWidth + 6 + latencyWidth + 6 + uptimeWidth + sidePadding
        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: 22))
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // Start/stop refresh timer when view enters/leaves the menu window.
    // Timer uses .common mode so it fires during NSMenu's eventTracking run loop.
    override func viewDidMoveToWindow() {
        if window != nil {
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.history = MonitoringService.shared.latencyHistory[self.host.id] ?? []
                self.needsDisplay = true
            }
            RunLoop.main.add(t, forMode: .common)
            refreshTimer = t
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.clear.setFill()
        }
        NSBezierPath(rect: bounds).fill()

        let textColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor

        var x = sidePadding

        // Status dot — green / yellow / red per thresholds
        let dotColor = MonitoringService.shared.status(for: host).nsColor
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 6, width: 10, height: 10)).fill()
        x += 12 + 6

        // Host name (truncated)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: textColor
        ]
        let nameStr = truncate(host.name, width: nameWidth, attrs: nameAttrs)
        nameStr.draw(at: NSPoint(x: x, y: 4))
        x += nameWidth + 6

        // Sparkline bars
        let recent = Array(history.suffix(barCount))
        let maxVal = recent.compactMap { $0.value }.max() ?? 1
        let sparkWidth = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing

        for i in 0..<barCount {
            let barX = x + CGFloat(i) * (barWidth + barSpacing)
            if i < recent.count {
                let val = recent[i].value
                let h = max(2, CGFloat(val / maxVal) * barMaxHeight)
                let barColor = latencyColor(val)
                barColor.withAlphaComponent(isHighlighted ? 0.9 : 0.85).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: (22 - h) / 2, width: barWidth, height: h),
                             xRadius: 1, yRadius: 1).fill()
            } else {
                // Empty slot
                secondaryColor.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: 9, width: barWidth, height: 2),
                             xRadius: 1, yRadius: 1).fill()
            }
        }
        x += sparkWidth + 6

        // Latency value
        let latencyText: String
        if let ms = host.lastLatency {
            latencyText = String(format: "%.0f ms", ms)
        } else {
            latencyText = "–"
        }
        let latencyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: secondaryColor
        ]
        let latencyStr = NSAttributedString(string: latencyText, attributes: latencyAttrs)
        let latencySize = latencyStr.size()
        latencyStr.draw(at: NSPoint(x: x + latencyWidth - latencySize.width, y: 4))
        x += latencyWidth + 6

        // Uptime % (last 24h / since launch)
        let uptimeText: String
        if let pct = MonitoringService.shared.uptimePercent(for: host) {
            uptimeText = String(format: "%.0f%%", pct)
        } else {
            uptimeText = "–"
        }
        let uptimeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: secondaryColor
        ]
        let uptimeStr = NSAttributedString(string: uptimeText, attributes: uptimeAttrs)
        let uptimeSize = uptimeStr.size()
        uptimeStr.draw(at: NSPoint(x: x + uptimeWidth - uptimeSize.width, y: 5))
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { self.onSelect() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Helpers

    private func latencyColor(_ ms: Double) -> NSColor {
        let s = GlobalSettings.shared
        if ms < s.greenThreshold  { return .systemGreen }
        if ms < s.orangeThreshold { return .systemOrange }
        return .systemRed
    }

    private func truncate(_ string: String, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var s = string
        while !s.isEmpty {
            let str = NSAttributedString(string: s, attributes: attrs)
            if str.size().width <= width { return str }
            s = String(s.dropLast())
        }
        return NSAttributedString(string: string, attributes: attrs)
    }
}

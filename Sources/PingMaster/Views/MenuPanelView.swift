import SwiftUI
import AppKit

// Shared hover selection between the host list panel and the floating detail card.
final class PanelHoverState: ObservableObject {
    static let shared = PanelHoverState()
    @Published var hostID: UUID?
    private init() {}
}

struct MenuPanelView: View {
    @ObservedObject var service = MonitoringService.shared
    @ObservedObject var settings = GlobalSettings.shared
    @ObservedObject var hover = PanelHoverState.shared

    private var hosts: [Host] { service.hosts.filter { $0.showInMenu } }

    var body: some View {
        Group {
            if hosts.isEmpty {
                emptyState
            } else {
                VStack(spacing: 1) {
                    ForEach(hosts) { host in
                        hostRow(host)
                    }
                }
                .padding(5)
            }
        }
        .fixedSize()
        .background(MenuVisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hostRow(_ host: Host) -> some View {
        let active = host.id == hover.hostID
        return HStack(spacing: 8) {
            Circle().fill(service.status(for: host).color)
                .frame(width: 8, height: 8)
            Text(host.name)
                .font(.system(size: 12.5))
                .foregroundColor(active ? .white : .primary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 14)
            RowSparkline(points: service.latencyHistory[host.id] ?? [],
                         green: settings.greenThreshold, orange: settings.orangeThreshold)
                .frame(width: 46, height: 14)
            Text(host.lastLatency.map { String(format: "%.0f мс", $0) } ?? "–")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundColor(active ? .white.opacity(0.9) : .secondary)
                .frame(width: 46, alignment: .trailing)
            Text(service.uptimePercent(for: host).map { String(format: "%.0f%%", $0) } ?? "–")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundColor(active ? .white.opacity(0.8) : .secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onHover { if $0 { hover.hostID = host.id } }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack").font(.title).foregroundColor(.secondary)
            Text("Нет хостов").font(.subheadline.weight(.medium))
            Text("Включите «Показывать в меню» у хостов")
                .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 240)
        .padding(20)
    }
}

// Floating card (no arrow): large interactive sparkline with hover tooltips.
struct DetailCardView: View {
    @ObservedObject var hover = PanelHoverState.shared
    @ObservedObject var service = MonitoringService.shared
    @ObservedObject var settings = GlobalSettings.shared

    var body: some View {
        Group {
            if let id = hover.hostID, let host = service.hosts.first(where: { $0.id == id }) {
                let history = service.latencyHistory[host.id] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle().fill(service.status(for: host).color).frame(width: 9, height: 9)
                        Text(host.name).font(.subheadline).bold().lineLimit(1)
                        Spacer()
                        if let ms = host.lastLatency {
                            Text(String(format: "%.0f мс", ms))
                                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        }
                    }
                    if history.isEmpty {
                        Text("Ожидание данных…")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LineChartView(slots: history.suffix(80).map { Optional($0) },
                                      greenThreshold: settings.greenThreshold,
                                      orangeThreshold: settings.orangeThreshold)
                    }
                }
                .padding(14)
                .frame(width: 360, height: 184)
                .background(MenuVisualEffect())
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                // Invisible until a host is hovered.
                Color.clear.frame(width: 360, height: 184)
            }
        }
    }
}

// Native menu-style vibrant background.
struct MenuVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Lightweight non-interactive sparkline for list rows.
struct RowSparkline: View {
    let points: [LatencyPoint]
    let green: Double
    let orange: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cy = h / 2
            let barW: CGFloat = 2.5, gap: CGFloat = 1.5
            let maxBars = max(1, Int((w + gap) / (barW + gap)))
            let bars = Array(points.suffix(maxBars))
            let maxVal = bars.map(\.value).max() ?? 1
            Canvas { ctx, _ in
                for (i, p) in bars.enumerated() {
                    let half = max(1, CGFloat(p.value / maxVal) * (h * 0.46))
                    let x = CGFloat(i) * (barW + gap)
                    let rect = CGRect(x: x, y: cy - half, width: barW, height: half * 2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW/2),
                             with: .color(color(p.value).opacity(0.85)))
                }
            }
        }
    }

    private func color(_ ms: Double) -> Color {
        if ms < green { return .green }
        if ms < orange { return .orange }
        return .red
    }
}

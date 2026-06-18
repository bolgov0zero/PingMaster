import SwiftUI

struct SparklineChartView: View {
    let points: [LatencyPoint]
    let greenThreshold: Double
    let orangeThreshold: Double
    var dateStyle: Date.FormatStyle = .dateTime.hour().minute().second()
    // Fixed-axis slots (hours/days/months). When set, bars sit at their logical
    // position and empty slots are gaps. When nil, `points` scroll (live mode).
    var slots: [LatencyPoint?]? = nil

    private let barGap: CGFloat = 3
    private let barWidth: CGFloat = 5
    private let maxBarWidth: CGFloat = 16

    @State private var hoverIndex: Int? = nil
    @State private var hoverX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2  // center line Y

            let layout = computeLayout(width: w)
            let cells = layout.cells          // [LatencyPoint?]
            let slot = layout.slot
            let barW = layout.barW
            let centered = layout.centered
            let values = cells.compactMap { $0?.value }
            let maxVal = max((values.max() ?? orangeThreshold) * 1.1, orangeThreshold)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    // Center line
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: 0, y: cy))
                    linePath.addLine(to: CGPoint(x: w, y: cy))
                    ctx.stroke(linePath,
                               with: .color(.primary.opacity(0.15)),
                               style: StrokeStyle(lineWidth: 1))

                    // Bars — symmetric around center, at their slot position
                    for (i, cell) in cells.enumerated() {
                        guard let point = cell else { continue }
                        let halfH = max(2, CGFloat(point.value / maxVal) * (h * 0.46))
                        let x = CGFloat(i) * slot + (centered ? (slot - barW) / 2 : 0)
                        let rect = CGRect(x: x, y: cy - halfH, width: barW, height: halfH * 2)
                        let path = Path(roundedRect: rect, cornerRadius: barW / 2)
                        let highlighted = (i == hoverIndex)
                        ctx.fill(path, with: .color(barColor(point.value).opacity(highlighted ? 1.0 : 0.85)))
                    }
                }

                // Tooltip
                if let idx = hoverIndex, idx < cells.count, let point = cells[idx] {
                    tooltip(for: point)
                        .fixedSize()
                        .background(
                            GeometryReader { tipGeo in
                                Color.clear.preference(key: TooltipWidthKey.self, value: tipGeo.size.width)
                            }
                        )
                        .modifier(TooltipPosition(anchorX: hoverX, maxX: w))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let i = Int(location.x / slot)
                    if i >= 0 && i < cells.count && cells[i] != nil {
                        hoverIndex = i
                        hoverX = CGFloat(i) * slot + slot / 2
                    } else {
                        hoverIndex = nil
                    }
                case .ended:
                    hoverIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func tooltip(for point: LatencyPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.timestamp, format: dateStyle)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f мс", point.value))
                .foregroundColor(barColor(point.value))
                .bold()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
    }

    private func computeLayout(width w: CGFloat) -> (cells: [LatencyPoint?], slot: CGFloat, barW: CGFloat, centered: Bool) {
        if let slots {
            // Fixed axis: each slot takes 1/n of the width; bars centered in slot.
            let n = max(1, slots.count)
            let slot = w / CGFloat(n)
            let barW = max(2, min(maxBarWidth, slot - barGap))
            return (slots, slot, barW, true)
        } else {
            // Live scroll: fixed-width bars anchored left, oldest scroll off.
            let maxBars = max(1, Int((w + barGap) / (barWidth + barGap)))
            let visible = Array(points.suffix(maxBars)).map { Optional($0) }
            return (visible, barWidth + barGap, barWidth, false)
        }
    }

    private func barColor(_ ms: Double) -> Color {
        if ms < greenThreshold  { return .green }
        if ms < orangeThreshold { return .orange }
        return .red
    }
}

private struct TooltipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Positions the tooltip above the hovered bar, clamped to the chart bounds.
private struct TooltipPosition: ViewModifier {
    let anchorX: CGFloat
    let maxX: CGFloat
    @State private var tipWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(TooltipWidthKey.self) { tipWidth = $0 }
            .offset(x: min(max(anchorX - tipWidth / 2, 0), max(0, maxX - tipWidth)), y: 0)
    }
}

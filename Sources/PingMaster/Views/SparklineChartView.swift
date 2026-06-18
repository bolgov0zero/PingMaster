import SwiftUI

struct SparklineChartView: View {
    let points: [LatencyPoint]
    let greenThreshold: Double
    let orangeThreshold: Double

    private let barGap: CGFloat = 3
    private let barWidth: CGFloat = 5

    @State private var hoverIndex: Int? = nil
    @State private var hoverX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2  // center line Y

            // Fixed bar width: bars grow left→right and fill the width; once
            // there are more points than fit, the oldest scroll off the left.
            let maxBars = max(1, Int((w + barGap) / (barWidth + barGap)))
            let visible = Array(points.suffix(maxBars))
            let maxVal = max((visible.map(\.value).max() ?? orangeThreshold) * 1.1, orangeThreshold)
            let pitch = barWidth + barGap

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    // Center line
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: 0, y: cy))
                    linePath.addLine(to: CGPoint(x: w, y: cy))
                    ctx.stroke(linePath,
                               with: .color(.primary.opacity(0.15)),
                               style: StrokeStyle(lineWidth: 1))

                    // Bars — symmetric around center, anchored to the left edge
                    for (i, point) in visible.enumerated() {
                        let halfH = max(2, CGFloat(point.value / maxVal) * (h * 0.46))
                        let x = CGFloat(i) * pitch
                        let rect = CGRect(x: x, y: cy - halfH, width: barWidth, height: halfH * 2)
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        let highlighted = (i == hoverIndex)
                        ctx.fill(path, with: .color(barColor(point.value).opacity(highlighted ? 1.0 : 0.85)))
                    }
                }

                // Tooltip
                if let idx = hoverIndex, idx < visible.count {
                    let point = visible[idx]
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
                    let i = Int((location.x) / pitch)
                    if i >= 0 && i < visible.count {
                        hoverIndex = i
                        hoverX = CGFloat(i) * pitch + barWidth / 2
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
            Text(point.timestamp, format: .dateTime.hour().minute().second())
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

import SwiftUI

struct SparklineChartView: View {
    let points: [LatencyPoint]
    let greenThreshold: Double
    let orangeThreshold: Double

    private let barGap: CGFloat = 2
    private let cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let chartH = h - 20  // bottom 20pt for time labels
            let maxVal = max((points.map(\.value).max() ?? orangeThreshold) * 1.2, orangeThreshold * 1.1)
            let n = points.count
            let barW = n > 0 ? max(4, (w - CGFloat(n - 1) * barGap) / CGFloat(n)) : 8

            ZStack(alignment: .topLeading) {
                // Bars
                Canvas { ctx, _ in
                    for (i, point) in points.enumerated() {
                        let barH = CGFloat(point.value / maxVal) * chartH
                        let x = CGFloat(i) * (barW + barGap)
                        let y = chartH - barH
                        let rect = CGRect(x: x, y: y, width: barW, height: barH)
                        let path = Path(roundedRect: rect,
                                        cornerRadii: RectangleCornerRadii(
                                            topLeading: cornerRadius, bottomLeading: 0,
                                            bottomTrailing: 0, topTrailing: cornerRadius))
                        ctx.fill(path, with: .color(barColor(point.value).opacity(0.85)))
                    }
                }
                .frame(width: w, height: chartH)

                // Time labels
                if let first = points.first, let last = points.last {
                    HStack {
                        Text(first.timestamp, format: .dateTime.hour().minute().second())
                        Spacer()
                        Text(last.timestamp, format: .dateTime.hour().minute().second())
                    }
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: w)
                    .offset(y: chartH + 4)
                }

                // Y labels on right
                VStack {
                    Text("\(Int(maxVal)) мс").offset(x: w - 42, y: -2)
                    Spacer()
                    Text("0 мс").offset(x: w - 42, y: 0)
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(height: chartH)
            }
        }
    }

    private func barColor(_ ms: Double) -> Color {
        if ms < greenThreshold  { return .green }
        if ms < orangeThreshold { return .orange }
        return .red
    }
}

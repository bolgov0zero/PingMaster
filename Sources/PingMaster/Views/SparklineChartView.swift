import SwiftUI

struct SparklineChartView: View {
    let points: [LatencyPoint]
    let greenThreshold: Double
    let orangeThreshold: Double

    private let barGap: CGFloat = 3
    private let barWidth: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2  // center line Y

            let maxVal = max((points.map(\.value).max() ?? orangeThreshold) * 1.1, orangeThreshold)
            let n = points.count
            // Align bars to right edge, newest on right
            let startX: CGFloat = 0

            Canvas { ctx, size in
                // Center line
                var linePath = Path()
                linePath.move(to: CGPoint(x: 0, y: cy))
                linePath.addLine(to: CGPoint(x: w, y: cy))
                ctx.stroke(linePath,
                           with: .color(.primary.opacity(0.15)),
                           style: StrokeStyle(lineWidth: 1))

                // Bars — symmetric around center
                for (i, point) in points.enumerated() {
                    let halfH = max(2, CGFloat(point.value / maxVal) * (h * 0.46))
                    let x = startX + CGFloat(i) * (barWidth + barGap)
                    let rect = CGRect(x: x, y: cy - halfH, width: barWidth, height: halfH * 2)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    ctx.fill(path, with: .color(barColor(point.value).opacity(0.85)))
                }
            }
        }
    }

    private func barColor(_ ms: Double) -> Color {
        if ms < greenThreshold  { return .green }
        if ms < orangeThreshold { return .orange }
        return .red
    }
}

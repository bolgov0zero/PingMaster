import SwiftUI

// Smooth line + gradient-area latency chart with Y/X axes, an end-point value
// bubble and a hover tooltip. Slot-positioned (gaps allowed).
struct LineChartView: View {
    let slots: [LatencyPoint?]
    let greenThreshold: Double
    let orangeThreshold: Double
    var dateStyle: Date.FormatStyle = .dateTime.hour().minute().second()

    private let leftPad: CGFloat = 30
    private let rightPad: CGFloat = 12
    private let topPad: CGFloat = 10
    private let bottomPad: CGFloat = 20

    @State private var hoverIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let plot = CGRect(x: leftPad, y: topPad,
                              width: max(1, w - leftPad - rightPad),
                              height: max(1, h - topPad - bottomPad))
            let values = slots.compactMap { $0?.value }
            let niceMax = niceCeil(max((values.max() ?? orangeThreshold) * 1.15, 10))
            let n = slots.count
            let stepX = n > 1 ? plot.width / CGFloat(n - 1) : 0

            let pt: (Int, Double) -> CGPoint = { i, v in
                CGPoint(x: plot.minX + CGFloat(i) * stepX,
                        y: plot.maxY - CGFloat(v / niceMax) * plot.height)
            }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // Y grid + labels
                    let ticks = 3
                    for t in 0...ticks {
                        let val = niceMax * Double(t) / Double(ticks)
                        let y = plot.maxY - CGFloat(t) / CGFloat(ticks) * plot.height
                        var grid = Path()
                        grid.move(to: CGPoint(x: plot.minX, y: y))
                        grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                        ctx.stroke(grid, with: .color(.primary.opacity(0.08)), lineWidth: 1)
                        let label = Text("\(Int(val))").font(.system(size: 9)).foregroundColor(.secondary)
                        ctx.draw(label, at: CGPoint(x: plot.minX - 6, y: y), anchor: .trailing)
                    }

                    // Build segments (break on gaps)
                    var segments: [[CGPoint]] = []
                    var current: [CGPoint] = []
                    for (i, cell) in slots.enumerated() {
                        if let v = cell?.value {
                            current.append(pt(i, v))
                        } else if !current.isEmpty {
                            segments.append(current); current = []
                        }
                    }
                    if !current.isEmpty { segments.append(current) }

                    for seg in segments {
                        guard seg.count > 0 else { continue }
                        let linePath = smoothPath(seg)

                        // Area fill
                        var area = linePath
                        area.addLine(to: CGPoint(x: seg.last!.x, y: plot.maxY))
                        area.addLine(to: CGPoint(x: seg.first!.x, y: plot.maxY))
                        area.closeSubpath()
                        ctx.fill(area, with: .linearGradient(
                            Gradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: plot.minY),
                            endPoint: CGPoint(x: 0, y: plot.maxY)))

                        // Line
                        if seg.count > 1 {
                            ctx.stroke(linePath, with: .color(.accentColor),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        } else {
                            ctx.fill(Path(ellipseIn: CGRect(x: seg[0].x - 2, y: seg[0].y - 2, width: 4, height: 4)),
                                     with: .color(.accentColor))
                        }
                    }

                    // End point dot
                    if let lastIdx = slots.lastIndex(where: { $0 != nil }), let v = slots[lastIdx]?.value {
                        let p = pt(lastIdx, v)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                                 with: .color(.accentColor))
                        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                                   with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1.5)
                    }
                }

                // End value bubble
                if let lastIdx = slots.lastIndex(where: { $0 != nil }), let v = slots[lastIdx]?.value {
                    let p = pt(lastIdx, v)
                    Text(String(format: "%.1f ms", v))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .fixedSize()
                        .position(x: min(p.x, plot.maxX - 28), y: max(p.y - 14, topPad + 6))
                }

                // Hover tooltip
                if let idx = hoverIndex, idx < slots.count, let point = slots[idx] {
                    let p = pt(idx, point.value)
                    VStack(spacing: 1) {
                        Text(point.timestamp, format: dateStyle).font(.system(size: 9)).foregroundColor(.secondary)
                        Text(String(format: "%.1f мс", point.value)).font(.caption.monospacedDigit().bold())
                            .foregroundColor(barColor(point.value))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                    .fixedSize()
                    .position(x: min(max(p.x, 34), plot.maxX - 34), y: max(p.y - 26, topPad + 12))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    guard stepX > 0 else { hoverIndex = nil; return }
                    let i = Int(((loc.x - plot.minX) / stepX).rounded())
                    hoverIndex = (i >= 0 && i < slots.count && slots[i] != nil) ? i : nil
                case .ended:
                    hoverIndex = nil
                }
            }
        }
    }

    private func barColor(_ ms: Double) -> Color {
        if ms < greenThreshold { return .green }
        if ms < orangeThreshold { return .orange }
        return .red
    }

    // Catmull-Rom smoothed path through points.
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count < 3 {
            for p in pts.dropFirst() { path.addLine(to: p) }
            return path
        }
        for i in 0..<pts.count - 1 {
            let p0 = i == 0 ? pts[0] : pts[i - 1]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func niceCeil(_ v: Double) -> Double {
        guard v > 0 else { return 10 }
        let exp = floor(log10(v))
        let base = pow(10, exp)
        let n = v / base
        let nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10
        return Double(nice) * base
    }
}

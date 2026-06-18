import SwiftUI

struct HeatmapView: View {
    let hostID: UUID
    var days: Int = 7

    private let gap: CGFloat = 2

    var body: some View {
        let grid = UptimeStore.shared.grid(hostID: hostID, days: days)
        let dayLabels = makeDayLabels()

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Доступность по часам").font(.headline)
                Spacer()
                legend
            }

            VStack(spacing: gap) {
                // Hour axis
                HStack(spacing: gap) {
                    Color.clear.frame(width: 34, height: 10)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour % 6 == 0 ? "\(hour)" : "")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(grid.enumerated()), id: \.offset) { row, cells in
                    HStack(spacing: gap) {
                        Text(dayLabels[row])
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, value in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: value))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("0%").font(.system(size: 8)).foregroundColor(.secondary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: Double(i) / 4.0))
                    .frame(width: 12, height: 10)
            }
            Text("100%").font(.system(size: 8)).foregroundColor(.secondary)
        }
    }

    // No data → gray; otherwise red (0%) → yellow (50%) → green (100%).
    private func color(for value: Double?) -> Color {
        guard let v = value else { return Color.primary.opacity(0.08) }
        if v >= 0.999 { return .green }
        if v <= 0.5 {
            return Color(hue: 0.0 + (0.13 * (v / 0.5)), saturation: 0.85, brightness: 0.85)
        } else {
            return Color(hue: 0.13 + (0.20 * ((v - 0.5) / 0.5)), saturation: 0.85, brightness: 0.8)
        }
    }

    private func makeDayLabels() -> [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "d MMM"
        return (0..<days).reversed().map { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return "" }
            return fmt.string(from: d)
        }
    }
}

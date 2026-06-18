import SwiftUI

struct TracerouteView: View {
    let host: Host
    let greenThreshold: Double
    let orangeThreshold: Double

    @StateObject private var runner = TracerouteRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13, weight: .semibold))
                Text("Трассировка маршрута").font(.headline)
                if runner.isRunning {
                    ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                }
                Spacer()
                Button {
                    if runner.isRunning { runner.cancel() }
                    else { runner.run(host: host.address) }
                } label: {
                    Label(runner.isRunning ? "Стоп" : "Запустить",
                          systemImage: runner.isRunning ? "stop.fill" : "play.fill")
                }
                .controlSize(.small)
            }

            if runner.hops.isEmpty && !runner.isRunning {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title).foregroundColor(.secondary)
                    Text("Постройте маршрут до \(host.address)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Connecting rail
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 2)
                            .padding(.leading, 12)
                            .padding(.vertical, 13)

                        VStack(spacing: 8) {
                            ForEach(runner.hops) { hop in
                                hopRow(hop)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { runner.cancel() }
    }

    @ViewBuilder
    private func hopRow(_ hop: TracerouteHop) -> some View {
        HStack(spacing: 12) {
            // Hop number badge (solid, covers the rail)
            Text("\(hop.number)")
                .font(.caption2.bold().monospacedDigit())
                .foregroundColor(hop.isTimeout ? .secondary : .white)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(hop.isTimeout ? Color.primary.opacity(0.12) : color(hop.ms))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(hop.isTimeout ? "Нет ответа" : hop.host)
                    .font(.callout.monospacedDigit())
                    .foregroundColor(hop.isTimeout ? .secondary : .primary)
            }

            Spacer()

            if let ms = hop.ms {
                Text(String(format: "%.1f мс", ms))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(color(ms))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(color(ms).opacity(0.15)))
            } else {
                Text("✶")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func color(_ ms: Double?) -> Color {
        guard let ms else { return .secondary }
        if ms < greenThreshold  { return .green }
        if ms < orangeThreshold { return .orange }
        return .red
    }
}

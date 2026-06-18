import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var service = MonitoringService.shared

    var selectedHostID: Binding<UUID?> {
        Binding(
            get: { service.selectedHostID },
            set: {
                service.selectedHostID = $0
                service.startDashboardPolling()
            }
        )
    }

    var selectedHost: Host? {
        service.hosts.first { $0.id == service.selectedHostID }
    }

    var history: [LatencyPoint] {
        guard let id = service.selectedHostID else { return [] }
        let cutoff = Date().addingTimeInterval(-60)
        return (service.latencyHistory[id] ?? []).filter { $0.timestamp >= cutoff }
    }

    var recentResults: [LatencyPoint] {
        guard let id = service.selectedHostID else { return [] }
        let all = service.latencyHistory[id] ?? []
        return Array(all.suffix(20).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("График задержки").font(.title2).bold()
                Spacer()
                Picker("Хост", selection: selectedHostID) {
                    Text("Выберите хост").tag(Optional<UUID>.none)
                    ForEach(service.hosts) { host in
                        Text(host.name).tag(Optional(host.id))
                    }
                }
                .frame(width: 200)
                .onAppear {
                    if service.selectedHostID == nil {
                        service.selectedHostID = service.hosts.first?.id
                    }
                }
            }

            // Chart
            if service.hosts.isEmpty {
                emptyState(icon: "server.rack", title: "Нет хостов", subtitle: "Добавьте хосты во вкладке «Хосты»")
            } else if history.isEmpty {
                emptyState(icon: "chart.line.uptrend.xyaxis", title: "Нет данных", subtitle: "Ожидание первого опроса...")
            } else {
                let now = Date()
                let xMin = now.addingTimeInterval(-60)
                let xMax = now.addingTimeInterval(2)

                Chart(history) { point in
                    LineMark(
                        x: .value("Время", point.timestamp),
                        y: .value("мс", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                    AreaMark(
                        x: .value("Время", point.timestamp),
                        y: .value("мс", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor.opacity(0.1))
                }
                .chartXScale(domain: xMin...xMax)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            Text("\(value.as(Double.self).map { Int($0) } ?? 0) мс")
                        }
                    }
                }
                .frame(height: 180)
            }

            // Stats row
            if let host = selectedHost {
                HStack(spacing: 20) {
                    Label(host.isAvailable ? "Доступен" : "Недоступен",
                          systemImage: host.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(host.isAvailable ? .green : .red)

                    if let ms = host.lastLatency {
                        Text(String(format: "Последний: %.1f мс", ms)).foregroundColor(.secondary)
                    }
                    if !recentResults.isEmpty {
                        let avg = recentResults.map(\.value).reduce(0, +) / Double(recentResults.count)
                        let min = recentResults.map(\.value).min() ?? 0
                        let max = recentResults.map(\.value).max() ?? 0
                        Text(String(format: "Среднее: %.1f мс", avg)).foregroundColor(.secondary)
                        Text(String(format: "Min: %.1f / Max: %.1f мс", min, max)).foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }

            Divider()

            // Last 20 results table
            if !recentResults.isEmpty {
                Text("Последние результаты").font(.headline)

                let columns: [GridItem] = [
                    GridItem(.fixed(160), alignment: .leading),
                    GridItem(.flexible(), alignment: .trailing)
                ]

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 0) {
                        // Header
                        Text("Время").font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
                        Text("Задержка").font(.caption).foregroundColor(.secondary).padding(.vertical, 4)

                        ForEach(recentResults) { point in
                            Text(point.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .padding(.vertical, 3)
                            Text(String(format: "%.1f мс", point.value))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(latencyColor(point.value))
                                .padding(.vertical, 3)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .onAppear { service.startDashboardPolling() }
        .onDisappear { service.stopDashboardPolling() }
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 50 { return .green }
        if ms < 150 { return .orange }
        return .red
    }

    @ViewBuilder
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: icon).font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.headline).padding(.top, 8)
            Text(subtitle).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

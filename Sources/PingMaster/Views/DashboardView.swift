import SwiftUI

struct DashboardView: View {
    @ObservedObject var service = MonitoringService.shared
    @ObservedObject var settings = GlobalSettings.shared

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
        return Array((service.latencyHistory[id] ?? []).suffix(20).reversed())
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
            }

            // Chart
            if service.hosts.isEmpty {
                emptyState(icon: "server.rack", title: "Нет хостов",
                           subtitle: "Добавьте хосты во вкладке «Хосты»")
            } else if history.isEmpty {
                emptyState(icon: "chart.bar.xaxis", title: "Нет данных",
                           subtitle: "Ожидание первого опроса...")
            } else {
                SparklineChartView(
                    points: history,
                    greenThreshold: settings.greenThreshold,
                    orangeThreshold: settings.orangeThreshold
                )
                .frame(height: 160)
            }

            // Stats row
            if let host = selectedHost {
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(host.isAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(host.isAvailable ? "Доступен" : "Недоступен")
                    }

                    if let ms = host.lastLatency {
                        statBadge("Последний", String(format: "%.1f мс", ms))
                    }
                    if !recentResults.isEmpty {
                        let avg = recentResults.map(\.value).reduce(0, +) / Double(recentResults.count)
                        let minV = recentResults.map(\.value).min() ?? 0
                        let maxV = recentResults.map(\.value).max() ?? 0
                        statBadge("Среднее", String(format: "%.1f мс", avg))
                        statBadge("Мин", String(format: "%.1f мс", minV))
                        statBadge("Макс", String(format: "%.1f мс", maxV))
                    }
                    Spacer()
                }
                .font(.caption)
            }

            Divider()

            // Last 20 results
            if !recentResults.isEmpty {
                Text("Последние результаты").font(.headline)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(recentResults.enumerated()), id: \.element.id) { idx, point in
                            HStack {
                                Text(point.timestamp, format: .dateTime.hour().minute().second())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f мс", point.value))
                                    .foregroundColor(latencyColor(point.value))
                            }
                            .font(.caption.monospacedDigit())
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(idx % 2 == 0 ? Color.primary.opacity(0.03) : Color.clear)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            if service.selectedHostID == nil {
                service.selectedHostID = service.hosts.first?.id
            }
            service.startDashboardPolling()
        }
        .onDisappear { service.stopDashboardPolling() }
        .onChange(of: service.selectedHostID) { _ in service.startDashboardPolling() }
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < settings.greenThreshold  { return .green }
        if ms < settings.orangeThreshold { return .orange }
        return .red
    }

    @ViewBuilder
    private func statBadge(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundColor(.secondary)
            Text(value).monospacedDigit()
        }
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
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

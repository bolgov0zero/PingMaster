import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var service = MonitoringService.shared
    @State private var selectedHostID: UUID? = nil

    var selectedHost: Host? {
        service.hosts.first { $0.id == selectedHostID }
    }

    var history: [LatencyPoint] {
        guard let id = selectedHostID else { return [] }
        let cutoff = Date().addingTimeInterval(-60)
        return (service.latencyHistory[id] ?? []).filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("График задержки").font(.title2).bold()
                Spacer()
                Picker("Хост", selection: $selectedHostID) {
                    Text("Выберите хост").tag(Optional<UUID>.none)
                    ForEach(service.hosts) { host in
                        Text(host.name).tag(Optional(host.id))
                    }
                }
                .frame(width: 200)
                .onAppear {
                    if selectedHostID == nil {
                        selectedHostID = service.hosts.first?.id
                    }
                }
            }

            if service.hosts.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "server.rack").font(.largeTitle).foregroundColor(.secondary)
                    Text("Нет хостов").font(.headline).padding(.top, 8)
                    Text("Добавьте хосты во вкладке «Хосты»").foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if history.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundColor(.secondary)
                    Text("Нет данных").font(.headline).padding(.top, 8)
                    Text("Ожидание первого опроса...").foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
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
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Double.self).map { Int($0) } ?? 0) мс") }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let host = selectedHost {
                HStack(spacing: 20) {
                    Label(host.isAvailable ? "Доступен" : "Недоступен",
                          systemImage: host.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(host.isAvailable ? .green : .red)

                    if let ms = host.lastLatency {
                        Text(String(format: "Последний: %.0f мс", ms))
                            .foregroundColor(.secondary)
                    }

                    if !history.isEmpty {
                        let avg = history.map(\.value).reduce(0, +) / Double(history.count)
                        Text(String(format: "Среднее: %.0f мс", avg))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(20)
    }
}

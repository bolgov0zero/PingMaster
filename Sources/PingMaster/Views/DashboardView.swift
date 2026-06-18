import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var service = MonitoringService.shared
    @ObservedObject var settings = GlobalSettings.shared
    @State private var period: ChartPeriod = .online

    var selectedHost: Host? {
        service.hosts.first { $0.id == service.selectedHostID }
    }

    var history: [LatencyPoint] {
        guard let id = service.selectedHostID else { return [] }
        return service.latencyHistory[id] ?? []
    }

    var recentResults: [LatencyPoint] {
        guard let id = service.selectedHostID else { return [] }
        return Array((service.latencyHistory[id] ?? []).suffix(20).reversed())
    }

    var body: some View {
        Group {
            if service.hosts.isEmpty {
                emptyState(icon: "server.rack", title: "Нет хостов",
                           subtitle: "Добавьте хосты во вкладке «Хосты»")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    hostChips
                    if !service.networkAvailable { offlineBanner }
                    if let host = selectedHost {
                        // Top row: compact hero on the left, heatmap on the right.
                        HStack(alignment: .top, spacing: 12) {
                            heroCard(host)
                                .frame(width: 320)
                            if let id = service.selectedHostID {
                                card(fill: true) { HeatmapView(hostID: id, days: 7) }
                            }
                        }
                        .frame(height: 190)

                        statsCards

                        // Flexible chart and bottom row share the remaining
                        // height; each keeps a guaranteed minimum.
                        chartCard
                            .frame(minHeight: 140, maxHeight: .infinity)

                        HStack(alignment: .top, spacing: 12) {
                            card(fill: true) {
                                TracerouteView(host: host,
                                               greenThreshold: settings.greenThreshold,
                                               orangeThreshold: settings.orangeThreshold)
                                    .id(host.id)  // reset runner on host switch
                            }
                            recentCard
                                .frame(width: 240)
                        }
                        .frame(minHeight: 200, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(16)
            }
        }
        .onAppear {
            if service.selectedHostID == nil {
                service.selectedHostID = service.hosts.first?.id
            }
        }
    }

    // MARK: - Host selector chips

    private var hostChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(service.hosts) { host in
                    let selected = host.id == service.selectedHostID
                    Button {
                        service.selectedHostID = host.id
                    } label: {
                        Text(host.name).fontWeight(selected ? .semibold : .regular)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var offlineBanner: some View {
        Label("Нет сети — мониторинг приостановлен", systemImage: "wifi.slash")
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - Hero card

    @ViewBuilder
    private func heroCard(_ host: Host) -> some View {
        let status = service.status(for: host)
        card(fill: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Title row
                HStack(spacing: 8) {
                    Circle().fill(status.color).frame(width: 11, height: 11)
                    Text(host.name).font(.headline).lineLimit(1)
                    Spacer()
                    Text(host.isAvailable ? "Доступен" : "Недоступен")
                        .font(.caption.weight(.medium))
                        .foregroundColor(host.isAvailable ? .green : .red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill((host.isAvailable ? Color.green : Color.red).opacity(0.15)))
                }

                Text(host.address)
                    .font(.caption.monospaced()).foregroundColor(.secondary)
                    .lineLimit(1).textSelection(.enabled)
                    .padding(.top, 2)

                // Big latency
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(host.lastLatency.map { String(format: "%.0f", $0) } ?? "–")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(status.color)
                    Text("мс").font(.title3).foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Info chips
                HStack(spacing: 6) {
                    chip(host.method.rawValue, system: "dot.radiowaves.left.and.right")
                    if let pct = service.uptimePercent(for: host) {
                        chip(String(format: "%.0f%% аптайм", pct), system: "checkmark.seal")
                    }
                    if host.method == .https, let days = host.sslDaysLeft {
                        chip("SSL \(days)д", system: days <= 14 ? "exclamationmark.shield" : "lock.shield",
                             tint: days <= 14 ? .orange : .secondary)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 8)

                Divider()

                Button {
                    openTerminal("ping \(host.address)")
                } label: {
                    Label("Открыть в терминале", systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .padding(.top, 8)
            }
        }
    }

    private func chip(_ text: String, system: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 9))
            Text(text).font(.caption2)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Stats cards

    private var statsCards: some View {
        let window = Array(history.suffix(60).map(\.value))
        return HStack(spacing: 10) {
            statCard("Среднее", window.isEmpty ? "–" : String(format: "%.0f", window.reduce(0,+) / Double(window.count)))
            statCard("Мин", window.min().map { String(format: "%.0f", $0) } ?? "–")
            statCard("Макс", window.max().map { String(format: "%.0f", $0) } ?? "–")
            statCard("Джиттер", jitter(window).map { String(format: "%.0f", $0) } ?? "–")
        }
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Chart card

    private var onlineSeries: [LatencyPoint] {
        guard let id = service.selectedHostID else { return [] }
        return service.latencyHistory[id] ?? []
    }

    private var slottedSeries: [LatencyPoint?] {
        guard let id = service.selectedHostID else { return [] }
        _ = service.latencyHistory[id]?.count  // re-render on each poll
        return LatencyStore.shared.slottedSeries(hostID: id, period: period)
    }

    private var chartCard: some View {
        card(fill: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Задержка").font(.headline)
                    Spacer()
                    Picker("", selection: $period) {
                        ForEach(ChartPeriod.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                chartBody
            }
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        if period == .online {
            if onlineSeries.isEmpty {
                chartEmpty
            } else {
                SparklineChartView(points: onlineSeries,
                                   greenThreshold: settings.greenThreshold,
                                   orangeThreshold: settings.orangeThreshold,
                                   dateStyle: tooltipStyle)
                    .frame(maxHeight: .infinity)
            }
        } else {
            let slots = slottedSeries
            if slots.allSatisfy({ $0 == nil }) {
                chartEmpty
            } else {
                SparklineChartView(points: [],
                                   greenThreshold: settings.greenThreshold,
                                   orangeThreshold: settings.orangeThreshold,
                                   dateStyle: tooltipStyle,
                                   slots: slots)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var chartEmpty: some View {
        emptyState(icon: "chart.bar.xaxis", title: "Нет данных",
                   subtitle: "Ожидание первого опроса...")
    }

    private var tooltipStyle: Date.FormatStyle {
        switch period {
        case .online: return .dateTime.hour().minute().second()
        case .day:    return .dateTime.hour().minute()
        case .month:  return .dateTime.day().month()
        case .year:   return .dateTime.month().year()
        }
    }

    // MARK: - Recent results card

    private var recentCard: some View {
        card(fill: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Последние результаты").font(.headline)
                if recentResults.isEmpty {
                    Text("Нет данных").font(.caption).foregroundColor(.secondary)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(recentResults.enumerated()), id: \.element.id) { idx, point in
                                HStack {
                                    Text(point.timestamp, format: .dateTime.hour().minute().second())
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f мс", point.value))
                                        .foregroundColor(latencyColor(point.value))
                                }
                                .font(.caption.monospacedDigit())
                                .padding(.vertical, 3).padding(.horizontal, 4)
                                .background(idx % 2 == 0 ? Color.primary.opacity(0.03) : Color.clear)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func card<Content: View>(fill: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    // Mean absolute difference between consecutive samples.
    private func jitter(_ vals: [Double]) -> Double? {
        guard vals.count >= 2 else { return nil }
        var sum = 0.0
        for i in 1..<vals.count { sum += abs(vals[i] - vals[i - 1]) }
        return sum / Double(vals.count - 1)
    }

    private func openTerminal(_ command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command)\"\ntell application \"Terminal\" to activate"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < settings.greenThreshold  { return .green }
        if ms < settings.orangeThreshold { return .orange }
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
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

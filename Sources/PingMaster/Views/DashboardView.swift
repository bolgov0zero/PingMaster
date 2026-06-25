import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var service = MonitoringService.shared
    @ObservedObject var settings = GlobalSettings.shared
    @ObservedObject var live = LivePinger.shared
    @State private var period: ChartPeriod = .online

    // Continuous ping applies on the Онлайн view for ICMP hosts only.
    private var useLivePing: Bool {
        period == .online && selectedHost?.method == .ping
    }

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

                        // Flexible chart and bottom row share the remaining
                        // height; each keeps a guaranteed minimum.
                        chartCard
                            .frame(minHeight: 150, maxHeight: .infinity)

                        HStack(alignment: .top, spacing: 12) {
                            card(fill: true) {
                                TracerouteView(host: host,
                                               greenThreshold: settings.greenThreshold,
                                               orangeThreshold: settings.orangeThreshold)
                                    .id(host.id)  // reset runner on host switch
                            }
                            statsCard(host)
                                .frame(width: 320)
                        }
                        .frame(minHeight: 210, maxHeight: .infinity)
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
            syncLive()
        }
        .onDisappear { live.stop() }
        .onChange(of: period) { _ in syncLive() }
        .onChange(of: service.selectedHostID) { _ in syncLive() }
    }

    private func syncLive() {
        if useLivePing, let host = selectedHost {
            live.start(address: host.address)
        } else {
            live.stop()
        }
    }

    // MARK: - Host selector chips

    // Ordered by section (section1's hosts, section2's hosts, …) then «Без раздела».
    private var chipHosts: [Host] {
        service.sections.flatMap { service.hosts(in: $0.id) } + service.hosts(in: nil)
    }

    private var hostChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chipHosts) { host in
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

    // MARK: - Stats card

    @ViewBuilder
    private func statsCard(_ host: Host) -> some View {
        // When the live ping drives the Онлайн view, stats come from it.
        let source = useLivePing ? live.points : history
        let window = Array(source.suffix(60).map(\.value))
        let d: (sent: Int, received: Int) = useLivePing
            ? (live.sent, live.received)
            : service.delivery(for: host, count: 60)
        let loss = d.sent > 0 ? Double(d.sent - d.received) / Double(d.sent) * 100 : 0
        let avg = window.isEmpty ? nil : window.reduce(0, +) / Double(window.count)
        let grade = self.grade(avg: avg, loss: loss)
        let lastPings = Array(source.suffix(10))  // oldest → newest

        card(fill: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Статистика").font(.headline)
                    Spacer()
                    Text(grade.letter)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(grade.color))
                }

                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 8) {
                    statTile("paperplane.fill", "Отпр.", "\(d.sent)", .secondary)
                    statTile("checkmark.circle.fill", "Получ.", "\(d.received)", .green)
                    statTile("exclamationmark.triangle.fill", "Потери",
                             String(format: "%.0f%%", loss), loss > 0 ? .orange : .secondary)
                    statTile("arrow.down.to.line", "Мин",
                             window.min().map { String(format: "%.0f", $0) } ?? "–", .green)
                    statTile("arrow.up.to.line", "Макс",
                             window.max().map { String(format: "%.0f", $0) } ?? "–", .red)
                    statTile("equal.circle.fill", "Сред.",
                             avg.map { String(format: "%.0f", $0) } ?? "–", .blue)
                }

                if !lastPings.isEmpty {
                    Text("Последние пинги").font(.caption2).foregroundColor(.secondary)
                    let start = source.count - lastPings.count
                    let pillCols = [GridItem(.adaptive(minimum: 44), spacing: 5)]
                    LazyVGrid(columns: pillCols, alignment: .leading, spacing: 5) {
                        // Newest first (left); older readings shift to the right.
                        ForEach(Array(lastPings.enumerated()).reversed(), id: \.element.id) { j, p in
                            // Compare to the reading just before it in the full series.
                            let gi = start + j
                            pingPill(p.value, prev: gi > 0 ? source[gi - 1].value : nil)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func pingPill(_ value: Double, prev: Double?) -> some View {
        // Arrow vs the previous reading: up = latency rose (worse), down = fell.
        let trend: (sym: String, color: Color)? = {
            guard let prev else { return nil }
            if value > prev { return ("arrow.up", .red) }
            if value < prev { return ("arrow.down", .green) }
            return ("minus", .secondary)
        }()
        HStack(spacing: 2) {
            Text(String(format: "%.0f", value))
                .font(.caption2.monospacedDigit())
                .foregroundColor(latencyColor(value))
            if let trend {
                Image(systemName: trend.sym).font(.system(size: 7, weight: .bold))
                    .foregroundColor(trend.color)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(latencyColor(value).opacity(0.15)))
    }

    private func statTile(_ icon: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9)).foregroundColor(tint)
                Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            }
            Text(value).font(.callout.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func grade(avg: Double?, loss: Double) -> (letter: String, color: Color) {
        if loss >= 10 { return ("D", .red) }
        guard let avg else { return ("–", .secondary) }
        if loss >= 2 || avg >= settings.orangeThreshold { return ("C", .red) }
        if avg >= settings.greenThreshold { return ("B", .orange) }
        return ("A", .green)
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
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("График задержки").font(.title3).bold()
                        Text("История пинга").font(.caption2).foregroundColor(.secondary)
                    }
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

    private var chartSlots: [LatencyPoint?] {
        if period == .online {
            let pts = useLivePing ? live.points : onlineSeries
            return pts.suffix(80).map { Optional($0) }
        }
        return slottedSeries
    }

    @ViewBuilder
    private var chartBody: some View {
        let slots = chartSlots
        if slots.allSatisfy({ $0 == nil }) {
            chartEmpty
        } else {
            LineChartView(slots: slots,
                          greenThreshold: settings.greenThreshold,
                          orangeThreshold: settings.orangeThreshold,
                          dateStyle: tooltipStyle)
                .frame(maxHeight: .infinity)
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
        openInTerminal(command)
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

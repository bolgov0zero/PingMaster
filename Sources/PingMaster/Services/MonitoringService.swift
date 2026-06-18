import Foundation
import Combine

extension Notification.Name {
    static let hostStatusChanged = Notification.Name("hostStatusChanged")
}

class MonitoringService: ObservableObject {
    static let shared = MonitoringService()

    @Published var hosts: [Host] = []
    @Published var latencyHistory: [UUID: [LatencyPoint]] = [:]
    @Published var selectedHostID: UUID? = nil

    private var sources: [UUID: DispatchSourceTimer] = [:]
    private var dashboardSource: DispatchSourceTimer?
    private let saveKey = "PingMasterHosts"
    private let maxHistoryPoints = 120
    private var settingsCancellable: AnyCancellable?

    private init() {
        load()
        settingsCancellable = GlobalSettings.shared.$interval
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restartAll() }
    }

    // MARK: - Host Management

    func add(_ host: Host) {
        hosts.append(host)
        latencyHistory[host.id] = []
        save()
        startMonitoring(host)
    }

    func remove(at offsets: IndexSet) {
        offsets.forEach {
            stopMonitoring(hosts[$0])
            latencyHistory.removeValue(forKey: hosts[$0].id)
        }
        hosts.remove(atOffsets: offsets)
        save()
    }

    func update(_ host: Host) {
        stopMonitoring(host)
        save()
        startMonitoring(host)
    }

    func pingAll() {
        hosts.forEach { poll($0) }
    }

    // MARK: - Monitoring

    func startAll() {
        hosts.forEach { startMonitoring($0) }
    }

    private func restartAll() {
        hosts.forEach {
            stopMonitoring($0)
            startMonitoring($0)
        }
    }

    private func startMonitoring(_ host: Host) {
        stopMonitoring(host)
        let interval = GlobalSettings.shared.interval
        let source = makeTimer(interval: interval) { [weak self] in self?.poll(host) }
        sources[host.id] = source
        poll(host)
    }

    private func stopMonitoring(_ host: Host) {
        sources[host.id]?.cancel()
        sources.removeValue(forKey: host.id)
    }

    // MARK: - Dashboard fast polling (1s)

    func startDashboardPolling() {
        stopDashboardPolling()
        guard let id = selectedHostID, let host = hosts.first(where: { $0.id == id }) else { return }
        dashboardSource = makeTimer(interval: 1.0) { [weak self] in self?.poll(host) }
        poll(host)
    }

    func stopDashboardPolling() {
        dashboardSource?.cancel()
        dashboardSource = nil
    }

    // MARK: - Timer factory (DispatchSourceTimer — not blocked by NSMenu run loop)

    private func makeTimer(interval: Double, handler: @escaping () -> Void) -> DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }

    // MARK: - Poll

    private func poll(_ host: Host) {
        switch host.method {
        case .ping:
            PingChecker.check(host: host.address) { [weak self] latency in
                self?.handleResult(host: host, latency: latency)
            }
        case .http, .https:
            HTTPChecker.check(host: host.address, method: host.method) { [weak self] latency in
                self?.handleResult(host: host, latency: latency)
            }
        }
    }

    private func handleResult(host: Host, latency: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            host.lastLatency = latency
            if let ms = latency {
                var history = self.latencyHistory[host.id] ?? []
                history.append(LatencyPoint(timestamp: Date(), value: ms))
                if history.count > self.maxHistoryPoints { history.removeFirst() }
                self.latencyHistory[host.id] = history
                host.consecutiveFailures = 0
                host.isAvailable = true
            } else {
                host.consecutiveFailures += 1
                if host.consecutiveFailures >= host.failThreshold {
                    host.isAvailable = false
                }
            }
            NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([Host].self, from: data) else { return }
        hosts = loaded
        hosts.forEach { latencyHistory[$0.id] = [] }
    }
}

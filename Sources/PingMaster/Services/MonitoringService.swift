import Foundation
import Combine

extension Notification.Name {
    static let hostStatusChanged = Notification.Name("hostStatusChanged")
}

class MonitoringService: ObservableObject {
    static let shared = MonitoringService()

    @Published var hosts: [Host] = []
    private var timers: [UUID: Timer] = [:]
    private let saveKey = "PingMasterHosts"

    private init() {
        load()
    }

    func add(_ host: Host) {
        hosts.append(host)
        save()
        startMonitoring(host)
    }

    func remove(at offsets: IndexSet) {
        offsets.forEach { stopMonitoring(hosts[$0]) }
        hosts.remove(atOffsets: offsets)
        save()
    }

    func update(_ host: Host) {
        stopMonitoring(host)
        save()
        startMonitoring(host)
    }

    func startAll() {
        hosts.forEach { startMonitoring($0) }
    }

    private func startMonitoring(_ host: Host) {
        stopMonitoring(host)
        let timer = Timer.scheduledTimer(withTimeInterval: host.interval, repeats: true) { [weak self] _ in
            self?.poll(host)
        }
        timers[host.id] = timer
        poll(host)
    }

    private func stopMonitoring(_ host: Host) {
        timers[host.id]?.invalidate()
        timers.removeValue(forKey: host.id)
    }

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
        DispatchQueue.main.async {
            host.lastLatency = latency
            if latency == nil {
                host.consecutiveFailures += 1
                if host.consecutiveFailures >= host.failThreshold {
                    host.isAvailable = false
                }
            } else {
                host.consecutiveFailures = 0
                host.isAvailable = true
            }
            NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([Host].self, from: data) else { return }
        hosts = loaded
    }
}

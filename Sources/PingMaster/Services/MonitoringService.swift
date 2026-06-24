import Foundation
import Combine
import Network

extension Notification.Name {
    static let hostStatusChanged = Notification.Name("hostStatusChanged")
}

class MonitoringService: ObservableObject {
    static let shared = MonitoringService()

    @Published var hosts: [Host] = []
    @Published var latencyHistory: [UUID: [LatencyPoint]] = [:]
    @Published var selectedHostID: UUID? = nil

    // Host sections (groups). Hosts with sectionID == nil are «Без раздела».
    @Published var sections: [HostSection] = []
    private let sectionsKey = "PingMasterSections"

    // Collapse state is tracked separately for the menu panel and the Hosts tab.
    @Published var collapsedMenu: Set<UUID> = []
    @Published var collapsedTab: Set<UUID> = []
    @Published var uncatMenuCollapsed = false
    @Published var uncatTabCollapsed = false

    // Availability samples per host (timestamp, up?), pruned to the last 24h.
    private var availabilityLog: [UUID: [(date: Date, up: Bool)]] = [:]
    let launchDate = Date()
    private let uptimeWindow: TimeInterval = 24 * 3600

    // Auto-pause when there's no network path (avoids false-down spam).
    @Published var networkAvailable = true
    private let pathMonitor = NWPathMonitor()

    // SSL certificate expiry tracking for HTTPS hosts.
    private var sslLastChecked: [UUID: Date] = [:]
    private var sslNotified: Set<UUID> = []
    private let sslRecheckInterval: TimeInterval = 6 * 3600

    private var sources: [UUID: DispatchSourceTimer] = [:]
    private let saveKey = "PingMasterHosts"
    private let maxHistoryPoints = 120
    private var settingsCancellable: AnyCancellable?

    private init() {
        load()
        settingsCancellable = GlobalSettings.shared.$interval
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restartAll() }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.networkAvailable = (path.status == .satisfied)
                NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "pathMonitor"))
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
            availabilityLog.removeValue(forKey: hosts[$0].id)
            UptimeStore.shared.clear(hostID: hosts[$0].id)
            LatencyStore.shared.clear(hostID: hosts[$0].id)
            EventLog.shared.clear(hostID: hosts[$0].id)
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

    func pingNow(_ host: Host) {
        poll(host)
    }

    func move(from source: IndexSet, to destination: Int) {
        hosts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Export / Import

    func exportHostsData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(hosts)
    }

    /// Imports hosts from JSON, appending them with fresh IDs (non-destructive,
    /// avoids ID collisions). Returns the number of hosts added.
    @discardableResult
    func importHosts(from data: Data) -> Int {
        guard let decoded = try? JSONDecoder().decode([Host].self, from: data) else { return 0 }
        for h in decoded {
            add(Host(name: h.name, address: h.address, method: h.method,
                     failThreshold: h.failThreshold, showInMenu: h.showInMenu))
        }
        return decoded.count
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
        // Auto-pause: skip polling (and recording) while offline.
        guard networkAvailable else { return }

        checkSSLIfNeeded(host)

        switch host.method {
        case .ping:
            // Send a short burst and report the minimum RTT. The first packet
            // pays the link wake-up cost; later packets travel a warm path, so
            // the minimum matches a continuous terminal `ping`. The interval is
            // always ≥ 5s, leaving room for the ~2s burst.
            let count = GlobalSettings.shared.interval >= 4 ? 3 : 1
            PingChecker.check(host: host.address, count: count) { [weak self] latency in
                self?.handleResult(host: host, latency: latency)
            }
        case .http, .https:
            // Same burst-min idea for TCP: a few sequential connects, take min.
            let count = GlobalSettings.shared.interval >= 4 ? 3 : 1
            HTTPChecker.check(host: host.address, method: host.method, count: count) { [weak self] latency in
                self?.handleResult(host: host, latency: latency)
            }
        }
    }

    private func handleResult(host: Host, latency: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            host.lastLatency = latency
            let wasAvailable = host.isAvailable

            self.recordAvailability(host: host, up: latency != nil)

            if let ms = latency {
                var history = self.latencyHistory[host.id] ?? []
                history.append(LatencyPoint(timestamp: Date(), value: ms))
                if history.count > self.maxHistoryPoints { history.removeFirst() }
                self.latencyHistory[host.id] = history
                LatencyStore.shared.record(hostID: host.id, ms: ms)
                host.consecutiveFailures = 0
                host.isAvailable = true
                if !wasAvailable {
                    NotificationManager.shared.notifyUp(host: host)
                    EventLog.shared.record(hostID: host.id, hostName: host.name, up: true)
                }
            } else {
                host.consecutiveFailures += 1
                if host.consecutiveFailures >= host.failThreshold {
                    host.isAvailable = false
                    if wasAvailable {
                        NotificationManager.shared.notifyDown(host: host)
                        EventLog.shared.record(hostID: host.id, hostName: host.name, up: false)
                    }
                }
            }
            NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
        }
    }

    // MARK: - Availability log & uptime

    private func recordAvailability(host: Host, up: Bool) {
        var log = availabilityLog[host.id] ?? []
        log.append((Date(), up))
        let cutoff = Date().addingTimeInterval(-uptimeWindow)
        log.removeAll { $0.date < cutoff }
        availabilityLog[host.id] = log

        // Persist hourly aggregation for the heatmap.
        UptimeStore.shared.record(hostID: host.id, up: up)
    }

    // MARK: - Data management

    func clearAllData() {
        LatencyStore.shared.clearAll()
        UptimeStore.shared.clearAll()
        EventLog.shared.clearAll()
        availabilityLog.removeAll()
        for host in hosts {
            latencyHistory[host.id] = []
            host.lastLatency = nil
            host.consecutiveFailures = 0
        }
        NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
    }

    // MARK: - SSL certificate

    private func checkSSLIfNeeded(_ host: Host) {
        guard host.method == .https else { return }
        if let last = sslLastChecked[host.id],
           Date().timeIntervalSince(last) < sslRecheckInterval { return }
        sslLastChecked[host.id] = Date()

        SSLChecker.check(host: host.address) { [weak self] expiry in
            DispatchQueue.main.async {
                guard let self else { return }
                host.sslExpiry = expiry
                if let days = host.sslDaysLeft, days <= 14, days >= 0,
                   !self.sslNotified.contains(host.id) {
                    self.sslNotified.insert(host.id)
                    NotificationManager.shared.notifySSL(host: host, days: days)
                }
                NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
            }
        }
    }

    /// Sent/received counts over the last `count` polls (from the 24h log).
    func delivery(for host: Host, count: Int) -> (sent: Int, received: Int) {
        let recent = (availabilityLog[host.id] ?? []).suffix(count)
        return (recent.count, recent.filter { $0.up }.count)
    }

    /// Uptime % over the last 24h (or since launch if the app ran < 24h).
    /// Returns nil when there are no samples yet.
    func uptimePercent(for host: Host) -> Double? {
        guard let log = availabilityLog[host.id], !log.isEmpty else { return nil }
        let total = log.count
        let up = log.filter { $0.up }.count
        return Double(up) / Double(total) * 100
    }

    // MARK: - Status color

    /// green / yellow / red dot for a host, with 3-sample smoothing so a single
    /// latency spike doesn't flip the color.
    func status(for host: Host) -> HostStatus {
        if !host.isAvailable { return .red }
        let s = GlobalSettings.shared
        let recent = (latencyHistory[host.id] ?? []).suffix(3).map(\.value)
        guard recent.count >= 3 else { return .green }
        // zone: 0 green, 1 orange, 2 red
        func zone(_ ms: Double) -> Int {
            if ms < s.greenThreshold  { return 0 }
            if ms < s.orangeThreshold { return 1 }
            return 2
        }
        let zones = recent.map(zone)
        if zones.allSatisfy({ $0 == 2 }) { return .red }
        if zones.allSatisfy({ $0 >= 1 }) { return .yellow }
        return .green
    }

    /// Aggregate status for a section: red if any host red/down, else yellow if
    /// any yellow, else green if all green, gray if empty.
    func sectionStatus(_ sectionID: UUID?) -> HostStatus? {
        let group = hosts(in: sectionID)
        guard !group.isEmpty else { return nil }
        let statuses = group.map { status(for: $0) }
        if statuses.contains(.red) { return .red }
        if statuses.contains(.yellow) { return .yellow }
        return .green
    }

    // MARK: - Sections

    func hosts(in sectionID: UUID?) -> [Host] {
        hosts.filter { $0.sectionID == sectionID }
    }

    func addSection(name: String) {
        sections.append(HostSection(name: name))
        saveSections()
    }

    func moveSection(_ id: UUID, before targetID: UUID) {
        guard id != targetID, let from = sections.firstIndex(where: { $0.id == id }) else { return }
        let moving = sections.remove(at: from)
        let to = sections.firstIndex(where: { $0.id == targetID }) ?? sections.count
        sections.insert(moving, at: to)
        saveSections()
        objectWillChange.send()
    }

    func renameSection(_ id: UUID, to name: String) {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[i].name = name
        saveSections()
    }

    func removeSection(_ id: UUID) {
        // Move its hosts back to «Без раздела».
        hosts.forEach { if $0.sectionID == id { $0.sectionID = nil } }
        sections.removeAll { $0.id == id }
        collapsedMenu.remove(id)
        collapsedTab.remove(id)
        saveSections()
        saveCollapse()
        save()
    }

    enum CollapseScope { case menu, tab }

    func isCollapsed(_ sectionID: UUID?, _ scope: CollapseScope) -> Bool {
        if let id = sectionID {
            return scope == .menu ? collapsedMenu.contains(id) : collapsedTab.contains(id)
        }
        return scope == .menu ? uncatMenuCollapsed : uncatTabCollapsed
    }

    func toggleCollapse(_ sectionID: UUID?, _ scope: CollapseScope) {
        if let id = sectionID {
            if scope == .menu { collapsedMenu.formSymmetricDifference([id]) }
            else { collapsedTab.formSymmetricDifference([id]) }
        } else {
            if scope == .menu { uncatMenuCollapsed.toggle() } else { uncatTabCollapsed.toggle() }
        }
        saveCollapse()
    }

    private func saveCollapse() {
        let d = UserDefaults.standard
        d.set(collapsedMenu.map(\.uuidString), forKey: "collapsedMenu")
        d.set(collapsedTab.map(\.uuidString), forKey: "collapsedTab")
        d.set(uncatMenuCollapsed, forKey: "uncatMenuCollapsed")
        d.set(uncatTabCollapsed, forKey: "uncatTabCollapsed")
    }

    private func loadCollapse() {
        let d = UserDefaults.standard
        collapsedMenu = Set((d.array(forKey: "collapsedMenu") as? [String] ?? []).compactMap { UUID(uuidString: $0) })
        collapsedTab = Set((d.array(forKey: "collapsedTab") as? [String] ?? []).compactMap { UUID(uuidString: $0) })
        uncatMenuCollapsed = d.bool(forKey: "uncatMenuCollapsed")
        uncatTabCollapsed = d.bool(forKey: "uncatTabCollapsed")
    }

    /// Moves `host` so it sits right before `target` (and into target's section).
    func moveHost(_ host: Host, before target: Host) {
        guard host.id != target.id, let from = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts.remove(at: from)
        host.sectionID = target.sectionID
        let to = hosts.firstIndex(where: { $0.id == target.id }) ?? hosts.count
        hosts.insert(host, at: to)
        save()
        objectWillChange.send()
    }

    /// Moves `host` to the end of the given section.
    func moveHost(_ host: Host, toSection sectionID: UUID?) {
        guard let from = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts.remove(at: from)
        host.sectionID = sectionID
        // Insert after the last host already in that section, else append.
        if let lastIdx = hosts.lastIndex(where: { $0.sectionID == sectionID }) {
            hosts.insert(host, at: lastIdx + 1)
        } else {
            hosts.append(host)
        }
        save()
        objectWillChange.send()
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func saveSections() {
        if let data = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(data, forKey: sectionsKey)
        }
    }

    private func load() {
        loadCollapse()
        if let sdata = UserDefaults.standard.data(forKey: sectionsKey),
           let loadedSections = try? JSONDecoder().decode([HostSection].self, from: sdata) {
            sections = loadedSections
        }
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([Host].self, from: data) else { return }
        hosts = loaded
        hosts.forEach { latencyHistory[$0.id] = [] }
        // Drop section references that no longer exist.
        let ids = Set(sections.map(\.id))
        hosts.forEach { if let sid = $0.sectionID, !ids.contains(sid) { $0.sectionID = nil } }
    }
}

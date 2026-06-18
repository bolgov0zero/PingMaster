import Foundation

struct StatusEvent: Codable, Identifiable {
    var id = UUID()
    let hostID: UUID
    let hostName: String
    let up: Bool
    let date: Date
}

// Persistent log of host up/down transitions. Survives restarts.
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var events: [StatusEvent] = []  // oldest → newest

    private let url: URL
    private let ioQueue = DispatchQueue(label: "EventLog.io")

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PingMaster", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("events.json")
        load()
    }

    func record(hostID: UUID, hostName: String, up: Bool) {
        events.append(StatusEvent(hostID: hostID, hostName: hostName, up: up, date: Date()))
        save()
    }

    func clear(hostID: UUID) {
        events.removeAll { $0.hostID == hostID }
        save()
    }

    func clearAll() {
        events.removeAll()
        save()
    }

    private func save() {
        let snapshot = events
        ioQueue.async { [url] in
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StatusEvent].self, from: data) else { return }
        events = decoded
    }
}

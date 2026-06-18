import Foundation

enum PollMethod: String, Codable, CaseIterable {
    case ping = "Ping (ICMP)"
    case http = "HTTP"
    case https = "HTTPS"
}

struct LatencyPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double  // ms, nil-safe: timeouts not stored
}

class Host: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var name: String
    @Published var address: String
    @Published var method: PollMethod
    @Published var failThreshold: Int
    @Published var showInMenu: Bool

    @Published var isAvailable: Bool = true
    @Published var lastLatency: Double? = nil
    @Published var consecutiveFailures: Int = 0
    @Published var sslExpiry: Date? = nil  // runtime only, HTTPS hosts

    var sslDaysLeft: Int? {
        guard let sslExpiry else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: sslExpiry).day
    }

    init(id: UUID = UUID(), name: String, address: String,
         method: PollMethod = .ping, failThreshold: Int = 3, showInMenu: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.method = method
        self.failThreshold = failThreshold
        self.showInMenu = showInMenu
    }

    enum CodingKeys: String, CodingKey {
        case id, name, address, method, failThreshold, showInMenu
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        method = try c.decode(PollMethod.self, forKey: .method)
        failThreshold = try c.decodeIfPresent(Int.self, forKey: .failThreshold) ?? 3
        showInMenu = try c.decodeIfPresent(Bool.self, forKey: .showInMenu) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(method, forKey: .method)
        try c.encode(failThreshold, forKey: .failThreshold)
        try c.encode(showInMenu, forKey: .showInMenu)
    }
}

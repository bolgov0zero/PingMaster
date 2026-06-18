import Foundation

enum PollMethod: String, Codable, CaseIterable {
    case ping = "Ping (ICMP)"
    case http = "HTTP"
    case https = "HTTPS"
}

class Host: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var name: String
    @Published var address: String
    @Published var method: PollMethod
    @Published var interval: Double  // seconds
    @Published var failThreshold: Int

    @Published var isAvailable: Bool = true
    @Published var lastLatency: Double? = nil
    @Published var consecutiveFailures: Int = 0

    init(id: UUID = UUID(), name: String, address: String,
         method: PollMethod = .ping, interval: Double = 30, failThreshold: Int = 3) {
        self.id = id
        self.name = name
        self.address = address
        self.method = method
        self.interval = interval
        self.failThreshold = failThreshold
    }

    enum CodingKeys: String, CodingKey {
        case id, name, address, method, interval, failThreshold
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        method = try c.decode(PollMethod.self, forKey: .method)
        interval = try c.decode(Double.self, forKey: .interval)
        failThreshold = try c.decode(Int.self, forKey: .failThreshold)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(method, forKey: .method)
        try c.encode(interval, forKey: .interval)
        try c.encode(failThreshold, forKey: .failThreshold)
    }
}

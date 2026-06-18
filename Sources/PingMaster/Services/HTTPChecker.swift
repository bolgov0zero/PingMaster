import Foundation
import Network

class HTTPChecker {
    /// Performs `count` TCP connections in sequence and reports the minimum
    /// connect time — the warm/best case, less affected by transient jitter
    /// (mirrors the ICMP burst behaviour). Returns nil only if all attempts fail.
    static func check(host: String, method: PollMethod, count: Int = 1,
                      completion: @escaping (Double?) -> Void) {
        // Parse host and port from address
        var hostname = host
        var port: UInt16 = method == .https ? 443 : 80

        for scheme in ["https://", "http://"] {
            if hostname.hasPrefix(scheme) {
                hostname = String(hostname.dropFirst(scheme.count))
                break
            }
        }
        if let slash = hostname.firstIndex(of: "/") {
            hostname = String(hostname[..<slash])
        }
        if let colon = hostname.lastIndex(of: ":"),
           let p = UInt16(hostname[hostname.index(after: colon)...]) {
            port = p
            hostname = String(hostname[..<colon])
        }

        guard !hostname.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(nil)
            return
        }

        runSequence(hostname: hostname, port: nwPort,
                    remaining: max(1, count), best: nil, completion: completion)
    }

    // Runs one connection, then recurses for the rest, tracking the minimum.
    private static func runSequence(hostname: String, port: NWEndpoint.Port,
                                    remaining: Int, best: Double?,
                                    completion: @escaping (Double?) -> Void) {
        connectOnce(hostname: hostname, port: port) { ms in
            let newBest: Double?
            switch (best, ms) {
            case let (b?, m?): newBest = Swift.min(b, m)
            case (nil, let m?): newBest = m
            case (let b, nil):  newBest = b
            }
            if remaining <= 1 {
                completion(newBest)
            } else {
                runSequence(hostname: hostname, port: port,
                            remaining: remaining - 1, best: newBest, completion: completion)
            }
        }
    }

    private static func connectOnce(hostname: String, port: NWEndpoint.Port,
                                    completion: @escaping (Double?) -> Void) {
        let connection = NWConnection(host: NWEndpoint.Host(hostname), port: port, using: .tcp)
        let start = Date()
        var done = false

        connection.stateUpdateHandler = { state in
            guard !done else { return }
            switch state {
            case .ready:
                done = true
                let ms = Date().timeIntervalSince(start) * 1000
                connection.cancel()
                completion(ms)
            case .failed, .cancelled:
                if !done {
                    done = true
                    completion(nil)
                }
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            guard !done else { return }
            done = true
            connection.cancel()
            completion(nil)
        }
    }
}

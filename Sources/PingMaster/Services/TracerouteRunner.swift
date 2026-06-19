import Foundation

struct TracerouteHop: Identifiable {
    let id = UUID()
    let number: Int
    let host: String      // IP, or "*" when no reply
    let ms: Double?
    var isTimeout: Bool { host == "*" }
}

// ICMP traceroute built on top of `/sbin/ping` with an increasing TTL.
// This avoids the raw socket that `/usr/sbin/traceroute` needs (which requires
// setuid/root and is blocked for an unsigned / translocated .app), while still
// behaving like ICMP traceroute: it terminates at the real host.
final class TracerouteRunner: ObservableObject {
    @Published var hops: [TracerouteHop] = []
    @Published var isRunning = false

    private let maxHops = 20
    private let queue = DispatchQueue(label: "traceroute", qos: .userInitiated)
    private var cancelled = false
    private var currentProcess: Process?

    func run(host rawHost: String) {
        cancel()
        hops = []
        cancelled = false
        isRunning = true

        let host = Self.sanitize(rawHost)
        guard !host.isEmpty else { isRunning = false; return }

        queue.async { [weak self] in self?.loop(host: host) }
    }

    func cancel() {
        cancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        isRunning = false  // called on main (run/cancel button/onDisappear)
    }

    // MARK: - Probing

    private func loop(host: String) {
        for ttl in 1...maxHops {
            if cancelled { break }
            let (hop, reached) = probe(host: host, ttl: ttl)
            if cancelled { break }
            DispatchQueue.main.async { self.hops.append(hop) }
            if reached { break }
        }
        DispatchQueue.main.async { self.isRunning = false }
    }

    private func probe(host: String, ttl: Int) -> (hop: TracerouteHop, reached: Bool) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // We don't wait for ping to finish (it lingers for the full timeout even
        // after the ICMP error arrives). Instead we read its streamed output and
        // stop the moment the hop line appears, so RTT = line-arrival time.
        // -W 1000: no-reply hops give up after 1s.
        proc.arguments = ["-c", "1", "-n", "-m", "\(ttl)", "-W", "1000", host]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        let fh = pipe.fileHandleForReading
        let sem = DispatchSemaphore(value: 0)
        var buffer = ""
        var result: (TracerouteHop, Bool)?
        let start = Date()

        let finish: (TracerouteHop, Bool) -> Void = { hop, reached in
            if result == nil { result = (hop, reached); sem.signal() }
        }

        fh.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty else { return }
            buffer += String(decoding: d, as: UTF8.self)
            let elapsed = Date().timeIntervalSince(start) * 1000
            if let ip = Self.firstGroup(#"from ([0-9.]+): icmp_seq"#, buffer) {
                let t = Self.firstGroup(#"time[=<]([0-9.]+)"#, buffer).flatMap(Double.init) ?? elapsed
                finish(TracerouteHop(number: ttl, host: ip, ms: t), true)
            } else if let ip = Self.firstGroup(#"from ([0-9.]+): Time to live exceeded"#, buffer) {
                finish(TracerouteHop(number: ttl, host: ip, ms: elapsed), false)
            }
        }
        proc.terminationHandler = { _ in sem.signal() }  // no reply → unblock

        currentProcess = proc
        do { try proc.run() } catch {
            fh.readabilityHandler = nil
            return (TracerouteHop(number: ttl, host: "*", ms: nil), false)
        }

        _ = sem.wait(timeout: .now() + 2.5)
        fh.readabilityHandler = nil
        if proc.isRunning { proc.terminate() }
        currentProcess = nil

        return result ?? (TracerouteHop(number: ttl, host: "*", ms: nil), false)
    }

    // MARK: - Helpers

    private static func firstGroup(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func sanitize(_ raw: String) -> String {
        var host = raw
        for s in ["https://", "http://"] {
            if host.hasPrefix(s) { host = String(host.dropFirst(s.count)) }
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        if let colon = host.lastIndex(of: ":"),
           host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        return host
    }
}

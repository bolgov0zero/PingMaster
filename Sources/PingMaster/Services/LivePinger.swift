import Foundation

// Continuous `ping` (one persistent process, like the terminal) used only by
// the dashboard's "Онлайн" view. Streams parsed RTTs live; nothing is saved to
// history — the regular interval polling owns the persistent data.
final class LivePinger: ObservableObject {
    static let shared = LivePinger()

    @Published private(set) var points: [LatencyPoint] = []
    @Published private(set) var sent: Int = 0
    @Published private(set) var received: Int = 0

    private var process: Process?
    private var currentAddress: String?
    private let maxPoints = 300

    private init() {}

    func start(address rawAddress: String) {
        let host = Self.hostname(from: rawAddress)
        guard !host.isEmpty else { return }
        // Already pinging this host — keep the live stream going.
        if currentAddress == host, process != nil { return }
        stop()
        currentAddress = host
        points = []
        sent = 0
        received = 0

        let proc = Process()
        // Under `script` for an unbuffered, line-by-line stream (pty).
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        proc.arguments = ["-q", "/dev/null", "/sbin/ping", host]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            buffer += str
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl])
                buffer = String(buffer[buffer.index(after: nl)...])
                if let ms = Self.parseRTT(line) {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.sent += 1
                        self.received += 1
                        self.points.append(LatencyPoint(timestamp: Date(), value: ms))
                        if self.points.count > self.maxPoints { self.points.removeFirst() }
                    }
                } else if Self.isTimeout(line) {
                    DispatchQueue.main.async { self?.sent += 1 }
                }
            }
        }

        proc.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try proc.run()
            process = proc
        } catch {
            currentAddress = nil
        }
    }

    func stop() {
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        currentAddress = nil
    }

    private static func isTimeout(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("timeout") ||
        line.localizedCaseInsensitiveContains("100% packet loss")
    }

    private static func parseRTT(_ line: String) -> Double? {
        guard let r = line.range(of: #"time[=<]([\d.]+)"#, options: .regularExpression) else { return nil }
        let num = line[r].drop { !$0.isNumber && $0 != "." }
        return Double(num)
    }

    private static func hostname(from raw: String) -> String {
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

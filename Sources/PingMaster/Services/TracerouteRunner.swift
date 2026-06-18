import Foundation

struct TracerouteHop: Identifiable {
    let id = UUID()
    let number: Int
    let host: String      // IP, or "*" when no reply
    let ms: Double?
    var isTimeout: Bool { host == "*" }
}

// Runs the system traceroute and streams parsed hops as they arrive.
final class TracerouteRunner: ObservableObject {
    @Published var hops: [TracerouteHop] = []
    @Published var isRunning = false

    private var process: Process?

    func run(host rawHost: String) {
        cancel()
        hops = []

        var host = rawHost
        for s in ["https://", "http://"] {
            if host.hasPrefix(s) { host = String(host.dropFirst(s.count)) }
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        if let colon = host.lastIndex(of: ":"),
           host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        guard !host.isEmpty else { return }

        let proc = Process()
        // Run under `script` so traceroute gets a pseudo-terminal — otherwise
        // its stdout is fully buffered when piped and hops arrive all at once.
        // -I: ICMP probes (like ping) so the destination replies and the trace
        //     terminates at the real host instead of running to -m with UDP.
        // -w 1: wait only 1s per hop, -q 1: one probe, -m 20: cap, -n: no DNS.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        proc.arguments = ["-q", "/dev/null",
                          "/usr/sbin/traceroute", "-I", "-n", "-q", "1", "-w", "1", "-m", "20", host]

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
                if let hop = Self.parse(line) {
                    DispatchQueue.main.async { self?.hops.append(hop) }
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.isRunning = false }
        }

        do {
            try proc.run()
            isRunning = true
            process = proc
        } catch {
            isRunning = false
        }
    }

    func cancel() {
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        isRunning = false
    }

    static func parse(_ line: String) -> TracerouteHop? {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first, let num = Int(first) else { return nil }

        let rest = Array(parts.dropFirst())
        var host = "*"
        if let h = rest.first, h != "*" { host = h }

        var ms: Double?
        for (i, t) in rest.enumerated() where t == "ms" && i > 0 {
            ms = Double(rest[i - 1]); break
        }
        return TracerouteHop(number: num, host: host, ms: ms)
    }
}

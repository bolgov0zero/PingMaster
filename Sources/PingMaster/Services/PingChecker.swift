import Foundation

class PingChecker {
    /// Sends `count` ICMP packets and reports the minimum RTT (kernel-measured,
    /// identical to what the `ping` terminal command prints). Minimum is used
    /// because it represents the cleanest round-trip — least affected by
    /// transient queueing/scheduling jitter on either host.
    static func check(host: String, count: Int = 1, completion: @escaping (Double?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c N: packets, -W: per-packet timeout (ms), -t: overall deadline (s),
        // -q would suppress per-packet lines, so we keep verbose to parse each RTT.
        process.arguments = ["-c", "\(count)", "-W", "2000", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        process.terminationHandler = { proc in
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // Prefer the summary min if present, else min of per-packet samples.
            completion(Self.parseRTT(from: output))
        }

        do {
            try process.run()
        } catch {
            completion(nil)
        }
    }

    /// Extracts RTT from ping output. Prefers the statistics summary line
    /// (`round-trip min/avg/max/stddev = a/b/c/d ms`) min field; falls back to
    /// the minimum of all `time=NN.N ms` per-packet samples.
    private static func parseRTT(from output: String) -> Double? {
        // 1) Summary line — most authoritative, same numbers terminal prints.
        if let summaryMin = firstMatch(
            in: output,
            pattern: #"min/avg/max(?:/stddev)?\s*=\s*([\d.]+)/"#
        ) {
            return summaryMin
        }

        // 2) Fall back to minimum of individual packet times.
        let pattern = #"time[=<]([\d.]+)\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        let samples = regex.matches(in: output, range: range).compactMap { m -> Double? in
            guard let r = Range(m.range(at: 1), in: output) else { return nil }
            return Double(output[r])
        }
        return samples.min()
    }

    private static func firstMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}

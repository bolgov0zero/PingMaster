import Foundation

class PingChecker {
    static func check(host: String, completion: @escaping (Double?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "2000", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        process.terminationHandler = { proc in
            guard proc.terminationStatus == 0 else {
                completion(nil)
                return
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            completion(Self.parseRTT(from: output))
        }

        do {
            try process.run()
        } catch {
            completion(nil)
        }
    }

    // Parses "time=12.345 ms" or "time=12.345ms" from ping output
    private static func parseRTT(from output: String) -> Double? {
        let pattern = #"time[=<]([\d.]+)\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return Double(output[range])
    }
}

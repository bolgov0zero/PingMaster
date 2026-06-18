import Foundation

class PingChecker {
    static func check(host: String, completion: @escaping (Double?) -> Void) {
        let start = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "2000", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { proc in
            let latency = proc.terminationStatus == 0 ? Date().timeIntervalSince(start) * 1000 : nil
            completion(latency)
        }

        do {
            try process.run()
        } catch {
            completion(nil)
        }
    }
}

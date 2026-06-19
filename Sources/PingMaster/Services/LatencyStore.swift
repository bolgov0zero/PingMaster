import Foundation

enum ChartPeriod: String, CaseIterable, Identifiable {
    case online = "Сейчас"
    case day = "День"
    case month = "Месяц"
    case year = "Год"
    var id: String { rawValue }
}

// Persistent latency history on disk, kept indefinitely. Stores compact
// per-hour aggregates per host (one bucket per hour → tiny even over years).
final class LatencyStore {
    static let shared = LatencyStore()

    struct Agg: Codable {
        var count: Int
        var sum: Double
        var minV: Double
        var maxV: Double
    }

    // hostID -> [hourIndexString: Agg]
    private var data: [String: [String: Agg]] = [:]
    private let url: URL
    private let ioQueue = DispatchQueue(label: "LatencyStore.io")

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PingMaster", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("latency.json")
        load()
    }

    private static func hourIndex(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 3600) }

    func record(hostID: UUID, ms: Double, at date: Date = Date()) {
        let hid = hostID.uuidString
        let key = String(Self.hourIndex(date))
        var host = data[hid] ?? [:]
        if var agg = host[key] {
            agg.count += 1
            agg.sum += ms
            agg.minV = Swift.min(agg.minV, ms)
            agg.maxV = Swift.max(agg.maxV, ms)
            host[key] = agg
        } else {
            host[key] = Agg(count: 1, sum: ms, minV: ms, maxV: ms)
        }
        data[hid] = host
        save()
    }

    /// Fixed-axis slots for the chart: hours 0–23 of today, days of the current
    /// month, or months of the current year. Empty slots are nil (gaps).
    func slottedSeries(hostID: UUID, period: ChartPeriod) -> [LatencyPoint?] {
        let host = data[hostID.uuidString] ?? [:]
        let cal = Calendar.current
        let now = Date()

        func build(count: Int, slotIndex: (Date) -> Int?, slotDate: (Int) -> Date) -> [LatencyPoint?] {
            var acc = [(sum: Double, count: Int)](repeating: (0, 0), count: count)
            for (k, agg) in host {
                guard let idx = Int(k) else { continue }
                let date = Date(timeIntervalSince1970: Double(idx) * 3600)
                guard let s = slotIndex(date), s >= 0, s < count else { continue }
                acc[s].sum += agg.sum
                acc[s].count += agg.count
            }
            return (0..<count).map { i in
                acc[i].count > 0 ? LatencyPoint(timestamp: slotDate(i), value: acc[i].sum / Double(acc[i].count)) : nil
            }
        }

        switch period {
        case .online:
            return []
        case .day:
            let start = cal.startOfDay(for: now)
            return build(count: 24, slotIndex: { date in
                let d = date.timeIntervalSince(start)
                return d >= 0 && d < 24 * 3600 ? Int(d / 3600) : nil
            }, slotDate: { start.addingTimeInterval(Double($0) * 3600) })
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
            return build(count: days, slotIndex: { date in
                guard cal.isDate(date, equalTo: now, toGranularity: .month) else { return nil }
                return cal.component(.day, from: date) - 1
            }, slotDate: { cal.date(byAdding: .day, value: $0, to: start) ?? start })
        case .year:
            let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return build(count: 12, slotIndex: { date in
                guard cal.isDate(date, equalTo: now, toGranularity: .year) else { return nil }
                return cal.component(.month, from: date) - 1
            }, slotDate: { cal.date(byAdding: .month, value: $0, to: start) ?? start })
        }
    }

    func clear(hostID: UUID) {
        data.removeValue(forKey: hostID.uuidString)
        save()
    }

    func clearAll() {
        data.removeAll()
        save()
    }

    private func save() {
        let snapshot = data
        ioQueue.async { [url] in
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: url)
            }
        }
    }

    private func load() {
        guard let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: Agg]].self, from: raw) else { return }
        data = decoded
    }
}

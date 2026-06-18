import Foundation

// Persistent hourly availability aggregation, used by the heatmap.
// For each host we keep per-hour buckets (up count / total count) and prune
// to the retention window. Stored in UserDefaults as JSON.
final class UptimeStore {
    static let shared = UptimeStore()

    struct Bucket: Codable {
        var up: Int
        var total: Int
    }

    private let key = "uptimeBuckets"
    private let retentionDays = 14
    // hostID -> [hourEpochString: Bucket]
    private var buckets: [String: [String: Bucket]] = [:]

    private init() { load() }

    // Epoch hour index (hours since 1970), stable across launches.
    private static func hourIndex(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 3600)
    }

    func record(hostID: UUID, up: Bool, at date: Date = Date()) {
        let hid = hostID.uuidString
        let hour = String(Self.hourIndex(date))
        var host = buckets[hid] ?? [:]
        var b = host[hour] ?? Bucket(up: 0, total: 0)
        b.total += 1
        if up { b.up += 1 }
        host[hour] = b
        buckets[hid] = host
        prune()
        save()
    }

    /// Heatmap grid: `days` rows (row 0 = oldest day, last = today),
    /// 24 columns (local hour 0…23). Cell = uptime fraction 0…1, or nil if
    /// no data for that hour.
    func grid(hostID: UUID, days: Int) -> [[Double?]] {
        let hid = hostID.uuidString
        let host = buckets[hid] ?? [:]
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())

        var rows: [[Double?]] = []
        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: startOfToday) else {
                rows.append(Array(repeating: nil, count: 24)); continue
            }
            var row: [Double?] = []
            for hour in 0..<24 {
                guard let cellDate = cal.date(byAdding: .hour, value: hour, to: dayStart) else {
                    row.append(nil); continue
                }
                let h = String(Self.hourIndex(cellDate))
                if let b = host[h], b.total > 0 {
                    row.append(Double(b.up) / Double(b.total))
                } else {
                    row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }

    func clear(hostID: UUID) {
        buckets.removeValue(forKey: hostID.uuidString)
        save()
    }

    private func prune() {
        let cutoff = Self.hourIndex(Date()) - retentionDays * 24
        for hid in buckets.keys {
            buckets[hid] = buckets[hid]?.filter { (Int($0.key) ?? 0) >= cutoff }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(buckets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: Bucket]].self, from: data) else { return }
        buckets = decoded
    }
}

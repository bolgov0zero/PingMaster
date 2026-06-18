import SwiftUI

struct SettingsView: View {
    @ObservedObject var service = MonitoringService.shared
    @State private var showAddSheet = false
    @State private var editingHost: Host? = nil

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(service.hosts) { host in
                    HostRow(host: host)
                        .onTapGesture(count: 2) { editingHost = host }
                }
                .onDelete(perform: service.remove)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Добавить хост", systemImage: "plus")
                }
                Spacer()
                Text("Двойной клик — редактировать")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
        }
        .frame(minWidth: 550, minHeight: 380)
        .sheet(isPresented: $showAddSheet) {
            HostEditView(host: nil)
        }
        .sheet(item: $editingHost) { host in
            HostEditView(host: host)
        }
    }
}

struct HostRow: View {
    @ObservedObject var host: Host

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(host.isAvailable ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).font(.headline)
                Text(host.address).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text(host.method.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("каждые \(formatInterval(host.interval))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            Group {
                if let latency = host.lastLatency {
                    Text(String(format: "%.0f ms", latency))
                } else {
                    Text("—")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
            .frame(width: 55, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) с" }
        let m = Int(seconds / 60)
        let s = Int(seconds) % 60
        return s == 0 ? "\(m) мин" : "\(m)м \(s)с"
    }
}

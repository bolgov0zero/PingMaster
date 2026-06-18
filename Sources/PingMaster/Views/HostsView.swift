import SwiftUI

struct HostsView: View {
    @ObservedObject var service = MonitoringService.shared
    @State private var showAddSheet = false
    @State private var editingHost: Host? = nil

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(service.hosts) { host in
                    HostRow(host: host, onEdit: { editingHost = host }, onDelete: {
                        if let idx = service.hosts.firstIndex(where: { $0.id == host.id }) {
                            service.remove(at: IndexSet(integer: idx))
                        }
                    })
                }
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
            }
            .padding(10)
        }
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
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

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

            if isHovered {
                Button(action: onEdit) {
                    Label("Изменить", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Редактировать")

                Button(action: onDelete) {
                    Label("Удалить", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .help("Удалить")
            } else {
                Text(host.method.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Group {
                    if let latency = host.lastLatency {
                        Text(String(format: "%.0f ms", latency))
                    } else {
                        Text("–")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

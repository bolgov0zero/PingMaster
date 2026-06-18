import SwiftUI

struct HostsView: View {
    @ObservedObject var service = MonitoringService.shared
    @State private var showAddSheet = false
    @State private var editingHost: Host? = nil
    @State private var draggingHost: Host? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            HStack {
                Text("Хосты").font(.title2).bold()
                if !service.hosts.isEmpty {
                    Text("\(service.hosts.count)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            if service.hosts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(service.hosts) { host in
                            HostRow(host: host)
                                .opacity(draggingHost?.id == host.id ? 0.4 : 1)
                                .onTapGesture(count: 2) { editingHost = host }
                                .onDrag {
                                    draggingHost = host
                                    return NSItemProvider(object: host.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: HostDropDelegate(
                                    item: host,
                                    dragging: $draggingHost,
                                    service: service
                                ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                HStack {
                    Image(systemName: "hand.tap")
                    Text("Двойной клик — изменить · перетащите для сортировки")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            HostEditView(host: nil)
        }
        .sheet(item: $editingHost) { host in
            HostEditView(host: host)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Нет хостов").font(.headline)
            Text("Нажмите «Добавить хост», чтобы начать мониторинг")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HostDropDelegate: DropDelegate {
    let item: Host
    @Binding var dragging: Host?
    let service: MonitoringService

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id,
              let from = service.hosts.firstIndex(where: { $0.id == dragging.id }),
              let to = service.hosts.firstIndex(where: { $0.id == item.id }) else { return }
        if service.hosts[to].id != dragging.id {
            withAnimation {
                service.move(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct HostRow: View {
    @ObservedObject var host: Host
    @ObservedObject var service = MonitoringService.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(service.status(for: host).color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).font(.headline)
                Text(host.address).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if !host.showInMenu {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Скрыт из меню панели")
            }

            if host.method == .https, let days = host.sslDaysLeft {
                Label("\(days)д", systemImage: days <= 14 ? "exclamationmark.shield" : "lock.shield")
                    .font(.caption2)
                    .foregroundColor(days <= 14 ? .orange : .secondary)
                    .help("SSL-сертификат: \(days) дн. до истечения")
            }

            Text(host.method.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

            // Uptime % over last 24h (or since launch)
            VStack(spacing: 1) {
                Text(uptimeText)
                    .font(.callout.monospacedDigit())
                Text("аптайм")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.secondary)
            .frame(width: 48, alignment: .trailing)

            Group {
                if let latency = host.lastLatency {
                    Text(String(format: "%.0f мс", latency))
                } else {
                    Text("–")
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundColor(.secondary)
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(isHovered ? 0.12 : 0), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    private var uptimeText: String {
        if let pct = service.uptimePercent(for: host) {
            return String(format: "%.0f%%", pct)
        }
        return "–"
    }
}

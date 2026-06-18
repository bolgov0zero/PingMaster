import SwiftUI

struct LogView: View {
    @ObservedObject var service = MonitoringService.shared
    @ObservedObject var log = EventLog.shared

    @State private var filter: UUID? = nil  // nil = все

    private var filtered: [StatusEvent] {
        log.events
            .filter { filter == nil || $0.hostID == filter }
            .reversed()  // newest first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Лог").font(.title2).bold()
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            chips
                .padding(.horizontal, 16).padding(.bottom, 10)

            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, ev in
                            row(ev, even: idx % 2 == 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Все", id: nil)
                ForEach(service.hosts) { host in
                    chip(title: host.name, id: host.id)
                }
            }
        }
    }

    private func chip(title: String, id: UUID?) -> some View {
        let selected = filter == id
        return Button {
            filter = id
        } label: {
            Text(title)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ ev: StatusEvent, even: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(ev.up ? Color.green : Color.red).frame(width: 9, height: 9)
            Text(ev.hostName).font(.callout.weight(.medium)).lineLimit(1)
            Text(ev.up ? "Доступен" : "Недоступен")
                .font(.caption)
                .foregroundColor(ev.up ? .green : .red)
            Spacer()
            Text(ev.date, format: .dateTime.day().month().hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(even ? Color.primary.opacity(0.03) : Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle").font(.largeTitle).foregroundColor(.secondary)
            Text("Нет событий").font(.headline)
            Text("Здесь появятся изменения доступности хостов")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

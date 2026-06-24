import SwiftUI

struct HostsView: View {
    @ObservedObject var service = MonitoringService.shared
    @State private var showAddSheet = false
    @State private var editingHost: Host? = nil
    @State private var draggingHost: Host? = nil
    @State private var draggingSection: HostSection? = nil

    @State private var showAddSection = false
    @State private var newSectionName = ""
    @State private var renamingSection: HostSection? = nil
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if service.hosts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if service.sections.isEmpty {
                            hostRows(in: nil)
                        } else {
                            ForEach(service.sections) { section in
                                sectionGroup(section: section)
                            }
                            if !service.hosts(in: nil).isEmpty {
                                uncategorizedGroup()
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
                hint
            }
        }
        .sheet(isPresented: $showAddSheet) { HostEditView(host: nil) }
        .sheet(item: $editingHost) { HostEditView(host: $0) }
        .alert("Новый раздел", isPresented: $showAddSection) {
            TextField("Название", text: $newSectionName)
            Button("Добавить") {
                let n = newSectionName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { service.addSection(name: n) }
                newSectionName = ""
            }
            Button("Отмена", role: .cancel) { newSectionName = "" }
        }
        .alert("Переименовать раздел", isPresented: Binding(
            get: { renamingSection != nil },
            set: { if !$0 { renamingSection = nil } }
        )) {
            TextField("Название", text: $renameText)
            Button("Сохранить") {
                if let s = renamingSection {
                    let n = renameText.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { service.renameSection(s.id, to: n) }
                }
                renamingSection = nil
            }
            Button("Отмена", role: .cancel) { renamingSection = nil }
        }
    }

    private var header: some View {
        HStack {
            Text("Хосты").font(.title2).bold()
            if !service.hosts.isEmpty {
                Text("\(service.hosts.count)")
                    .font(.caption.bold()).foregroundColor(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
            Button { showAddSection = true } label: {
                Label("Раздел", systemImage: "folder.badge.plus")
            }
            Button { showAddSheet = true } label: {
                Label("Добавить", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var hint: some View {
        HStack {
            Image(systemName: "hand.tap")
            Text("Двойной клик — изменить · перетаскивайте хосты между разделами")
            Spacer()
        }
        .font(.caption).foregroundColor(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Section group

    @ViewBuilder
    private func sectionGroup(section: HostSection) -> some View {
        let collapsed = service.isCollapsed(section.id, .tab)
        sectionHeader(id: section.id, name: section.name, collapsed: collapsed)
            .opacity(draggingSection?.id == section.id ? 0.4 : 1)
            .onDrag {
                draggingSection = section
                draggingHost = nil
                return NSItemProvider(object: section.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: SectionDropDelegate(
                sectionID: section.id, draggingHost: $draggingHost,
                draggingSection: $draggingSection, service: service))
        if !collapsed {
            hostRows(in: section.id)
        }
    }

    @ViewBuilder
    private func uncategorizedGroup() -> some View {
        let collapsed = service.isCollapsed(nil, .tab)
        sectionHeader(id: nil, name: "Без раздела", collapsed: collapsed)
            .onDrop(of: [.text], delegate: SectionDropDelegate(
                sectionID: nil, draggingHost: $draggingHost,
                draggingSection: $draggingSection, service: service))
        if !collapsed {
            hostRows(in: nil)
        }
    }

    @ViewBuilder
    private func sectionHeader(id: UUID?, name: String, collapsed: Bool) -> some View {
        let count = service.hosts(in: id).count
        HStack(spacing: 8) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.caption2.bold()).foregroundColor(.secondary).frame(width: 12)
            Circle().fill((service.sectionStatus(id)?.color) ?? Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
            Text(name).font(.subheadline.weight(.semibold))
            Text("\(count)").font(.caption2).foregroundColor(.secondary)
            Spacer()
            if id != nil {
                Button { renamingSection = service.sections.first { $0.id == id }; renameText = name } label: {
                    Image(systemName: "pencil")
                }.buttonStyle(.plain).foregroundColor(.secondary)
                Button { service.removeSection(id!) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { service.toggleCollapse(id, .tab) } }
    }

    @ViewBuilder
    private func hostRows(in sectionID: UUID?) -> some View {
        ForEach(service.hosts(in: sectionID)) { host in
            HostRow(host: host)
                .opacity(draggingHost?.id == host.id ? 0.4 : 1)
                .onDrag {
                    draggingHost = host
                    draggingSection = nil
                    return NSItemProvider(object: host.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: HostRowDropDelegate(item: host, dragging: $draggingHost, service: service))
                // simultaneousGesture so the double-click doesn't delay the drag.
                .simultaneousGesture(TapGesture(count: 2).onEnded { editingHost = host })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "server.rack").font(.largeTitle).foregroundColor(.secondary)
            Text("Нет хостов").font(.headline)
            Text("Нажмите «Добавить хост», чтобы начать мониторинг")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HostRowDropDelegate: DropDelegate {
    let item: Host
    @Binding var dragging: Host?
    let service: MonitoringService

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id else { return }
        withAnimation { service.moveHost(dragging, before: item) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

struct SectionDropDelegate: DropDelegate {
    let sectionID: UUID?
    @Binding var draggingHost: Host?
    @Binding var draggingSection: HostSection?
    let service: MonitoringService

    func dropEntered(info: DropInfo) {
        // Reorder sections (only over a real section, not «Без раздела»).
        if let sec = draggingSection, let target = sectionID, sec.id != target {
            withAnimation { service.moveSection(sec.id, before: target) }
            return
        }
        // Move a host into this section.
        if let host = draggingHost, host.sectionID != sectionID {
            withAnimation { service.moveHost(host, toSection: sectionID) }
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        draggingHost = nil; draggingSection = nil; return true
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
                    .font(.caption).foregroundColor(.secondary)
                    .help("Скрыт из меню панели")
            }

            if host.method == .https, let days = host.sslDaysLeft {
                Label("\(days)д", systemImage: days <= 14 ? "exclamationmark.shield" : "lock.shield")
                    .font(.caption2)
                    .foregroundColor(days <= 14 ? .orange : .secondary)
                    .help("SSL-сертификат: \(days) дн. до истечения")
            }

            Text(host.method.rawValue)
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

            VStack(spacing: 1) {
                Text(uptimeText).font(.callout.monospacedDigit())
                Text("аптайм").font(.system(size: 9)).foregroundColor(.secondary)
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
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isHovered ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(isHovered ? 0.12 : 0), lineWidth: 1))
        .onHover { isHovered = $0 }
    }

    private var uptimeText: String {
        if let pct = service.uptimePercent(for: host) {
            return String(format: "%.0f%%", pct)
        }
        return "–"
    }
}

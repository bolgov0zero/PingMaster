import SwiftUI

struct HostEditView: View {
    @Environment(\.dismiss) var dismiss
    var host: Host?

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var method: PollMethod = .ping
    @State private var failThreshold: Int = 3
    @State private var showInMenu: Bool = true
    @State private var showDeleteConfirm = false

    var isEditing: Bool { host != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 1) {
                Text(isEditing ? "Редактирование хоста" : "Новый хост")
                    .font(.headline)
                Text(isValid ? (name.isEmpty ? address : name) : "Заполните имя и адрес")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // Basics
                    VStack(spacing: 0) {
                        fieldRow(label: "Имя") {
                            TextField("Google DNS", text: $name)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                        }
                        rowDivider
                        fieldRow(label: "Адрес") {
                            TextField("8.8.8.8 или example.com", text: $address)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospaced())
                        }
                    }
                    .cardBackground()

                    // Method
                    VStack(spacing: 8) {
                        HStack {
                            Text("Метод проверки")
                            Spacer()
                        }
                        Picker("", selection: $method) {
                            ForEach(PollMethod.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(14)
                    .cardBackground()

                    // Behaviour
                    VStack(spacing: 0) {
                        fieldRow(label: "Порог недоступности",
                                 sublabel: "Неудач подряд до статуса «недоступен»") {
                            Stepper("\(failThreshold)", value: $failThreshold, in: 1...10)
                                .labelsHidden()
                                .fixedSize()
                            Text("\(failThreshold)")
                                .monospacedDigit().frame(width: 18)
                        }
                        rowDivider
                        fieldRow(label: "Показывать в меню",
                                 sublabel: "Виден в списке меню-бара") {
                            Toggle("", isOn: $showInMenu).labelsHidden()
                        }
                    }
                    .cardBackground()
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                if isEditing {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Добавить") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(16)
        }
        .frame(width: 460, height: 500)
        .onAppear { loadHost() }
        .confirmationDialog(
            "Удалить хост «\(name)»?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                deleteHost()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 14)
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        label: String,
        sublabel: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if let sublabel {
                    Text(sublabel).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func deleteHost() {
        guard let h = host else { return }
        let service = MonitoringService.shared
        if let idx = service.hosts.firstIndex(where: { $0.id == h.id }) {
            service.remove(at: IndexSet(integer: idx))
        }
    }

    private func loadHost() {
        guard let h = host else { return }
        name = h.name
        address = h.address
        method = h.method
        failThreshold = h.failThreshold
        showInMenu = h.showInMenu
    }

    private func save() {
        let service = MonitoringService.shared
        if let h = host {
            h.name = name.trimmingCharacters(in: .whitespaces)
            h.address = address.trimmingCharacters(in: .whitespaces)
            h.method = method
            h.failThreshold = failThreshold
            h.showInMenu = showInMenu
            service.update(h)
        } else {
            service.add(Host(
                name: name.trimmingCharacters(in: .whitespaces),
                address: address.trimmingCharacters(in: .whitespaces),
                method: method,
                failThreshold: failThreshold,
                showInMenu: showInMenu
            ))
        }
    }
}

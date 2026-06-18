import SwiftUI

struct HostEditView: View {
    @Environment(\.dismiss) var dismiss
    var host: Host?

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var method: PollMethod = .ping
    @State private var interval: Double = 30
    @State private var failThreshold: Int = 3

    var isEditing: Bool { host != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Редактировать хост" : "Добавить хост")
                .font(.title2).bold()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Имя").gridColumnAlignment(.trailing)
                    TextField("Например: Google DNS", text: $name)
                }
                GridRow {
                    Text("Адрес").gridColumnAlignment(.trailing)
                    TextField("8.8.8.8 или example.com", text: $address)
                }
                GridRow {
                    Text("Метод").gridColumnAlignment(.trailing)
                    Picker("", selection: $method) {
                        ForEach(PollMethod.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Интервал").gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $interval, in: 5...300, step: 5)
                        Text(formatInterval(interval))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                GridRow {
                    Text("Порог").gridColumnAlignment(.trailing)
                    HStack {
                        Stepper("\(failThreshold) неудачных подряд", value: $failThreshold, in: 1...10)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Добавить") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440, height: 320)
        .onAppear { loadHost() }
    }

    private func loadHost() {
        guard let h = host else { return }
        name = h.name
        address = h.address
        method = h.method
        interval = h.interval
        failThreshold = h.failThreshold
    }

    private func save() {
        let service = MonitoringService.shared
        if let h = host {
            h.name = name.trimmingCharacters(in: .whitespaces)
            h.address = address.trimmingCharacters(in: .whitespaces)
            h.method = method
            h.interval = interval
            h.failThreshold = failThreshold
            service.update(h)
        } else {
            service.add(Host(
                name: name.trimmingCharacters(in: .whitespaces),
                address: address.trimmingCharacters(in: .whitespaces),
                method: method,
                interval: interval,
                failThreshold: failThreshold
            ))
        }
    }

    private func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) секунд" }
        let m = Int(seconds / 60)
        let s = Int(seconds) % 60
        return s == 0 ? "\(m) минут" : "\(m) мин \(s) сек"
    }
}

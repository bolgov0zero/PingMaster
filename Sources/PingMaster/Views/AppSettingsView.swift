import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @ObservedObject var settings = GlobalSettings.shared
    @State private var launchAtLogin: Bool = false
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionCard(title: "Система") {
                    Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
                }

                SectionCard(title: "Уведомления") {
                    Toggle("Уведомлять о падении и восстановлении", isOn: $settings.notificationsEnabled)
                }

                SectionCard(title: "Иконка в меню-баре") {
                    Toggle("Показывать количество хостов", isOn: $settings.showCountInIcon)
                    Text("Рядом с иконкой будет «5/0» — доступные и недоступные.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                SectionCard(title: "Опрос") {
                    HStack {
                        Text("Интервал опроса")
                        Spacer()
                        IntervalInputRow(value: $settings.interval)
                    }
                    Divider()
                    Text("Применяется ко всем хостам. Минимум — 5 секунд.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                SectionCard(title: "Хосты") {
                    HStack {
                        Button {
                            exportHosts()
                        } label: {
                            Label("Экспорт…", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            importHosts()
                        } label: {
                            Label("Импорт…", systemImage: "square.and.arrow.down")
                        }
                        Spacer()
                    }
                    Text("Сохранение и загрузка списка хостов в формате JSON. Импорт добавляет хосты к текущим.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                SectionCard(title: "Данные") {
                    HStack {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Очистить данные", systemImage: "trash")
                        }
                        .foregroundColor(.red)
                        Spacer()
                    }
                    Text("Удаляет всю историю задержек и тепловую карту по всем хостам. Сами хосты сохраняются.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                SectionCard(title: "Пороги задержки") {
                    ThresholdInputRow(color: .green,  label: "Зелёный — до", value: $settings.greenThreshold)
                    Divider()
                    ThresholdInputRow(color: .orange, label: "Оранжевый — до", value: $settings.orangeThreshold)
                    Divider()
                    HStack {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                        Text("Красный — от \(Int(settings.orangeThreshold)) мс и выше")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(16)
        }
        .onAppear { launchAtLogin = getLaunchAtLoginStatus() }
        .confirmationDialog("Очистить все данные по хостам?",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) {
                MonitoringService.shared.clearAllData()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История задержек и тепловая карта будут удалены. Хосты останутся.")
        }
    }

    private func exportHosts() {
        guard let data = MonitoringService.shared.exportHostsData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "pingmaster-hosts.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importHosts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            MonitoringService.shared.importHosts(from: data)
        }
    }

    private func getLaunchAtLoginStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = getLaunchAtLoginStatus()
        }
    }
}

// Interval input: accepts seconds or "Xm Ys" notation, shows formatted value
struct IntervalInputRow: View {
    @Binding var value: Double
    @State private var text: String = ""
    @State private var editing = false

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .onAppear { text = "\(Int(value))" }
                .onSubmit { commit(); editing = false }
                .onChange(of: text) { _ in editing = true }
            Text("сек").foregroundColor(.secondary)
            if !editing {
                Text("(\(formatted))")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    private var formatted: String {
        if value < 60 { return "\(Int(value)) сек" }
        let m = Int(value / 60); let s = Int(value) % 60
        return s == 0 ? "\(m) мин" : "\(m)м \(s)с"
    }

    private func commit() {
        // Minimum 5s: leaves room for the 3-packet ICMP burst.
        if let v = Double(text.trimmingCharacters(in: .whitespaces)), v >= 5 {
            value = v
        } else {
            text = "\(Int(value))"
        }
    }
}

struct ThresholdInputRow: View {
    let color: Color
    let label: String
    @Binding var value: Double
    @State private var text: String = ""

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
            Spacer()
            TextField("", text: $text)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onAppear { text = "\(Int(value))" }
                .onSubmit { commit() }
            Text("мс").foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func commit() {
        if let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 {
            value = v
        } else {
            text = "\(Int(value))"
        }
    }
}

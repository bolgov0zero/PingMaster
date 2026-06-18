import SwiftUI
import ServiceManagement

struct AppSettingsView: View {
    @ObservedObject var settings = GlobalSettings.shared
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
            }

            Section("Опрос") {
                HStack {
                    Text("Интервал опроса")
                    Spacer()
                    IntervalInputRow(value: $settings.interval)
                }
                Text("Применяется ко всем хостам.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Пороги задержки") {
                ThresholdInputRow(color: .green,  label: "Зелёный — до", value: $settings.greenThreshold)
                ThresholdInputRow(color: .orange, label: "Оранжевый — до", value: $settings.orangeThreshold)
                HStack {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text("Красный — от \(Int(settings.orangeThreshold)) мс и выше")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { launchAtLogin = getLaunchAtLoginStatus() }
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
        if let v = Double(text.trimmingCharacters(in: .whitespaces)), v >= 1 {
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

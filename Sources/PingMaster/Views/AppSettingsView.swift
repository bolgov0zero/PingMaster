import SwiftUI
import ServiceManagement

struct AppSettingsView: View {
    @ObservedObject var settings = GlobalSettings.shared
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("Опрос") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Интервал опроса")
                        Spacer()
                        Text(formatInterval(settings.interval))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.interval, in: 5...300, step: 5)
                    Text("Применяется ко всем хостам.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Пороги задержки") {
                VStack(alignment: .leading, spacing: 12) {
                    ThresholdRow(
                        color: .green,
                        label: "Зелёный — до",
                        value: $settings.greenThreshold,
                        range: 1...Double(settings.orangeThreshold - 1)
                    )
                    ThresholdRow(
                        color: .orange,
                        label: "Оранжевый — до",
                        value: $settings.orangeThreshold,
                        range: Double(settings.greenThreshold + 1)...999
                    )
                    HStack {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                        Text("Красный — от \(Int(settings.orangeThreshold)) мс и выше")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        setLaunchAtLogin(enabled)
                    }
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

    private func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) сек" }
        let m = Int(seconds / 60)
        let s = Int(seconds) % 60
        return s == 0 ? "\(m) мин" : "\(m) мин \(s) сек"
    }
}

struct ThresholdRow: View {
    let color: Color
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label)
                Spacer()
                Text("\(Int(value)) мс")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            Slider(value: $value, in: range, step: 5)
        }
        .font(.caption)
    }
}

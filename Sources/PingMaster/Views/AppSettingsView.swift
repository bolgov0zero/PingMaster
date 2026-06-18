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
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
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

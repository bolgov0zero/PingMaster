import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var settings = GlobalSettings.shared

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
                    Text("Применяется ко всем хостам. Изменение перезапускает таймеры.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) сек" }
        let m = Int(seconds / 60)
        let s = Int(seconds) % 60
        return s == 0 ? "\(m) мин" : "\(m) мин \(s) сек"
    }
}

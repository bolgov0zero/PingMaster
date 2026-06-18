import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Главная", systemImage: "chart.line.uptrend.xyaxis") }

            HostsView()
                .tabItem { Label("Хосты", systemImage: "server.rack") }

            LogView()
                .tabItem { Label("Лог", systemImage: "list.bullet.rectangle") }

            AppSettingsView()
                .tabItem { Label("Настройки", systemImage: "gear") }
        }
        .frame(minWidth: 700, minHeight: 760)
    }
}

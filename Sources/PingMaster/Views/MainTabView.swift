import SwiftUI

// Lets other parts of the app switch the active tab (e.g. menu host click).
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab: Int = 0  // 0 = Главная
    private init() {}
}

struct MainTabView: View {
    @ObservedObject var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            DashboardView()
                .tabItem { Label("Главная", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(0)

            HostsView()
                .tabItem { Label("Хосты", systemImage: "server.rack") }
                .tag(1)

            LogView()
                .tabItem { Label("Лог", systemImage: "list.bullet.rectangle") }
                .tag(2)

            AppSettingsView()
                .tabItem { Label("Настройки", systemImage: "gear") }
                .tag(3)
        }
        .frame(minWidth: 700, minHeight: 760)
    }
}

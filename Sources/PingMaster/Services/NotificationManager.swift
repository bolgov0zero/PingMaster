import Foundation
import AppKit

// Uses the legacy NSUserNotification API: unlike UNUserNotificationCenter it
// works for ad-hoc / unsigned apps (no Developer ID), which is how this app is
// distributed. Still requires running inside a proper .app bundle.
class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        // No explicit authorization needed for NSUserNotification.
    }

    func notifyDown(host: Host) {
        send(title: "Хост недоступен",
             body: "«\(host.name)» (\(host.address)) не отвечает")
    }

    func notifyUp(host: Host) {
        send(title: "Хост восстановлен",
             body: "«\(host.name)» (\(host.address)) снова доступен")
    }

    func notifySSL(host: Host, days: Int) {
        let when = days == 0 ? "сегодня" : "через \(days) дн."
        send(title: "SSL-сертификат истекает",
             body: "«\(host.name)»: сертификат истекает \(when)")
    }

    private func send(title: String, body: String) {
        guard isBundled, GlobalSettings.shared.notificationsEnabled else { return }
        let n = NSUserNotification()
        n.title = title
        n.informativeText = body
        n.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(n)
    }
}

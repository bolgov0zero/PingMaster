import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private var authorized = false

    private init() {}

    // UNUserNotificationCenter asserts when the process has no app bundle
    // (e.g. running the bare executable from Xcode DerivedData). Only use it
    // when launched as a proper .app with a bundle identifier.
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func notifyDown(host: Host) {
        send(title: "Хост недоступен",
             body: "«\(host.name)» (\(host.address)) не отвечает",
             id: "down-\(host.id.uuidString)")
    }

    func notifyUp(host: Host) {
        send(title: "Хост восстановлен",
             body: "«\(host.name)» (\(host.address)) снова доступен",
             id: "up-\(host.id.uuidString)")
    }

    func notifySSL(host: Host, days: Int) {
        let when = days == 0 ? "сегодня" : "через \(days) дн."
        send(title: "SSL-сертификат истекает",
             body: "«\(host.name)»: сертификат истекает \(when)",
             id: "ssl-\(host.id.uuidString)")
    }

    private func send(title: String, body: String, id: String) {
        guard isBundled, GlobalSettings.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id + "-\(Date().timeIntervalSince1970)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

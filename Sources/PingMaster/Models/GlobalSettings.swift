import Foundation
import Combine

class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()

    @Published var interval: Double {
        didSet { UserDefaults.standard.set(interval, forKey: "pollInterval") }
    }

    // Thresholds: < green = green, < orange = orange, else = red
    @Published var greenThreshold: Double {
        didSet { UserDefaults.standard.set(greenThreshold, forKey: "greenThreshold") }
    }
    @Published var orangeThreshold: Double {
        didSet { UserDefaults.standard.set(orangeThreshold, forKey: "orangeThreshold") }
    }

    // Send a notification when a host goes down / comes back up.
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    // Show available/unavailable host counts next to the menu bar icon.
    @Published var showCountInIcon: Bool {
        didSet {
            UserDefaults.standard.set(showCountInIcon, forKey: "showCountInIcon")
            NotificationCenter.default.post(name: .hostStatusChanged, object: nil)
        }
    }

    private init() {
        let savedInterval = UserDefaults.standard.double(forKey: "pollInterval")
        interval = savedInterval >= 5 ? savedInterval : 30  // enforce 5s minimum

        let savedGreen = UserDefaults.standard.double(forKey: "greenThreshold")
        greenThreshold = savedGreen > 0 ? savedGreen : 50

        let savedOrange = UserDefaults.standard.double(forKey: "orangeThreshold")
        orangeThreshold = savedOrange > 0 ? savedOrange : 150

        // Default ON for notifications, OFF for the icon counter.
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        showCountInIcon = UserDefaults.standard.object(forKey: "showCountInIcon") as? Bool ?? false
    }
}

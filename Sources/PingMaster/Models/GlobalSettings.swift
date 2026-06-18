import Foundation
import Combine

class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()

    @Published var interval: Double {
        didSet { UserDefaults.standard.set(interval, forKey: "pollInterval") }
    }

    private init() {
        let saved = UserDefaults.standard.double(forKey: "pollInterval")
        interval = saved > 0 ? saved : 30
    }
}

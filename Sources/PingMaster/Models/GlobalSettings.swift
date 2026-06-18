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

    private init() {
        let savedInterval = UserDefaults.standard.double(forKey: "pollInterval")
        interval = savedInterval > 0 ? savedInterval : 30

        let savedGreen = UserDefaults.standard.double(forKey: "greenThreshold")
        greenThreshold = savedGreen > 0 ? savedGreen : 50

        let savedOrange = UserDefaults.standard.double(forKey: "orangeThreshold")
        orangeThreshold = savedOrange > 0 ? savedOrange : 150
    }
}

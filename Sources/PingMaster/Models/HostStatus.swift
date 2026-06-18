import SwiftUI
import AppKit

enum HostStatus {
    case green   // available, latency in green zone
    case yellow  // available, 3 consecutive measurements in orange-or-worse zone
    case red     // unavailable, or 3 consecutive measurements in red zone

    var color: Color {
        switch self {
        case .green:  return .green
        case .yellow: return .yellow
        case .red:    return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .green:  return .systemGreen
        case .yellow: return .systemYellow
        case .red:    return .systemRed
        }
    }
}

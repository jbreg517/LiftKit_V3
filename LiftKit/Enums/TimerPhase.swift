import SwiftUI

enum TimerPhase: String, Codable {
    case idle
    case work
    case rest
    case complete

    var label: String {
        switch self {
        case .idle:     return "Ready"
        case .work:     return "WORK"
        case .rest:     return "REST"
        case .complete: return "Done"
        }
    }

    var color: Color {
        switch self {
        case .idle:     return LKColor.textSecondary
        case .work:     return LKColor.work
        case .rest:     return LKColor.rest
        case .complete: return LKColor.accent
        }
    }
}

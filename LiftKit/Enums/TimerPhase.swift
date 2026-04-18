import SwiftUI

enum TimerPhase {
    case idle
    case work
    case rest
    case complete

    var label: String {
        switch self {
        case .idle:     return "READY"
        case .work:     return "WORK"
        case .rest:     return "REST"
        case .complete: return "DONE"
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

import SwiftUI

enum TimerType: String, CaseIterable, Identifiable {
    case amrap     = "AMRAP"
    case emom      = "EMOM"
    case forTime   = "For Time"
    case intervals = "Intervals"
    case reps      = "Reps"
    case manual    = "Manual"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .amrap:     return "As many rounds as possible"
        case .emom:      return "Every minute on the minute"
        case .forTime:   return "Complete for time"
        case .intervals: return "Timed work & rest intervals"
        case .reps:      return "Track sets and reps"
        case .manual:    return "Free-form count-up timer"
        }
    }

    var sfSymbol: String {
        switch self {
        case .amrap:     return "arrow.clockwise.circle.fill"
        case .emom:      return "clock.fill"
        case .forTime:   return "stopwatch.fill"
        case .intervals: return "timer"
        case .reps:      return "dumbbell.fill"
        case .manual:    return "play.circle.fill"
        }
    }

    var isCountdown: Bool {
        switch self {
        case .amrap, .emom, .intervals: return true
        case .forTime, .manual, .reps:  return false
        }
    }

    var hasInitialCountdown: Bool {
        switch self {
        case .amrap, .emom, .intervals, .forTime: return true
        case .reps, .manual:                      return false
        }
    }
}

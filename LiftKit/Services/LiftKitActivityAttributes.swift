import ActivityKit
import Foundation

/// Shared Live Activity contract.
/// Add this file to BOTH the main app target AND the widget extension target
/// via Xcode's File Inspector > Target Membership.
struct LiftKitActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var workoutName: String
        var currentRound: Int
        var totalRounds: Int
        /// "Minute 3", "Work", "Rest", or the timer type name
        var phaseLabel: String
        /// Non-nil for count-down modes; used by Text(timerInterval:) for live rendering
        var phaseEndDate: Date?
    }
    /// Static at start — the timer type string
    var workoutType: String
}

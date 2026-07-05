import ActivityKit
import Foundation

/// Manages the single Live Activity that shows on the Lock Screen and Dynamic Island.
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<LiftKitActivityAttributes>?

    func start(
        workoutName: String,
        workoutType: String,
        currentRound: Int,
        totalRounds: Int,
        phaseLabel: String,
        phaseEndDate: Date?,
        reps: Int? = nil,
        weightText: String? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = LiftKitActivityAttributes(workoutType: workoutType)
        let state = LiftKitActivityAttributes.ContentState(
            workoutName: workoutName,
            currentRound: currentRound,
            totalRounds: totalRounds,
            phaseLabel: phaseLabel,
            phaseEndDate: phaseEndDate,
            reps: reps,
            weightText: weightText
        )
        let content = ActivityContent(state: state, staleDate: nil)
        activity = try? Activity.request(attributes: attrs, content: content, pushType: nil)
    }

    /// `workoutName` is updatable because EMOM cycles to a different exercise
    /// each minute — the Live Activity follows along.
    func update(
        workoutName: String? = nil,
        currentRound: Int,
        totalRounds: Int,
        phaseLabel: String,
        phaseEndDate: Date?,
        reps: Int? = nil,
        weightText: String? = nil
    ) {
        guard let activity else { return }
        let state = LiftKitActivityAttributes.ContentState(
            workoutName: workoutName ?? activity.content.state.workoutName,
            currentRound: currentRound,
            totalRounds: totalRounds,
            phaseLabel: phaseLabel,
            phaseEndDate: phaseEndDate,
            reps: reps,
            weightText: weightText
        )
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    func stop() {
        guard let activity else { return }
        let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
}

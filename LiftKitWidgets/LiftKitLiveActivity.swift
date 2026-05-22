import ActivityKit
import SwiftUI
import WidgetKit

// NOTE: Also add LiftKitActivityAttributes.swift (from LiftKit/Services/) to this
// target's membership in Xcode so the struct is available here.

struct LiftKitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiftKitActivityAttributes.self) { context in
            LKLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (user long-presses the island)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phaseLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(context.state.currentRound)/\(context.state.totalRounds)")
                            .font(.title2.bold())
                            .foregroundColor(.orange)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = context.state.phaseEndDate, end > .now {
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.system(.title, design: .monospaced, weight: .bold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.workoutName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                // Compact: round x/total on the left
                Text("\(context.state.currentRound)/\(context.state.totalRounds)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.orange)
            } compactTrailing: {
                // Compact: live countdown on the right
                if let end = context.state.phaseEndDate, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                } else {
                    Text(context.state.phaseLabel)
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundColor(.orange)
                }
            } minimal: {
                // Minimal (pill squeezed by another live activity)
                if let end = context.state.phaseEndDate, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                } else {
                    Text("\(context.state.currentRound)")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Lock Screen View

struct LKLockScreenView: View {
    let context: ActivityViewContext<LiftKitActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.workoutName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(context.state.phaseLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    if context.state.totalRounds > 1 {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(context.state.currentRound) of \(context.state.totalRounds)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if let end = context.state.phaseEndDate, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.10))
        .activitySystemActionForegroundColor(.white)
    }
}

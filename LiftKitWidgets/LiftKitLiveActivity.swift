import ActivityKit
import SwiftUI
import WidgetKit

// This target also compiles LiftKit/Services/LiftKitActivityAttributes.swift
// (shared with the app) so the ContentState layout stays in sync.

/// "10 reps · 135 lb" — nil when the state carries neither.
private func repsWeightLine(_ state: LiftKitActivityAttributes.ContentState) -> String? {
    var parts: [String] = []
    if let reps = state.reps { parts.append("\(reps) reps") }
    if let weight = state.weightText { parts.append(weight) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// The live clock: counts down to phaseEndDate when one is set, otherwise
/// counts up from phaseStartDate. Both are wall-clock dates, so the clock
/// keeps running even while the app is suspended in the background.
private struct LiveClock: View {
    let state: LiftKitActivityAttributes.ContentState

    var body: some View {
        if let end = state.phaseEndDate, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
        } else if let start = state.phaseStartDate {
            Text(timerInterval: start...start.addingTimeInterval(24 * 3600), countsDown: false)
                .monospacedDigit()
        }
    }

    static func hasClock(_ state: LiftKitActivityAttributes.ContentState) -> Bool {
        if let end = state.phaseEndDate, end > .now { return true }
        return state.phaseStartDate != nil
    }
}

/// The gold from the app icon's barbell.
private let lkGold = Color(red: 0.93, green: 0.78, blue: 0.35)

/// LiftKit's logo mark for the Dynamic Island. The full app icon is a dark
/// tile that disappears against the black island, so this renders the icon's
/// barbell in its gold instead — crisp at any size.
private struct IslandLogo: View {
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: "dumbbell.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(lkGold)
    }
}

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
                    LiveClock(state: context.state)
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Text(context.state.workoutName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if let detail = repsWeightLine(context.state) {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                // Compact: logo mark + the current exercise (truncated to
                // whatever space the island allows)
                HStack(spacing: 4) {
                    IslandLogo()
                    Text(context.state.workoutName)
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 64, alignment: .leading)
                }
            } compactTrailing: {
                // Compact: the live clock on the right
                if LiveClock.hasClock(context.state) {
                    LiveClock(state: context.state)
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 50)
                } else {
                    Text("\(context.state.currentRound)/\(context.state.totalRounds)")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundColor(.orange)
                }
            } minimal: {
                // Minimal (pill squeezed by another live activity)
                IslandLogo(size: 15)
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
                if let detail = repsWeightLine(context.state) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer()
            LiveClock(state: context.state)
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundColor(.orange)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.10))
        .activitySystemActionForegroundColor(.white)
    }
}

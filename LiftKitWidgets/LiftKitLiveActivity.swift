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

/// The LiftKit app icon, sized for the Dynamic Island's compact slots.
private struct IslandLogo: View {
    var size: CGFloat = 22
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
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
                    if let end = context.state.phaseEndDate, end > .now {
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.system(.title, design: .monospaced, weight: .bold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .padding(.trailing, 4)
                    }
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
                // Compact: app logo on the left
                IslandLogo()
            } compactTrailing: {
                // Compact: the live count on the right
                if let end = context.state.phaseEndDate, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text("\(context.state.currentRound)/\(context.state.totalRounds)")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundColor(.orange)
                }
            } minimal: {
                // Minimal (pill squeezed by another live activity)
                IslandLogo(size: 20)
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

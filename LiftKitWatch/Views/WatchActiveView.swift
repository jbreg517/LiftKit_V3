import SwiftUI

/// The live workout on the wrist.
///
/// One screen, one dominant number, one big tap target. Everything secondary is
/// small and grey — mid-set with a loaded bar is the worst possible time to hunt for
/// the control you need.
struct WatchActiveView: View {
    @Environment(\.dismiss) private var dismiss
    let controller: WatchWorkoutController

    @State private var showEndConfirm = false

    private var item: WatchMenu.Item? { controller.item }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                clock
                if controller.phase == .rest { restBadge }
                roundLine
                primaryAction
                if item?.config.type == .reps { setList }
                controls
                metrics
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(item?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("End workout?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("Save", role: .none) { controller.end(); dismiss() }
            Button("Discard", role: .destructive) { controller.discard(); dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: Clock

    /// Counts down inside a block, and up for the untimed types where elapsed time is
    /// the only number there is.
    private var clock: some View {
        let showCountdown = controller.phase != .done
            && !(item?.config.type == .reps || item?.config.type == .manual)
        let seconds = showCountdown ? controller.timeRemaining : controller.elapsed
        return Text(Self.clockText(seconds))
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(controller.phase == .done ? .green
                             : (controller.isPaused ? .secondary : .primary))
            .contentTransition(.numericText())
    }

    private var restBadge: some View {
        Text("REST")
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(.blue)
    }

    @ViewBuilder
    private var roundLine: some View {
        if let type = item?.config.type {
            switch type {
            case .emom, .intervals:
                Text("Round \(controller.currentRound) of \(controller.totalRounds)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            case .amrap, .forTime:
                Text("\(controller.roundsCompleted) round\(controller.roundsCompleted == 1 ? "" : "s")")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            case .reps, .manual:
                EmptyView()
            }
        }
    }

    // MARK: Primary action

    /// The one thing you came here to tap. For scored types that's "round done"; for
    /// reps it's the set list below, so this becomes the finish button.
    @ViewBuilder
    private var primaryAction: some View {
        if let type = item?.config.type, controller.phase != .done {
            switch type {
            case .amrap, .forTime:
                Button {
                    controller.completeRound()
                } label: {
                    Label("Round Done", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            case .emom, .intervals, .reps, .manual:
                EmptyView()
            }
        } else if controller.phase == .done {
            Text("Time")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.green)
        }
    }

    // MARK: Reps

    private var setList: some View {
        VStack(spacing: 4) {
            ForEach(item?.exercises ?? []) { ex in
                let done = controller.loggedSets(for: ex)
                Button {
                    controller.completeSet(ex, setNumber: done + 1)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(planLine(ex))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(done)/\(ex.sets)")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(done >= ex.sets ? .green : .orange)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(done >= ex.sets)
            }
        }
    }

    private func planLine(_ ex: WatchMenu.Exercise) -> String {
        var parts: [String] = []
        if ex.distanceMeters > 0 { parts.append("\(Int(ex.distanceMeters)) m") }
        else if ex.durationSeconds > 0 { parts.append("\(ex.durationSeconds)s") }
        else if ex.reps > 0 { parts.append("\(ex.reps) reps") }
        if ex.weight > 0 { parts.append("\(Int(ex.weight)) \(ex.weightUnit.rawValue)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                controller.togglePause()
            } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .disabled(controller.phase == .done)

            Button {
                showEndConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            if controller.heartRate > 0 {
                Label("\(Int(controller.heartRate))", systemImage: "heart.fill")
                    .foregroundStyle(.red)
            }
            if controller.activeEnergyKcal > 0 {
                Label("\(Int(controller.activeEnergyKcal))", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
    }

    /// m:ss under an hour, h:mm:ss over it.
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

import Foundation
import SwiftData
import WatchConnectivity

/// The phone's half of the watch link.
///
/// Pushes the menu of runnable workouts as **application context** (the system
/// retains and replays the last one, so the watch has it at launch without any
/// storage of its own), and receives the finished-workout files the watch sends back.
///
/// Everything here is best-effort. The watch app is a companion, not a dependency —
/// a phone with no watch paired should never see an error, and never pay a cost.
@Observable
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    /// The payload last pushed, so an unchanged menu isn't re-sent. Application
    /// context replaces wholesale, and pushing an identical one wakes the watch for
    /// nothing.
    private var lastPushed: Data?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    // MARK: Publishing the menu

    /// Rebuilds the menu from the store and pushes it if it changed.
    ///
    /// Cheap enough to call on foreground and after edits: the fetches are small and
    /// the diff check stops an unchanged menu from crossing the link.
    @MainActor
    func publish(from context: ModelContext) {
        guard let session, session.activationState == .activated else { return }
        let menu = Self.buildMenu(from: context)
        guard let data = WatchLink.encode(menu), data != lastPushed else { return }
        do {
            try session.updateApplicationContext([WatchLink.menuKey: data])
            lastPushed = data
        } catch {
            // Nothing user-facing: an unpaired or unreachable watch is the normal
            // case, not an error worth surfacing.
        }
    }

    /// The menu the watch should show: today's scheduled workouts first, then saved
    /// plans. Pure and `static` so it can be reasoned about (and tested) without a
    /// live `WCSession`.
    @MainActor
    static func buildMenu(from context: ModelContext) -> WatchMenu {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let schedules = (try? context.fetch(FetchDescriptor<WorkoutSchedule>())) ?? []
        // Due today or carried forward from a missed day — the same rule the phone's
        // TODAY section uses, so the two never disagree about what's outstanding.
        let due = schedules
            .filter { !$0.isCompleted && cal.startOfDay(for: $0.date) <= today }
            .sorted { $0.date < $1.date }
            .compactMap { sched -> WatchMenu.Item? in
                guard let template = sched.template else { return nil }
                return item(from: template, name: sched.displayName,
                            source: .scheduled, referenceID: sched.id)
            }

        let templates = (try? context.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]))) ?? []
        // Program-generated templates are an implementation detail of a scheduled
        // program (they're one per session×block), so they're hidden here exactly as
        // they are in the phone's plan list. They still reach the watch when one is
        // scheduled — via the `due` list above.
        let plans = templates
            .filter { !$0.isProgramGenerated }
            .prefix(20)
            .map { item(from: $0, name: $0.name, source: .plan, referenceID: $0.id) }

        return WatchMenu(unitRaw: UnitSystem.current.rawValue,
                         scheduledToday: due,
                         plans: Array(plans))
    }

    /// Flattens a template into a wire item. Falls back to a Reps config for plans
    /// saved before timings were persisted.
    @MainActor
    private static func item(from template: WorkoutTemplate, name: String,
                             source: WatchMenu.Item.Source,
                             referenceID: UUID) -> WatchMenu.Item {
        let sorted = template.sortedExercises
        let config = template.storedConfig
            ?? TimerConfig.defaultConfig(for: sorted.first?.timerType ?? .reps)
        let exercises = sorted.map { ex in
            WatchMenu.Exercise(
                name: ex.exerciseName,
                sets: ex.targetSets,
                reps: ex.targetReps,
                durationSeconds: ex.targetDuration,
                distanceMeters: ex.targetDistanceMeters,
                weight: ex.targetWeight,
                weightUnit: ex.weightUnit,
                linkedToNext: ex.linkedToNext)
        }
        return WatchMenu.Item(name: name, config: config, exercises: exercises,
                              source: source, referenceID: referenceID)
    }

    // MARK: Announcing this device's state

    /// Tell the watch the phone has started or finished a workout, so it warns
    /// rather than starting a second recording of the same session.
    func announce(active: Bool, label: String) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(WorkoutOwner.message(active: active, label: label),
                            replyHandler: nil) { _ in }
    }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    /// The watch telling us it started or finished a workout.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { WorkoutOwner.shared.handle(message: message) }
    }

    // Both are required on iOS. After deactivation the system hands the session to a
    // newly paired watch; reactivating is what keeps the link alive across a swap.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

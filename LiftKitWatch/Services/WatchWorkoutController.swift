import Foundation
import HealthKit
import Observation
import WatchKit

/// Runs a workout on the wrist.
///
/// Owns a real `HKWorkoutSession`, which is the whole reason the watch can do this at
/// all: without one, watchOS suspends the app seconds after the wrist drops and the
/// round clock stops — precisely when it matters. The session also brings live heart
/// rate and active energy in for free via `HKLiveWorkoutBuilder`.
///
/// ## Phase semantics
///
/// These mirror the phone's `TimerEngine.advancePhase()` exactly. That function is the
/// source of truth; if it changes, this must change with it. They are reimplemented
/// rather than shared because the phone engine reaches for UIKit haptics and an
/// audio engine, while the wrist uses `WKInterfaceDevice`. What *is* shared is
/// `TimerConfig` — the numbers themselves — so the two can't disagree about how long
/// a round is, only (in the worst case) about what happens at its end.
///
/// - AMRAP: one timed block per `roundDurations` entry, else a single
///   `totalDuration`. The timer's round counter tracks elapsed blocks; the athlete's
///   score is `roundsCompleted`, a separate tally they advance by tapping.
/// - EMOM: `rounds` blocks of exactly 60s.
/// - Intervals: work → rest, `intervalRounds` times.
/// - For Time: counts down from the cap; finishing early is the point.
/// - Reps: no clock. Sets are logged as they're done.
/// - Manual: counts up until stopped.
@Observable
final class WatchWorkoutController: NSObject {
    static let shared = WatchWorkoutController()

    enum Phase: String { case idle, work, rest, done }

    // MARK: Published state

    private(set) var phase: Phase = .idle
    private(set) var item: WatchMenu.Item?
    /// Seconds left in the current block. Meaningless for `.reps` / `.manual`.
    private(set) var timeRemaining: TimeInterval = 0
    /// Seconds since the workout started, excluding pauses.
    private(set) var elapsed: TimeInterval = 0
    private(set) var currentRound = 1
    private(set) var totalRounds = 1
    /// The AMRAP score — rounds the athlete says they finished.
    private(set) var roundsCompleted = 0
    private(set) var isPaused = false
    private(set) var heartRate: Double = 0
    private(set) var activeEnergyKcal: Double = 0
    /// Sets logged so far, in order.
    private(set) var completedSets: [WatchWorkoutPayload.CompletedSet] = []

    var isRunning: Bool { phase == .work || phase == .rest }

    // MARK: Private

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var ticker: Timer?
    /// Wall-clock anchor for the current block. Using an end *date* rather than
    /// decrementing a counter keeps the clock honest across suspension — the app can
    /// miss ticks and still resume showing the right number.
    private var phaseEndDate: Date?
    private var startDate = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    // MARK: Authorisation

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        [.heartRate, .activeEnergyBurned]
            .compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { read.insert($0) }
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    // MARK: Start

    func start(_ item: WatchMenu.Item) {
        guard !isRunning else { return }
        self.item = item
        completedSets = []
        roundsCompleted = 0
        currentRound = 1
        pausedTotal = 0
        pausedAt = nil
        isPaused = false
        startDate = Date()

        startHealthSession(for: item.config.type)
        WatchStore.shared.announce(active: true, label: item.name)

        let config = item.config
        switch config.type {
        case .amrap:
            let blocks = config.roundDurations
            totalRounds = max(1, blocks.count)
            beginBlock(blocks.first ?? config.totalDuration)
        case .emom:
            totalRounds = max(1, config.rounds)
            beginBlock(60)
        case .intervals:
            totalRounds = max(1, config.intervalRounds)
            beginBlock(config.workDuration)
        case .forTime:
            totalRounds = 1
            beginBlock(config.totalDuration)
        case .reps, .manual:
            // No block clock — just a running total.
            totalRounds = 1
            phase = .work
            phaseEndDate = nil
            timeRemaining = 0
            startTicker()
        }
        WKInterfaceDevice.current().play(.start)
    }

    private func beginBlock(_ duration: TimeInterval) {
        phase = .work
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = duration
        startTicker()
    }

    // MARK: Ticking

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so the clock keeps running while the user scrolls.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    @MainActor
    private func tick() {
        guard !isPaused else { return }
        elapsed = Date().timeIntervalSince(startDate) - pausedTotal

        guard let end = phaseEndDate else { return }   // reps / manual count up only
        let left = end.timeIntervalSinceNow
        timeRemaining = max(0, left)
        if left <= 0 { advance() }
    }

    /// End of a block. Mirrors `TimerEngine.advancePhase()`.
    @MainActor
    private func advance() {
        guard let config = item?.config else { return }
        switch config.type {
        case .amrap:
            let blocks = config.roundDurations
            if currentRound < blocks.count {
                currentRound += 1
                beginBlock(blocks[currentRound - 1])
                WKInterfaceDevice.current().play(.notification)
            } else {
                finishClock()
            }

        case .emom:
            if currentRound < totalRounds {
                currentRound += 1
                beginBlock(60)
                WKInterfaceDevice.current().play(.notification)
            } else {
                finishClock()
            }

        case .intervals:
            if phase == .work {
                phase = .rest
                phaseEndDate = Date().addingTimeInterval(config.restDuration)
                timeRemaining = config.restDuration
                WKInterfaceDevice.current().play(.stop)
            } else if currentRound < totalRounds {
                currentRound += 1
                beginBlock(config.workDuration)
                WKInterfaceDevice.current().play(.start)
            } else {
                finishClock()
            }

        case .forTime, .reps, .manual:
            finishClock()
        }
    }

    /// The clock ran out. The workout is *not* saved yet — the athlete still has to
    /// end it, so a finished AMRAP can be reviewed before it's committed.
    @MainActor
    private func finishClock() {
        ticker?.invalidate(); ticker = nil
        phaseEndDate = nil
        timeRemaining = 0
        phase = .done
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: Athlete input

    /// AMRAP / For Time: one more round done.
    func completeRound() {
        roundsCompleted += 1
        WKInterfaceDevice.current().play(.click)
    }

    /// Reps: log a set at its planned numbers. No editing on the wrist — the planned
    /// values are right the overwhelming majority of the time, and adjusting weight
    /// on a small screen mid-set is worse than reaching for the phone.
    func completeSet(_ exercise: WatchMenu.Exercise, setNumber: Int) {
        completedSets.append(
            WatchWorkoutPayload.CompletedSet(
                exerciseName: exercise.name,
                setNumber: setNumber,
                reps: exercise.reps,
                durationSeconds: exercise.durationSeconds,
                distanceMeters: exercise.distanceMeters,
                weight: exercise.weight,
                weightUnit: exercise.weightUnit))
        WKInterfaceDevice.current().play(.click)
    }

    /// How many sets of this exercise are already logged.
    func loggedSets(for exercise: WatchMenu.Exercise) -> Int {
        completedSets.filter { $0.exerciseName == exercise.name }.count
    }

    // MARK: Pause / end

    func togglePause() {
        guard isRunning || isPaused else { return }
        if isPaused {
            // Push the block's end date out by however long we were paused, so the
            // remaining time is preserved rather than silently burned.
            if let pausedAt {
                let gap = Date().timeIntervalSince(pausedAt)
                pausedTotal += gap
                if let end = phaseEndDate { phaseEndDate = end.addingTimeInterval(gap) }
            }
            pausedAt = nil
            isPaused = false
            session?.resume()
        } else {
            pausedAt = Date()
            isPaused = true
            session?.pause()
        }
        WKInterfaceDevice.current().play(.click)
    }

    /// Ends the workout: stops the clock, saves to HealthKit, and queues the session
    /// for the phone.
    func end() {
        ticker?.invalidate(); ticker = nil
        let ended = Date()
        phase = .done
        WatchStore.shared.announce(active: false, label: "")

        let payload = WatchWorkoutPayload(
            name: item?.name ?? "Workout",
            type: item?.config.type ?? .reps,
            startedAt: startDate,
            endedAt: ended,
            activeSeconds: max(0, ended.timeIntervalSince(startDate) - pausedTotal),
            roundsCompleted: roundsCompleted,
            activeEnergyKcal: activeEnergyKcal,
            sets: completedSets,
            referenceID: item?.referenceID,
            source: item?.source ?? .plan)

        // Send first: this is queued to disk by the system, so it survives whatever
        // happens next. Saving to Health is best-effort on top.
        WatchStore.shared.send(payload)
        endHealthSession(at: ended)
    }

    /// Abandon without saving anything, anywhere.
    func discard() {
        ticker?.invalidate(); ticker = nil
        phase = .idle
        item = nil
        completedSets = []
        WatchStore.shared.announce(active: false, label: "")
        session?.end()
        session = nil
        builder = nil
    }

    // MARK: HealthKit plumbing

    private func startHealthSession(for type: TimerType) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: type)
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
        } catch {
            // No Health session means no background execution — the workout still
            // runs while the app is on screen, which beats refusing to start.
            session = nil
            builder = nil
        }
    }

    private func endHealthSession(at date: Date) {
        guard let session, let builder else { return }
        session.end()
        builder.endCollection(withEnd: date) { [weak self] _, _ in
            builder.finishWorkout { _, _ in
                self?.session = nil
                self?.builder = nil
            }
        }
    }

    /// Lifting has no single right answer here. Timed circuit work reads as HIIT to
    /// Health's own summaries, while straight sets read as strength training.
    private static func activityType(for type: TimerType) -> HKWorkoutActivityType {
        switch type {
        case .amrap, .emom, .intervals, .forTime: return .highIntensityIntervalTraining
        case .reps, .manual:                      return .traditionalStrengthTraining
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutController: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Losing the Health session costs background execution, not the workout —
        // the clock keeps running while the app is on screen.
        session = nil
        builder = nil
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutController: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
                Task { @MainActor in self.heartRate = bpm }
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                Task { @MainActor in self.activeEnergyKcal = kcal }
            default:
                break
            }
        }
    }
}

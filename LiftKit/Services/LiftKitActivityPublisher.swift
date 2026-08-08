import Foundation
import SwiftData

/// Publishes LiftKit's slice of the suite activity exchange (`SuiteActivity.swift`
/// is the shared wire format, byte-identical across the three apps; this file is
/// LiftKit's own). It answers the two questions HealthKit can't: **how hard was
/// that, for this lifter** and **what strength work is planned** — so RunKit can be
/// recovery-aware and FuelKit can fuel around it.
///
/// LiftKit writes only `suiteActivityFeed.liftkit` and never rewrites another app's
/// key, so two apps can't clobber each other. See `docs/SUITE-HEALTH-SYNC.md`.
enum LiftKitActivityPublisher {
    static let source = SuiteSource.liftkit

    /// Cheap enough to call on every foreground — a fetch, some arithmetic and one
    /// `UserDefaults` write.
    @MainActor
    static func publish(from context: ModelContext, now: Date = Date()) {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<WorkoutSchedule>())) ?? []
        publish(sessions: sessions, schedules: schedules, now: now)
    }

    @MainActor
    static func publish(sessions: [WorkoutSession], schedules: [WorkoutSchedule], now: Date = Date()) {
        let completed = sessions.filter { $0.completedAt != nil }
        let reference = referenceStrain(completed, now: now)
        // Bodyweight for the kcal estimate — the App-Group mirror is fine here (no
        // Health needed), since this kcal is itself the Health-off fallback.
        let weightLb = SuiteProfileStore.load()?.latestWeightLb ?? 0
        let feed = SuiteActivityFeed(
            source: source,
            recentLoad: dailyLoads(completed, reference: reference, weightLb: weightLb, now: now),
            planned: plannedSessions(schedules, now: now),
            carries: carries(completed, weightLb: weightLb, now: now))
        SuiteActivityStore.publish(feed)
    }

    // MARK: - Carries

    /// Weighted-carry work (vest / ruck / farmer's) as `SuiteCarry` entries, so RunKit
    /// and FuelKit can fold LiftKit's loaded work into their own views. One entry per
    /// session that contains carries — a gym session's carries are one bout of work,
    /// not one per set. Distance-less carries publish `kilometers: 0`, which the
    /// contract expects and covers with `kgMinutes`.
    private static func carries(_ sessions: [WorkoutSession], weightLb: Double,
                                now: Date) -> [SuiteCarry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -SuiteActivityFeed.historyWindow,
                                           to: now) ?? .distantPast
        let bodyweightKg = weightLb > 0 ? weightLb * 0.453592 : 0
        return sessions
            .filter { $0.hasCarries && $0.startedAt >= cutoff }
            .map { session in
                let sets = session.carrySets
                // Minutes under load: the summed hold time when recorded, otherwise the
                // session's own active minutes — a carry logged only by distance still
                // took time, and kgMinutes is the only figure a reader gets for it.
                let heldSeconds = sets.compactMap(\.duration).reduce(0, +)
                let minutes = heldSeconds > 0 ? heldSeconds / 60 : session.activeMinutes
                return SuiteCarry(
                    startedAt: session.startedAt,
                    kind: .carry,
                    title: session.name,
                    loadKg: session.heaviestCarryKg,
                    bodyweightKg: bodyweightKg,
                    minutes: minutes,
                    kilometers: session.carryDistanceMeters / 1000.0)
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - Load

    /// Raw, unnormalised strain for one session. Lifting has no TRIMP without HR, so
    /// this uses **active minutes** (LiftKit records `activeSeconds`, excluding the
    /// countdown and pauses; older sessions fall back to wall-clock via `duration`).
    /// Crude, but it's normalised against the lifter's own norm below, which is what
    /// makes "hard for them" comparable across the suite.
    ///
    /// **Deliberately still duration-only now that sRPE exists.** Folding RPE in here
    /// would silently change what `load` means for readers already consuming it, and
    /// worse, it would mix units within one percentile pool — rated sessions measured in
    /// RPE×minutes against unrated ones measured in minutes, so a lifter who rates some
    /// sessions and not others would see their norm jump. sRPE travels in its own field
    /// (`sessionLoad`), where its absence is visible as nil rather than as a low number.
    private static func strain(of session: WorkoutSession) -> Double {
        max(0, session.duration / 60)
    }

    /// Per-day load for days the athlete actually lifted. Days with no session are
    /// omitted, never published as `.rest` — LiftKit can't know a blank day was rest
    /// (they may have run). Absent means "LiftKit has nothing to say" (see the note
    /// on `SuiteActivityStore.totalLoad`).
    private static func dailyLoads(_ sessions: [WorkoutSession], reference: Double,
                                   weightLb: Double, now: Date) -> [SuiteDailyLoad] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let earliest = cal.date(byAdding: .day, value: -SuiteActivityFeed.historyWindow,
                                      to: today) else { return [] }

        var byDay: [Date: [WorkoutSession]] = [:]
        for s in sessions where s.startedAt >= earliest {
            byDay[cal.startOfDay(for: s.startedAt), default: []].append(s)
        }

        return byDay.map { day, daySessions in
            let total = daySessions.reduce(0.0) { $0 + strain(of: $1) }
            // Absolute burn for the App-Group fallback (0 when no bodyweight is known).
            let kcal = weightLb > 0
                ? daySessions.reduce(0.0) { $0 + HealthCalculations.workoutCalories(for: $1, bodyweightLb: weightLb) }
                : 0
            // Session-RPE load. `sessionLoad` sums across the day's sessions because
            // that's the only form that merges correctly downstream — a reader adding
            // two apps' figures gets the right total, which multiplying a merged RPE by
            // merged minutes would not. `perceivedEffort` is the hardest single session,
            // since perceived effort doesn't add up.
            let rated = daySessions.compactMap { session -> (rpe: Double, au: Double)? in
                guard let au = TrainingLoad.srpe(for: session) else { return nil }
                return (TrainingLoad.rpe(for: session).value, au)
            }
            return SuiteDailyLoad(date: day,
                                  kind: .strength,
                                  load: reference > 0 ? min(1, total / reference) : 0,
                                  perceivedEffort: rated.map(\.rpe).max() ?? 0,
                                  sessionCount: daySessions.count,
                                  activeKcal: kcal,
                                  activeMinutes: daySessions.reduce(0) { $0 + $1.activeMinutes },
                                  sessionLoad: rated.reduce(0) { $0 + $1.au })
        }
        .sorted { $0.date < $1.date }
    }

    /// What a hard lifting day looks like **for this lifter** — the 90th percentile
    /// of their own active-day strain over the last 90 days. Falls back to a fixed
    /// reference until there's enough history for a percentile to mean anything, so a
    /// first workout doesn't publish 1.0.
    private static func referenceStrain(_ sessions: [WorkoutSession], now: Date) -> Double {
        let fallback = 45.0   // a solid ~45-minute session
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -90, to: now) else { return fallback }

        var byDay: [Date: Double] = [:]
        for s in sessions where s.startedAt >= start {
            byDay[cal.startOfDay(for: s.startedAt), default: 0] += strain(of: s)
        }
        let values = byDay.values.filter { $0 > 0 }.sorted()
        guard values.count >= 5 else { return fallback }

        let index = Int((Double(values.count - 1) * 0.9).rounded())
        return max(20, values[index])
    }

    // MARK: - Plans

    /// Upcoming scheduled workouts, so FuelKit can fuel and RunKit can avoid stacking
    /// a hard run the day before legs.
    private static func plannedSessions(_ schedules: [WorkoutSchedule], now: Date) -> [SuitePlannedSession] {
        let today = Calendar.current.startOfDay(for: now)
        return schedules
            .filter { !$0.isCompleted && $0.date >= today }
            .sorted { $0.date < $1.date }
            .prefix(SuiteActivityFeed.planWindow)
            .map { sched in
                SuitePlannedSession(date: sched.date,
                                    kind: .strength,
                                    title: sched.displayName,
                                    plannedMinutes: 0,
                                    plannedLoad: 0)
            }
    }
}

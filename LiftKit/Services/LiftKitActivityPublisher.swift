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
            planned: plannedSessions(schedules, now: now))
        SuiteActivityStore.publish(feed)
    }

    // MARK: - Load

    /// Raw, unnormalised strain for one session. Lifting has no TRIMP without HR, so
    /// this uses **active minutes** (LiftKit records `activeSeconds`, excluding the
    /// countdown and pauses; older sessions fall back to wall-clock via `duration`).
    /// Crude, but it's normalised against the lifter's own norm below, which is what
    /// makes "hard for them" comparable across the suite.
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
            return SuiteDailyLoad(date: day,
                                  kind: .strength,
                                  load: reference > 0 ? min(1, total / reference) : 0,
                                  perceivedEffort: 0,   // LiftKit doesn't collect session RPE
                                  sessionCount: daySessions.count,
                                  activeKcal: kcal)
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

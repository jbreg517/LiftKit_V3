import Foundation

/// Session-RPE training load — Foster's method, adapted to lifting.
///
/// **Why this and not tonnage.** Volume load (weight × reps) is dominated by exercise
/// selection: a squat moves several times the absolute load of a curl for comparable
/// stimulus, so a light upper-body week followed by a heavy lower-body week produces a
/// swing that measures *which body part was trained*, not how hard the week was.
/// Session RPE × duration sidesteps that entirely because it never touches the bar
/// weight. It is also validated across modalities including resistance training, which
/// means one number can span a lift and a run — the reason the suite wants it.
///
/// Tonnage stays available (`WorkoutSession.totalVolume`) as a secondary figure. It is
/// never the headline.
///
/// **Units.** sRPE is in arbitrary units (AU): `RPE (1–10) × active minutes`. A 45-minute
/// session at RPE 7 is 315 AU. The absolute number means nothing on its own; the point is
/// comparison against the same lifter's other weeks.
///
/// **No verdicts.** Everything here returns a number. Whether 2,400 AU in a week is good
/// is the lifter's call, and nothing in this file decides it.
enum TrainingLoad {

    // MARK: - Session RPE

    /// Where a session's RPE came from. Displayed, because a rating the lifter gave and
    /// one averaged out of their set logs are not the same claim.
    enum RPESource: Equatable {
        /// The lifter rated the session as a whole.
        case entered
        /// Averaged from per-set (or per-exercise) ratings, because no session rating
        /// was given.
        case derived
        /// Nothing to go on.
        case none
    }

    /// Sets rated below this are treated as not being a training dose — see
    /// `isHardSet(_:)`.
    static let easySetThreshold: Double = 5

    /// The session's RPE and where it came from.
    ///
    /// A session rating always wins. The fallback averages the working sets the lifter
    /// *did* rate, which is a genuinely different construct — Foster's sRPE asks for one
    /// global rating of the whole session, and the mean of individual set ratings tends to
    /// run higher, because people rate the sets they bothered to rate. It is a usable
    /// stand-in and is flagged as `.derived` everywhere it surfaces so it never
    /// masquerades as an answer the lifter gave.
    static func rpe(for session: WorkoutSession) -> (value: Double, source: RPESource) {
        if let given = session.sessionRPE, given > 0 { return (given, .entered) }
        let rated = ratedEfforts(in: session)
        guard !rated.isEmpty else { return (0, .none) }
        return (rated.reduce(0, +) / Double(rated.count), .derived)
    }

    /// Every effort rating in the session, warm-ups excluded.
    ///
    /// Per-set ratings are preferred; the exercise-level `WorkoutEntry.rpe` is the
    /// fallback for AMRAP/EMOM-style workouts, which don't log sets individually.
    private static func ratedEfforts(in session: WorkoutSession) -> [Double] {
        var values: [Double] = []
        for entry in session.entries {
            let setRPEs = entry.sets
                .filter { $0.setType != .warmup }
                .compactMap(\.rpe)
                .filter { $0 > 0 }
            if !setRPEs.isEmpty {
                values.append(contentsOf: setRPEs)
            } else if let exerciseRPE = entry.rpe, exerciseRPE > 0 {
                values.append(exerciseRPE)
            }
        }
        return values
    }

    /// Session load in AU, or nil when there's no RPE or no measured time.
    ///
    /// Nil is the honest answer and callers must keep it distinct from zero: an unrated
    /// session was still training, and folding it in as 0 AU would make a hard week
    /// look like a light one.
    static func srpe(for session: WorkoutSession) -> Double? {
        let rating = rpe(for: session)
        guard rating.source != .none else { return nil }
        let minutes = session.activeMinutes
        guard minutes > 0 else { return nil }
        return rating.value * minutes
    }

    /// Foster's verbal anchors for the 1–10 session scale. The unlabelled steps are
    /// intentional in the original — they're the gaps between named levels, not
    /// descriptions someone forgot to write.
    static func rpeAnchor(for value: Double) -> String {
        switch Int(value.rounded()) {
        case ...1: return "1 — very easy"
        case 2:    return "2 — easy"
        case 3:    return "3 — moderate"
        case 4:    return "4 — somewhat hard"
        case 5:    return "5 — hard"
        case 6:    return "6"
        case 7:    return "7 — very hard"
        case 8:    return "8"
        case 9:    return "9"
        default:   return "10 — maximal"
        }
    }

    // MARK: - Working sets

    /// A set that counts toward training volume: anything not tagged as a warm-up.
    static func isWorkingSet(_ set: SetRecord) -> Bool {
        set.setType != .warmup
    }

    /// A working set that also looks like a training dose.
    ///
    /// The hypertrophy literature counts sets taken near failure, which strictly means
    /// only rated sets would qualify. Nobody rates every set, so the rule here is
    /// *exclude what the lifter told us was easy*: a working set counts unless it carries
    /// a rating below `easySetThreshold`. An **unrated** set counts — absence of a rating
    /// isn't evidence the set was easy, and dropping unrated sets would make the count
    /// collapse for the majority who never touch the RPE field.
    static func isHardSet(_ set: SetRecord) -> Bool {
        guard isWorkingSet(set) else { return false }
        if let rpe = set.rpe, rpe > 0, rpe < easySetThreshold { return false }
        return true
    }

    /// Hard working sets in a session.
    static func hardSetCount(in session: WorkoutSession) -> Int {
        session.entries.reduce(0) { $0 + $1.sets.filter(isHardSet).count }
    }

    /// Hard-set credit per muscle group over a window, highest first.
    ///
    /// Per-muscle rather than a single total, because that's the distortion tonnage
    /// suffers from: a heavy lower-body week and a light upper-body week are different
    /// training, not different amounts of it. Primary muscle takes a full set, each
    /// secondary takes half (`Exercise.muscleContributions`).
    static func hardSetsByMuscle(_ sessions: [WorkoutSession], since cutoff: Date) -> [(muscle: MuscleGroup, sets: Double)] {
        var counts: [MuscleGroup: Double] = [:]
        for session in sessions where !session.isActive && session.startedAt >= cutoff {
            for entry in session.entries {
                guard let exercise = entry.exercise else { continue }
                let sets = Double(entry.sets.filter(isHardSet).count)
                guard sets > 0 else { continue }
                for contribution in exercise.muscleContributions {
                    counts[contribution.muscle, default: 0] += sets * contribution.weight
                }
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (muscle: $0.key, sets: $0.value) }
    }

    /// Weekly sets per muscle group the hypertrophy literature associates with a good
    /// return. A **reference line**, not a target and not a pass mark — plenty of people
    /// train productively either side of it.
    static let referenceSetsPerMuscleWeek: Double = 10

    // MARK: - Aggregates

    /// One day's training, summed across however many sessions it held.
    struct DayLoad: Identifiable, Equatable {
        /// Start of day.
        let date: Date
        /// Summed sRPE in AU, counting only the sessions that had a rating.
        var srpe: Double = 0
        var minutes: Double = 0
        var sessions: Int = 0
        /// How many of `sessions` contributed to `srpe`. When this is less than
        /// `sessions`, the load is an undercount and the UI says so.
        var ratedSessions: Int = 0
        var hardSets: Int = 0

        var id: Date { date }
        var isFullyRated: Bool { sessions > 0 && ratedSessions == sessions }
    }

    /// Per-day loads for days that were actually trained, oldest first.
    ///
    /// Untrained days are **omitted, not emitted as zero**. Rolling windows below add
    /// their own zeros where they need them; a caller charting these must not read a gap
    /// as data.
    static func dailyLoads(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> [DayLoad] {
        var byDay: [Date: DayLoad] = [:]
        for session in sessions where !session.isActive {
            let day = calendar.startOfDay(for: session.startedAt)
            var load = byDay[day] ?? DayLoad(date: day)
            load.sessions += 1
            load.minutes += session.activeMinutes
            load.hardSets += hardSetCount(in: session)
            if let au = srpe(for: session) {
                load.srpe += au
                load.ratedSessions += 1
            }
            byDay[day] = load
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    struct WeekLoad: Identifiable, Equatable {
        /// Start of the week, per the caller's calendar.
        let weekStart: Date
        var srpe: Double = 0
        var minutes: Double = 0
        var sessions: Int = 0
        var ratedSessions: Int = 0
        var hardSets: Int = 0

        var id: Date { weekStart }
        var isFullyRated: Bool { sessions > 0 && ratedSessions == sessions }
    }

    /// The last `weeks` weeks including the current one, oldest first.
    ///
    /// Zero weeks inside the window **are** included: within a range the lifter was
    /// using the app, a week with no training is a fact about the week. That's the
    /// opposite of the rule for `dailyLoads`, and the difference is deliberate — a
    /// bounded window has a known denominator, a bare list of days doesn't.
    static func weeklyLoads(_ sessions: [WorkoutSession], weeks: Int,
                            now: Date = Date(), calendar: Calendar = .current) -> [WeekLoad] {
        guard weeks > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        else { return [] }

        var buckets: [Date: WeekLoad] = [:]
        var starts: [Date] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { continue }
            buckets[start] = WeekLoad(weekStart: start)
            starts.append(start)
        }
        guard let earliest = starts.first else { return [] }

        for session in sessions where !session.isActive && session.startedAt >= earliest {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start,
                  var week = buckets[start] else { continue }
            week.sessions += 1
            week.minutes += session.activeMinutes
            week.hardSets += hardSetCount(in: session)
            if let au = srpe(for: session) {
                week.srpe += au
                week.ratedSessions += 1
            }
            buckets[start] = week
        }
        return starts.compactMap { buckets[$0] }
    }

    /// Total AU over the `days` ending on `endingOn` inclusive.
    static func rollingLoad(_ days: [DayLoad], endingOn end: Date, over window: Int,
                            calendar: Calendar = .current) -> Double {
        let last = calendar.startOfDay(for: end)
        guard let first = calendar.date(byAdding: .day, value: -(window - 1), to: last) else { return 0 }
        return days.filter { $0.date >= first && $0.date <= last }.reduce(0) { $0 + $1.srpe }
    }

    /// This week's load against what the last four weeks averaged — the acute:chronic
    /// workload ratio, as a bare number.
    ///
    /// 1.0 means the last seven days match the recent norm; 1.5 means half again as much.
    /// The published "sweet spot" bands around this metric are **contested** — the ratio
    /// has well-documented statistical problems (it shares data between numerator and
    /// denominator, and is sensitive to how the windows are defined), so LiftKit shows
    /// the number and no interpretation.
    ///
    /// Nil until there's a 28-day history to compare against, because a ratio computed
    /// from two weeks of data is arithmetic dressed up as information.
    static func acuteChronicRatio(_ days: [DayLoad], now: Date = Date(),
                                  calendar: Calendar = .current) -> Double? {
        guard let earliest = days.first?.date,
              let cutoff = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: now)),
              earliest <= cutoff
        else { return nil }
        let chronic = rollingLoad(days, endingOn: now, over: 28, calendar: calendar) / 4
        guard chronic > 0 else { return nil }
        return rollingLoad(days, endingOn: now, over: 7, calendar: calendar) / chronic
    }

    /// Foster monotony: how *evenly* the week's load was spread — mean daily load
    /// divided by its standard deviation, counting untrained days as zero.
    ///
    /// Note the direction, which reads backwards until you look at the formula: **high
    /// monotony means sameness**, not intensity. Training the identical amount every day
    /// gives a tiny standard deviation and therefore a large ratio; one big session in an
    /// otherwise empty week gives a large deviation and a small ratio. Foster's interest
    /// was in high monotony *combined with* high load — a week with no easy days and no
    /// rest — which is what `strain(_:endingOn:)` expresses.
    ///
    /// Nil when the week holds no load. Also nil in the degenerate case where all seven
    /// days are identical: monotony is unbounded there, and returning nil is more honest
    /// than returning a number that only looks finite because of floating point.
    static func monotony(_ days: [DayLoad], endingOn end: Date,
                        calendar: Calendar = .current) -> Double? {
        let last = calendar.startOfDay(for: end)
        guard let first = calendar.date(byAdding: .day, value: -6, to: last) else { return nil }
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.srpe) })
        var values: [Double] = []
        for offset in 0...6 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            values.append(byDay[day] ?? 0)
        }
        guard values.count == 7 else { return nil }
        let mean = values.reduce(0, +) / 7
        guard mean > 0 else { return nil }
        // Population SD: these seven days are the whole week, not a sample of it.
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 7
        let sd = variance.squareRoot()
        guard sd > 0 else { return nil }
        return mean / sd
    }

    /// Foster strain: weekly load × monotony. High when a lot of work was done *and*
    /// spread flatly across the week with no easy days. Nil whenever monotony is.
    static func strain(_ days: [DayLoad], endingOn end: Date,
                       calendar: Calendar = .current) -> Double? {
        guard let m = monotony(days, endingOn: end, calendar: calendar) else { return nil }
        return rollingLoad(days, endingOn: end, over: 7, calendar: calendar) * m
    }
}

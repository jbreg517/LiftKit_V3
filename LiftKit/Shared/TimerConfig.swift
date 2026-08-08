import Foundation

// Split out of TimerEngine.swift and moved to Shared/ so the watch app can compile
// it: the wrist and the phone must agree on what an EMOM *is*, and the surest way
// to guarantee that is one definition rather than two. The engine itself stays on
// the phone side for now — it pulls in notifications and audio.

// MARK: - Timer Config
struct TimerConfig {
    var type: TimerType
    // AMRAP / For Time / Manual
    var totalDuration: TimeInterval = 600
    /// For Time: how many times to repeat the exercise list (default 1).
    var forTimeRounds: Int = 1
    /// Multi-round AMRAP: per-round durations in seconds (e.g. two 10-minute
    /// circuits). Empty or a single entry = classic one-block AMRAP using
    /// `totalDuration`.
    var roundDurations: [TimeInterval] = []
    // EMOM
    var rounds: Int = 10
    // Intervals
    var workDuration: TimeInterval = 40
    var restDuration: TimeInterval = 20
    var intervalRounds: Int = 8
    // Reps rest
    var restBetweenSets: TimeInterval = 90

    static func defaultConfig(for type: TimerType) -> TimerConfig {
        var c = TimerConfig(type: type)
        switch type {
        case .amrap:     c.totalDuration = 600
        case .emom:      c.rounds = 10
        case .forTime:   c.totalDuration = 1200
        case .intervals: c.workDuration = 40; c.restDuration = 20; c.intervalRounds = 8
        case .reps:      c.restBetweenSets = 90
        case .manual:    break
        }
        return c
    }

    var totalTime: TimeInterval {
        switch type {
        case .intervals: return (workDuration + restDuration) * Double(intervalRounds)
        case .amrap:     return roundDurations.count > 1 ? roundDurations.reduce(0, +) : totalDuration
        case .emom:      return Double(rounds) * 60
        case .forTime:   return totalDuration
        default:         return 0
        }
    }
}

// MARK: - Persistence

/// Codable so a completed `WorkoutSession` can store the exact timings it was run
/// with (see `WorkoutSession.timerConfigData`) and "Do Again" can reproduce them.
///
/// Decoding is deliberately forgiving: every field falls back to its default when
/// absent, so a config written by an older or newer build never throws — a hard
/// failure here would drop the session back to default timings, the very bug this
/// round-trip exists to prevent.
extension TimerConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, totalDuration, forTimeRounds, roundDurations
        case rounds, workDuration, restDuration, intervalRounds, restBetweenSets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(type: (try? c.decode(TimerType.self, forKey: .type)) ?? .manual)
        if let v = try? c.decode(TimeInterval.self, forKey: .totalDuration)   { totalDuration = v }
        if let v = try? c.decode(Int.self, forKey: .forTimeRounds)            { forTimeRounds = v }
        if let v = try? c.decode([TimeInterval].self, forKey: .roundDurations) { roundDurations = v }
        if let v = try? c.decode(Int.self, forKey: .rounds)                   { rounds = v }
        if let v = try? c.decode(TimeInterval.self, forKey: .workDuration)    { workDuration = v }
        if let v = try? c.decode(TimeInterval.self, forKey: .restDuration)    { restDuration = v }
        if let v = try? c.decode(Int.self, forKey: .intervalRounds)           { intervalRounds = v }
        if let v = try? c.decode(TimeInterval.self, forKey: .restBetweenSets) { restBetweenSets = v }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(totalDuration, forKey: .totalDuration)
        try c.encode(forTimeRounds, forKey: .forTimeRounds)
        try c.encode(roundDurations, forKey: .roundDurations)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(workDuration, forKey: .workDuration)
        try c.encode(restDuration, forKey: .restDuration)
        try c.encode(intervalRounds, forKey: .intervalRounds)
        try c.encode(restBetweenSets, forKey: .restBetweenSets)
    }
}

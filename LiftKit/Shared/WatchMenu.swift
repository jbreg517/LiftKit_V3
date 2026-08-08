import Foundation

/// What the watch shows on its menu. Member of both the iOS app and the watch app
/// targets.
///
/// The watch will eventually **run the workout itself** (see docs/WATCH-APP.md), so
/// this carries the real timings and the real movement list rather than a
/// pre-formatted description of them. What it deliberately does *not* carry is any
/// SwiftData type: `WorkoutTemplate` and `WorkoutSchedule` stay on the phone, and the
/// watch refers back to them by id only.
struct WatchMenu: Codable, Hashable {

    /// One movement in a watch-side workout. A flattened `TemplateExercise` — enough
    /// to display it and to log what was done, and nothing else.
    struct Exercise: Codable, Hashable, Identifiable {
        var id: UUID = UUID()
        var name: String = ""
        var sets: Int = 1
        var reps: Int = 0
        /// Hold time in seconds. 0 = rep-based.
        var durationSeconds: Int = 0
        /// Ground covered under load, in meters. 0 = not a carry.
        var distanceMeters: Double = 0
        var weight: Double = 0
        /// `WeightUnit.rawValue`.
        var weightUnitRaw: String = WeightUnit.lb.rawValue
        /// Performed back-to-back with the next movement (a superset or complex).
        var linkedToNext: Bool = false

        var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

        init(id: UUID = UUID(), name: String = "", sets: Int = 1, reps: Int = 0,
             durationSeconds: Int = 0, distanceMeters: Double = 0, weight: Double = 0,
             weightUnit: WeightUnit = .lb, linkedToNext: Bool = false) {
            self.id = id
            self.name = name
            self.sets = sets
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
            self.weight = weight
            self.weightUnitRaw = weightUnit.rawValue
            self.linkedToNext = linkedToNext
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 1
            reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
            durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
            distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
            weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 0
            weightUnitRaw = try c.decodeIfPresent(String.self, forKey: .weightUnitRaw) ?? WeightUnit.lb.rawValue
            linkedToNext = try c.decodeIfPresent(Bool.self, forKey: .linkedToNext) ?? false
        }
    }

    /// One runnable thing on the watch: what to run, plus the identity the phone
    /// needs to reconcile a finished session against what was planned.
    struct Item: Codable, Hashable, Identifiable {

        /// Where this came from, so a finished workout can be tied back to it.
        enum Source: String, Codable, CaseIterable {
            case scheduled   // a `WorkoutSchedule` due today — gets ticked off
            case plan        // a saved `WorkoutTemplate`
            case quick       // nothing saved; a bare timer started on the wrist
        }

        var id: UUID = UUID()
        var name: String = ""
        /// The day's timings. Shared type, so the wrist and the phone can't disagree
        /// about round length or rest.
        var config: TimerConfig = TimerConfig(type: .reps)
        var exercises: [Exercise] = []
        /// `Source.rawValue`. A string so a source this watch build doesn't know yet
        /// degrades to a default instead of failing the whole decode.
        var sourceRaw: String = Source.plan.rawValue
        /// The `WorkoutSchedule` or `WorkoutTemplate` id, per `source`.
        var referenceID: UUID?

        var source: Source { Source(rawValue: sourceRaw) ?? .plan }
        var type: TimerType { config.type }

        /// The one-line description under the row. Computed here rather than sent
        /// pre-formatted — the watch holds both the timings and the unit preference,
        /// so there is nothing to gain from formatting twice.
        var summary: String {
            let n = exercises.count
            let moves = "\(n) move\(n == 1 ? "" : "s")"
            switch config.type {
            case .amrap:     return "AMRAP · \(Int(config.totalTime / 60)) min · \(moves)"
            case .emom:      return "EMOM · \(config.rounds) min · \(moves)"
            case .forTime:   return "For Time · \(Int(config.totalDuration / 60)) min cap · \(moves)"
            case .intervals: return "Intervals · \(config.intervalRounds)× · \(moves)"
            case .reps:      return moves
            case .manual:    return "Self-paced · \(moves)"
            }
        }

        init(id: UUID = UUID(), name: String = "",
             config: TimerConfig = TimerConfig(type: .reps),
             exercises: [Exercise] = [], source: Source = .plan,
             referenceID: UUID? = nil) {
            self.id = id
            self.name = name
            self.config = config
            self.exercises = exercises
            self.sourceRaw = source.rawValue
            self.referenceID = referenceID
        }

        /// Every field optional on the wire. The phone app and the watch app update
        /// **independently** — a watch running last month's build will be handed
        /// today's payload — and a synthesised decoder throws on any absent key,
        /// which would empty the menu rather than degrade it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            config = try c.decodeIfPresent(TimerConfig.self, forKey: .config) ?? TimerConfig(type: .reps)
            exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
            sourceRaw = try c.decodeIfPresent(String.self, forKey: .sourceRaw) ?? Source.plan.rawValue
            referenceID = try c.decodeIfPresent(UUID.self, forKey: .referenceID)
        }
    }

    /// `UnitSystem.rawValue` — the watch formats its own strings, but the choice is
    /// still the phone's to make.
    var unitRaw: String = UnitSystem.imperial.rawValue
    /// Due today or carried forward from a missed day — what the watch suggests first.
    var scheduledToday: [Item] = []
    /// The user's saved plans, most recently used first.
    var plans: [Item] = []

    var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    init(unitRaw: String = UnitSystem.imperial.rawValue,
         scheduledToday: [Item] = [], plans: [Item] = []) {
        self.unitRaw = unitRaw
        self.scheduledToday = scheduledToday
        self.plans = plans
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unitRaw = try c.decodeIfPresent(String.self, forKey: .unitRaw) ?? UnitSystem.imperial.rawValue
        scheduledToday = try c.decodeIfPresent([Item].self, forKey: .scheduledToday) ?? []
        plans = try c.decodeIfPresent([Item].self, forKey: .plans) ?? []
    }
}

// MARK: - Transport

/// The WatchConnectivity dictionary keys, in one place so the two sides can't drift.
enum WatchLink {
    /// Application-context key carrying an encoded `WatchMenu`.
    ///
    /// Application context, not a message: the system retains and replays the last
    /// one, so the menu is on disk for free and is present at launch instead of
    /// blank until the phone next pushes.
    static let menuKey = "menu"
    /// Message key: `true` while that device has a live workout.
    ///
    /// Deliberately a *message*, not application context. This is an event with a
    /// short useful life — "I started, don't you start too" — and application
    /// context is retained and replayed, which would leave a device believing the
    /// other was still mid-workout hours later.
    static let activeKey = "workoutActive"
    /// Message key carried alongside `activeKey`: what's running, for the banner.
    static let activeLabelKey = "workoutLabel"
    /// Filename prefix for a transferred finished workout.
    static let sessionFilePrefix = "liftkit-session-"

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from any: Any?) -> T? {
        guard let data = any as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

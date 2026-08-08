import Foundation

/// A workout the watch recorded, on its way to the phone.
///
/// Sent with `transferFile`, not `sendMessage`: the workout has to survive the phone
/// being out of range for its entire duration, and the system persists the queue to
/// disk and retries on its own. So this arrives even if the phone was left in a
/// locker the whole session.
///
/// The watch has already saved the workout to HealthKit by the time this is sent.
/// This exists so the session also appears in **LiftKit's own history** with its sets
/// — Health holds the workout, not the reps.
struct WatchWorkoutPayload: Codable, Hashable, Identifiable {

    /// One set the athlete actually completed.
    struct CompletedSet: Codable, Hashable, Identifiable {
        var id: UUID = UUID()
        var exerciseName: String = ""
        var setNumber: Int = 1
        /// 0 when the set wasn't rep-based.
        var reps: Int = 0
        /// Hold time in seconds. 0 when not timed.
        var durationSeconds: Int = 0
        /// Ground covered under load, in meters. 0 when not a carry.
        var distanceMeters: Double = 0
        var weight: Double = 0
        var weightUnitRaw: String = WeightUnit.lb.rawValue
        var completedAt: Date = Date()

        var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

        init(id: UUID = UUID(), exerciseName: String = "", setNumber: Int = 1,
             reps: Int = 0, durationSeconds: Int = 0, distanceMeters: Double = 0,
             weight: Double = 0, weightUnit: WeightUnit = .lb,
             completedAt: Date = Date()) {
            self.id = id
            self.exerciseName = exerciseName
            self.setNumber = setNumber
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
            self.weight = weight
            self.weightUnitRaw = weightUnit.rawValue
            self.completedAt = completedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            exerciseName = try c.decodeIfPresent(String.self, forKey: .exerciseName) ?? ""
            setNumber = try c.decodeIfPresent(Int.self, forKey: .setNumber) ?? 1
            reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
            durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
            distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
            weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 0
            weightUnitRaw = try c.decodeIfPresent(String.self, forKey: .weightUnitRaw) ?? WeightUnit.lb.rawValue
            completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date()
        }
    }

    var id: UUID = UUID()
    var name: String = ""
    /// `TimerType.rawValue`, as a string so a type this phone build doesn't know
    /// degrades instead of failing the decode.
    var typeRaw: String = TimerType.reps.rawValue
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    /// Time actually spent working, excluding pauses.
    var activeSeconds: Double = 0
    /// Rounds the athlete completed — the AMRAP score. Distinct from the timer's
    /// round counter, which counts elapsed blocks rather than work done.
    var roundsCompleted: Int = 0
    var activeEnergyKcal: Double = 0
    var sets: [CompletedSet] = []
    /// The `WorkoutSchedule` or `WorkoutTemplate` this came from, so the phone can
    /// tick a scheduled workout off rather than leaving it outstanding.
    var referenceID: UUID?
    /// `WatchMenu.Item.Source.rawValue`, so the phone knows what `referenceID` means.
    var sourceRaw: String = WatchMenu.Item.Source.plan.rawValue

    var type: TimerType { TimerType(rawValue: typeRaw) ?? .reps }
    var source: WatchMenu.Item.Source { WatchMenu.Item.Source(rawValue: sourceRaw) ?? .plan }

    init(id: UUID = UUID(), name: String = "", type: TimerType = .reps,
         startedAt: Date = Date(), endedAt: Date = Date(), activeSeconds: Double = 0,
         roundsCompleted: Int = 0, activeEnergyKcal: Double = 0,
         sets: [CompletedSet] = [], referenceID: UUID? = nil,
         source: WatchMenu.Item.Source = .plan) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.roundsCompleted = roundsCompleted
        self.activeEnergyKcal = activeEnergyKcal
        self.sets = sets
        self.referenceID = referenceID
        self.sourceRaw = source.rawValue
    }

    /// Every field optional on the wire — the watch and the phone update
    /// independently, and a workout that fails to decode is a workout the athlete
    /// did and lost.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        typeRaw = try c.decodeIfPresent(String.self, forKey: .typeRaw) ?? TimerType.reps.rawValue
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? Date()
        activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
        roundsCompleted = try c.decodeIfPresent(Int.self, forKey: .roundsCompleted) ?? 0
        activeEnergyKcal = try c.decodeIfPresent(Double.self, forKey: .activeEnergyKcal) ?? 0
        sets = try c.decodeIfPresent([CompletedSet].self, forKey: .sets) ?? []
        referenceID = try c.decodeIfPresent(UUID.self, forKey: .referenceID)
        sourceRaw = try c.decodeIfPresent(String.self, forKey: .sourceRaw) ?? WatchMenu.Item.Source.plan.rawValue
    }
}

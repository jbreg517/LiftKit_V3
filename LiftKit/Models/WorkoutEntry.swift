import Foundation
import SwiftData

@Model
final class WorkoutEntry {
    var id: UUID = UUID()
    var timerTypeRaw: String = TimerType.reps.rawValue
    var sortOrder: Int = 0
    var notes: String?
    /// Number of sets prescribed at setup time. Used by progression to know
    /// whether every planned set was completed. 0 = unknown (legacy data).
    var plannedSets: Int = 0
    /// Equipment used for this exercise instance. Weight memory/progression is
    /// keyed by exercise + equipment so e.g. kettlebell and barbell front squats
    /// track separately. nil = unspecified (legacy data).
    var equipmentRaw: String? = nil
    /// Exercise-level weight for non-rep workouts (AMRAP/EMOM/etc., which don't
    /// log per-set records). Rep workouts keep weight on each SetRecord.
    var weight: Double? = nil
    var weightUnit: String = WeightUnit.lb.rawValue
    /// Exercise-level RPE for non-rep workouts.
    var rpe: Double? = nil
    /// Superset group index within the session (nil = standalone).
    var supersetGroup: Int? = nil

    var exercise: Exercise?
    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetRecord.entry)
    var sets: [SetRecord] = []

    init(
        id: UUID = UUID(),
        timerType: TimerType = .reps,
        sortOrder: Int = 0,
        notes: String? = nil,
        plannedSets: Int = 0
    ) {
        self.id = id
        self.timerTypeRaw = timerType.rawValue
        self.sortOrder = sortOrder
        self.notes = notes
        self.plannedSets = plannedSets
        self.sets = []
    }

    var timerType: TimerType {
        get { TimerType(rawValue: timerTypeRaw) ?? .reps }
        set { timerTypeRaw = newValue.rawValue }
    }

    var equipmentEnum: Equipment? {
        guard let e = equipmentRaw else { return nil }
        return Equipment(rawValue: e)
    }

    var weightUnitEnum: WeightUnit {
        WeightUnit(rawValue: weightUnit) ?? .lb
    }

    var sortedSets: [SetRecord] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    var nextSetNumber: Int {
        (sets.map(\.setNumber).max() ?? 0) + 1
    }

    var bestSet: SetRecord? {
        sets.max { a, b in
            let va = (a.weight ?? 0) * Double(a.reps ?? 0)
            let vb = (b.weight ?? 0) * Double(b.reps ?? 0)
            return va < vb
        }
    }
}

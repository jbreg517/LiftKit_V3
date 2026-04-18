import Foundation
import SwiftData

@Model
final class WorkoutEntry {
    var id: UUID
    var timerTypeRaw: String
    var sortOrder: Int
    var notes: String?

    var exercise: Exercise?
    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetRecord.entry)
    var sets: [SetRecord]

    init(
        id: UUID = UUID(),
        timerType: TimerType = .reps,
        sortOrder: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.timerTypeRaw = timerType.rawValue
        self.sortOrder = sortOrder
        self.notes = notes
        self.sets = []
    }

    var timerType: TimerType {
        get { TimerType(rawValue: timerTypeRaw) ?? .reps }
        set { timerTypeRaw = newValue.rawValue }
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

import Foundation
import SwiftData

@Model
final class SetRecord {
    var id: UUID
    var setNumber: Int
    var weight: Double?
    var weightUnit: String
    var reps: Int?
    var duration: TimeInterval?
    var completedAt: Date
    var notes: String?
    var plannedWeight: Double?
    var plannedReps: Int?

    var entry: WorkoutEntry?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weight: Double? = nil,
        weightUnit: WeightUnit = .lb,
        reps: Int? = nil,
        duration: TimeInterval? = nil,
        completedAt: Date = Date(),
        notes: String? = nil,
        plannedWeight: Double? = nil,
        plannedReps: Int? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.weightUnit = weightUnit.rawValue
        self.reps = reps
        self.duration = duration
        self.completedAt = completedAt
        self.notes = notes
        self.plannedWeight = plannedWeight
        self.plannedReps = plannedReps
    }

    var weightUnitEnum: WeightUnit {
        WeightUnit(rawValue: weightUnit) ?? .lb
    }

    var volume: Double {
        guard let w = weight, let r = reps else { return 0 }
        let lbs = weightUnitEnum == .kg ? w * 2.20462 : w
        return lbs * Double(r)
    }
}

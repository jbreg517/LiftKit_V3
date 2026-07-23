import Foundation
import SwiftData

/// Optional tag for a logged set (normal, warm-up, drop, or failure).
enum SetType: String, CaseIterable, Identifiable {
    case normal, warmup, drop, failure
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal:  return "Normal"
        case .warmup:  return "Warm-up"
        case .drop:    return "Drop"
        case .failure: return "Failure"
        }
    }
    /// Single-letter chip shown next to the set; nil for normal.
    var badge: String? {
        switch self {
        case .normal:  return nil
        case .warmup:  return "W"
        case .drop:    return "D"
        case .failure: return "F"
        }
    }
}

@Model
final class SetRecord {
    var id: UUID = UUID()
    var setNumber: Int = 0
    var weight: Double?
    var weightUnit: String = WeightUnit.lb.rawValue
    var reps: Int?
    var duration: TimeInterval?
    var completedAt: Date = Date()
    var notes: String?
    var plannedWeight: Double?
    var plannedReps: Int?
    var plannedDuration: Int?
    var setTypeRaw: String?
    var rpe: Double?

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
        plannedReps: Int? = nil,
        plannedDuration: Int? = nil,
        setType: SetType = .normal,
        rpe: Double? = nil
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
        self.plannedDuration = plannedDuration
        self.setTypeRaw = setType == .normal ? nil : setType.rawValue
        self.rpe = rpe
    }

    var setType: SetType {
        get { setTypeRaw.flatMap { SetType(rawValue: $0) } ?? .normal }
        set { setTypeRaw = newValue == .normal ? nil : newValue.rawValue }
    }

    /// True when this set tracks a hold time rather than reps.
    var isTimed: Bool { duration != nil && reps == nil }

    var weightUnitEnum: WeightUnit {
        WeightUnit(rawValue: weightUnit) ?? .lb
    }

    var volume: Double {
        guard let w = weight, let r = reps else { return 0 }
        let lbs = weightUnitEnum == .kg ? w * 2.20462 : w
        return lbs * Double(r)
    }
}

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
    /// Distance covered under load, in **meters** (canonical). nil for a set that
    /// isn't distance-tracked. Additive/optional → lightweight migration.
    var distanceMeters: Double?
    /// The unit the user entered the distance in, so it's shown back the same way.
    var distanceUnitRaw: String?
    var plannedDistanceMeters: Double?

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
        rpe: Double? = nil,
        distanceMeters: Double? = nil,
        distanceUnit: DistanceUnit? = nil,
        plannedDistanceMeters: Double? = nil
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
        self.distanceMeters = distanceMeters
        self.distanceUnitRaw = distanceUnit?.rawValue
        self.plannedDistanceMeters = plannedDistanceMeters
    }

    var setType: SetType {
        get { setTypeRaw.flatMap { SetType(rawValue: $0) } ?? .normal }
        set { setTypeRaw = newValue == .normal ? nil : newValue.rawValue }
    }

    /// True when this set tracks a hold time rather than reps.
    var isTimed: Bool { duration != nil && reps == nil }

    /// True when this set tracks ground covered under load (a ruck or carry).
    var isDistance: Bool { (distanceMeters ?? 0) > 0 }

    var distanceUnit: DistanceUnit {
        distanceUnitRaw.flatMap { DistanceUnit(rawValue: $0) }
            ?? DistanceUnit.default(for: .current, short: (distanceMeters ?? 0) < 400)
    }

    /// The distance shown back in the unit it was entered in.
    var distanceDisplay: Double? {
        distanceMeters.map { distanceUnit.fromMeters($0) }
    }

    var weightUnitEnum: WeightUnit {
        WeightUnit(rawValue: weightUnit) ?? .lb
    }

    /// Tonnage. Deliberately 0 for a carry: load × distance isn't the same quantity
    /// as load × reps, and adding them would make one misleading number out of two
    /// honest ones. Carries are reported separately (see the carry figures below).
    var volume: Double {
        guard let w = weight, let r = reps else { return 0 }
        let lbs = weightUnitEnum == .kg ? w * 2.20462 : w
        return lbs * Double(r)
    }

    /// External load in kilograms, whatever unit it was entered in.
    var loadKg: Double {
        guard let w = weight else { return 0 }
        return weightUnitEnum == .kg ? w : w * 0.453592
    }

    /// The tonnage analogue for a carry: kilograms moved over distance. Matches
    /// `SuiteCarry.kgKilometers` so LiftKit and RunKit report the same quantity.
    var carryKgKilometers: Double {
        guard let m = distanceMeters, m > 0 else { return 0 }
        return loadKg * (m / 1000.0)
    }

    /// Time under load, in kg·minutes — the only carry figure available when a set
    /// was measured by time rather than distance. Mirrors `SuiteCarry.kgMinutes`.
    var carryKgMinutes: Double {
        guard let d = duration, d > 0 else { return 0 }
        return loadKg * (d / 60.0)
    }
}

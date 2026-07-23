import Foundation
import SwiftData

/// Linear weight progression.
///
/// Rules:
/// - Complete all reps of every set → add weight next workout
///   (+5 lb / +2.5 kg standard, +10 lb / +5 kg for deadlift).
/// - Miss any reps → repeat the same weight next workout.
/// - Fail the same weight 3 workouts in a row → deload 10%.
final class ProgressionService {
    static let shared = ProgressionService()
    private init() {}

    enum Reason {
        case increase
        case hold
        case deload
    }

    struct Suggestion {
        let weight: Double
        let unit: WeightUnit
        let equipment: Equipment?
        let reason: Reason
        let delta: Double      // signed change from last working weight
        let note: String       // short hint for the UI
    }

    /// Returns a weight suggestion for the next time this exercise is performed
    /// with the given equipment, or `nil` when there's no matching rep-based
    /// history. Keyed by exercise identity AND equipment so e.g. kettlebell vs
    /// barbell front squats progress independently.
    func suggest(exerciseID: UUID?, exerciseName: String, equipment: Equipment, in context: ModelContext) -> Suggestion? {
        guard let exercise = ExerciseLookup.resolve(id: exerciseID, name: exerciseName, in: context) else { return nil }

        // One past performance per entry, restricted to matching equipment.
        let performances = exercise.entries
            .filter { ExerciseLookup.matches($0, equipment: equipment, exerciseDefault: exercise.equipmentEnum) }
            .compactMap { performance(for: $0, exerciseDefault: exercise.equipmentEnum) }
            .sorted { $0.date > $1.date }   // newest first

        guard let last = performances.first else { return nil }
        let inc = increment(forExercise: exercise.name, unit: last.unit)

        if last.success {
            let newWeight = last.weight + inc
            return Suggestion(
                weight: newWeight, unit: last.unit, equipment: last.equipment,
                reason: .increase, delta: inc,
                note: "↑ +\(fmt(inc)) \(last.unit.rawValue) · hit all reps"
            )
        }

        // Count consecutive recent failures at this exact weight.
        var consecutiveFailures = 0
        for p in performances {
            guard abs(p.weight - last.weight) < 0.001, !p.success else { break }
            consecutiveFailures += 1
        }

        if consecutiveFailures >= 3 {
            let deloaded = roundToIncrement(last.weight * 0.9, unit: last.unit)
            return Suggestion(
                weight: deloaded, unit: last.unit, equipment: last.equipment,
                reason: .deload, delta: deloaded - last.weight,
                note: "↓ Deload −10% · failed 3×"
            )
        }

        return Suggestion(
            weight: last.weight, unit: last.unit, equipment: last.equipment,
            reason: .hold, delta: 0,
            note: "Repeat \(fmt(last.weight)) \(last.unit.rawValue) · missed reps"
        )
    }

    // MARK: - Internal

    private struct Performance {
        let date: Date
        let weight: Double
        let unit: WeightUnit
        let equipment: Equipment?
        let success: Bool
    }

    /// Reduces a single entry to a pass/fail at a working weight.
    /// Skips timed entries and entries without weighted sets.
    private func performance(for entry: WorkoutEntry, exerciseDefault: Equipment?) -> Performance? {
        if entry.timerType == .forTime { return nil }
        let sets = entry.sets.filter { $0.weight != nil }
        guard !sets.isEmpty else { return nil }

        let weight = sets.compactMap(\.weight).max() ?? 0
        let date = sets.map(\.completedAt).max() ?? .distantPast
        let unit = sets.first?.weightUnitEnum ?? .lb

        // All planned sets present (when we know the count) and every set hit its target reps.
        let completedAllSets = entry.plannedSets <= 0 || sets.count >= entry.plannedSets
        let hitAllReps = sets.allSatisfy { set in
            guard let planned = set.plannedReps else { return true }
            return (set.reps ?? 0) >= planned
        }

        return Performance(
            date: date, weight: weight, unit: unit,
            equipment: ExerciseLookup.entryEquipment(entry, exerciseDefault: exerciseDefault),
            success: completedAllSets && hitAllReps
        )
    }

    private func increment(forExercise name: String, unit: WeightUnit) -> Double {
        let isDeadlift = name.lowercased().contains("deadlift")
        switch unit {
        case .lb: return isDeadlift ? 10 : 5
        case .kg: return isDeadlift ? 5 : 2.5
        }
    }

    private func roundToIncrement(_ weight: Double, unit: WeightUnit) -> Double {
        let step: Double = unit == .lb ? 5 : 2.5
        return (weight / step).rounded() * step
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Shared exercise resolution + equipment matching, used by both
/// ProgressionService and WeightCache so weight memory is keyed by
/// exercise identity AND equipment.
enum ExerciseLookup {
    /// Resolve an exercise by stable id first, then by case-insensitive/trimmed name.
    static func resolve(id: UUID?, name: String, in context: ModelContext) -> Exercise? {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        if let id, let found = all.first(where: { $0.id == id }) { return found }
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return nil }
        return all.first(where: { $0.name.lowercased() == lower })
    }

    /// Equipment recorded for an entry, falling back to the exercise's default
    /// for legacy entries that predate per-entry equipment tracking.
    static func entryEquipment(_ entry: WorkoutEntry, exerciseDefault: Equipment?) -> Equipment? {
        entry.equipmentEnum ?? exerciseDefault
    }

    /// Whether an entry's equipment matches the requested equipment.
    static func matches(_ entry: WorkoutEntry, equipment: Equipment, exerciseDefault: Equipment?) -> Bool {
        let target: Equipment? = equipment == .none ? nil : equipment
        return entryEquipment(entry, exerciseDefault: exerciseDefault) == target
    }
}

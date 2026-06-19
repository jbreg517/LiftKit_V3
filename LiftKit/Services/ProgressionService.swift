import Foundation
import SwiftData

/// Stronglifts-style linear progression.
///
/// Rules (matching the Stronglifts app):
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

    /// Returns a weight suggestion for the next time this exercise is performed,
    /// or `nil` when there's no rep-based history to base it on.
    func suggest(exerciseName: String, in context: ModelContext) -> Suggestion? {
        let lower = exerciseName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Exercise>()
        guard let all = try? context.fetch(descriptor),
              let exercise = all.first(where: { $0.name.lowercased() == lower }) else { return nil }

        // One past performance per entry (an exercise within a single session).
        let performances = exercise.entries
            .compactMap { performance(for: $0, equipment: exercise.equipmentEnum) }
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
    private func performance(for entry: WorkoutEntry, equipment: Equipment?) -> Performance? {
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
            equipment: equipment, success: completedAllSets && hitAllReps
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

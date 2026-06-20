import Foundation
import SwiftData

final class WeightCache {
    static let shared = WeightCache()
    private init() {}

    /// Most recent weight logged for an exercise with the given equipment.
    /// Keyed by exercise identity AND equipment (see ExerciseLookup), so e.g.
    /// kettlebell and barbell variants don't bleed into each other.
    func lookup(exerciseID: UUID?, exerciseName: String, equipment: Equipment, in context: ModelContext) -> (weight: Double, unit: WeightUnit, equipment: Equipment?)? {
        guard let exercise = ExerciseLookup.resolve(id: exerciseID, name: exerciseName, in: context) else { return nil }

        let recentSet = exercise.entries
            .filter { ExerciseLookup.matches($0, equipment: equipment, exerciseDefault: exercise.equipmentEnum) }
            .flatMap { $0.sets }
            .filter { $0.weight != nil }
            .max(by: { $0.completedAt < $1.completedAt })

        guard let set = recentSet, let weight = set.weight else { return nil }
        return (weight, WeightUnit(rawValue: set.weightUnit) ?? .lb, exercise.equipmentEnum)
    }

    /// Sets logged the last time this exercise + equipment was performed,
    /// excluding the in-progress session. Used to show "last time" inline.
    func previousSets(exerciseID: UUID?, exerciseName: String, equipment: Equipment, excluding sessionID: UUID?, in context: ModelContext) -> [SetRecord]? {
        guard let exercise = ExerciseLookup.resolve(id: exerciseID, name: exerciseName, in: context) else { return nil }
        let entry = exercise.entries
            .filter { ExerciseLookup.matches($0, equipment: equipment, exerciseDefault: exercise.equipmentEnum) }
            .filter { $0.session?.id != sessionID && !$0.sets.isEmpty }
            .max(by: { ($0.sets.map(\.completedAt).max() ?? .distantPast) < ($1.sets.map(\.completedAt).max() ?? .distantPast) })
        return entry?.sortedSets
    }

    /// "Last: 135×5 · 135×5" summary of the previous session, or nil.
    func previousSummary(exerciseID: UUID?, exerciseName: String, equipment: Equipment, excluding sessionID: UUID?, in context: ModelContext) -> String? {
        guard let sets = previousSets(exerciseID: exerciseID, exerciseName: exerciseName, equipment: equipment, excluding: sessionID, in: context),
              !sets.isEmpty else { return nil }
        let parts = sets.map { set -> String in
            if let dur = set.duration, set.reps == nil { return "\(Int(dur))s" }
            let reps = set.reps ?? 0
            if let w = set.weight, w > 0 { return "\(Int(w))×\(reps)" }
            return "\(reps)"
        }
        return "Last: " + parts.joined(separator: " · ")
    }
}

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
}

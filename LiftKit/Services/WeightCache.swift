import Foundation
import SwiftData

final class WeightCache {
    static let shared = WeightCache()
    private init() {}

    func lookup(exerciseName: String, in context: ModelContext) -> (weight: Double, unit: WeightUnit, equipment: Equipment?)? {
        let lower = exerciseName.lowercased()
        let descriptor = FetchDescriptor<Exercise>()
        guard let allExercises = try? context.fetch(descriptor),
              let exercise = allExercises.first(where: { $0.name.lowercased() == lower }) else { return nil }

        let recentSet = exercise.entries
            .flatMap { $0.sets }
            .filter { $0.weight != nil }
            .max(by: { $0.completedAt < $1.completedAt })

        guard let set = recentSet, let weight = set.weight else { return nil }
        return (weight, WeightUnit(rawValue: set.weightUnit) ?? .lb, exercise.equipmentEnum)
    }

    func batchLookup(names: [String], in context: ModelContext) -> [String: (weight: Double, unit: WeightUnit, equipment: Equipment?)] {
        var result: [String: (weight: Double, unit: WeightUnit, equipment: Equipment?)] = [:]
        for name in names {
            if let found = lookup(exerciseName: name, in: context) {
                result[name.lowercased()] = found
            }
        }
        return result
    }
}

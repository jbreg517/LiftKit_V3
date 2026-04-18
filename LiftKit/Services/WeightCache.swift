import Foundation
import SwiftData

final class WeightCache {
    static let shared = WeightCache()
    private init() {}

    func lookup(exerciseName: String, in context: ModelContext) -> (weight: Double, unit: WeightUnit, equipment: Equipment?)? {
        let lower = exerciseName.lowercased()
        let descriptor = FetchDescriptor<SetRecord>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        guard let allSets = try? context.fetch(descriptor) else { return nil }

        for set in allSets {
            guard let entry = set.entry,
                  let exercise = entry.exercise,
                  exercise.name.lowercased() == lower,
                  let weight = set.weight else { continue }
            let unit = WeightUnit(rawValue: set.weightUnit) ?? .lb
            let equipment = entry.exercise?.equipmentEnum
            return (weight, unit, equipment)
        }
        return nil
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

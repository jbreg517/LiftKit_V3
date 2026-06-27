import Foundation
import SwiftData

/// One day's macro totals (grams), held as a cached rollup of the day's logged
/// `FoodEntry` items. Calories are derived (Atwater), not stored, so there's a
/// single source of truth. CloudKit-compatible: every attribute has a default
/// and the relationship is optional.
@Model
final class NutritionDay {
    var id: UUID = UUID()
    var date: Date = Date()
    var proteinG: Double = 0
    var carbG: Double = 0
    var fatG: Double = 0
    var alcoholG: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \FoodEntry.nutritionDay)
    var entries: [FoodEntry]? = []

    init(date: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    /// Derived calories (Atwater: protein/carb 4, fat 9, alcohol 7 kcal/g).
    var calories: Double {
        Atwater.calories(proteinG: proteinG, carbG: carbG, fatG: fatG, alcoholG: alcoholG)
    }

    var isEmpty: Bool {
        proteinG == 0 && carbG == 0 && fatG == 0 && alcoholG == 0
    }

    /// Logged entries, oldest first.
    var sortedEntries: [FoodEntry] {
        (entries ?? []).sorted { $0.loggedAt < $1.loggedAt }
    }

    /// Recompute the cached totals from the day's entries. Call after any
    /// add / edit / delete of an entry.
    func recalcTotals() {
        let es = entries ?? []
        proteinG = es.reduce(0) { $0 + $1.proteinG }
        carbG    = es.reduce(0) { $0 + $1.carbG }
        fatG     = es.reduce(0) { $0 + $1.fatG }
        alcoholG = es.reduce(0) { $0 + $1.alcoholG }
    }
}

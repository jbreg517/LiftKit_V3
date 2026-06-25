import Foundation
import SwiftData

/// One day's running macro totals (grams). Calories are derived, not stored, so
/// there's a single source of truth. Manual entry only — no food database.
@Model
final class NutritionDay {
    var id: UUID = UUID()
    var date: Date = Date()
    var proteinG: Double = 0
    var carbG: Double = 0
    var fatG: Double = 0
    var alcoholG: Double = 0

    init(date: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    /// Atwater factors: protein/carb 4, fat 9, alcohol 7 kcal per gram.
    var calories: Double {
        proteinG * 4 + carbG * 4 + fatG * 9 + alcoholG * 7
    }

    var isEmpty: Bool {
        proteinG == 0 && carbG == 0 && fatG == 0 && alcoholG == 0
    }
}

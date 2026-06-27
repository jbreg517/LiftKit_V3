import Foundation
import SwiftData

/// One serving of a food logged on a day, under a meal. Macros are snapshotted
/// at log time so later edits to the source `FoodItem` never rewrite history.
/// CloudKit-compatible: every attribute has a default; relationships are optional.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var loggedAt: Date = Date()
    var mealTypeRaw: String = MealType.snack.rawValue
    /// How much was logged, in listed servings (gram entries store grams ÷ servingGrams).
    var quantity: Double = 1
    /// Whether the user entered grams (true) or servings (false) — display only.
    var enteredAsGrams: Bool = false
    var proteinG: Double = 0
    var carbG: Double = 0
    var fatG: Double = 0
    var alcoholG: Double = 0
    /// Comma-joined UUIDs of the HealthKit samples this entry created (for
    /// edit/delete propagation). Empty when not mirrored to Apple Health.
    var healthKitSampleIDs: String = ""

    @Relationship(deleteRule: .nullify) var foodItem: FoodItem?
    var nutritionDay: NutritionDay?

    init(loggedAt: Date = Date(),
         mealType: MealType = .snack,
         quantity: Double = 1,
         enteredAsGrams: Bool = false,
         macros: Macros = Macros(),
         foodItem: FoodItem? = nil) {
        self.loggedAt = loggedAt
        self.mealTypeRaw = mealType.rawValue
        self.quantity = quantity
        self.enteredAsGrams = enteredAsGrams
        self.proteinG = macros.proteinG
        self.carbG = macros.carbG
        self.fatG = macros.fatG
        self.alcoholG = macros.alcoholG
        self.foodItem = foodItem
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var macros: Macros {
        Macros(proteinG: proteinG, carbG: carbG, fatG: fatG, alcoholG: alcoholG)
    }

    var calories: Double { macros.calories }

    /// HealthKit sample UUIDs round-tripped through `healthKitSampleIDs`.
    var healthKitSampleUUIDs: [UUID] {
        get {
            healthKitSampleIDs
                .split(separator: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            healthKitSampleIDs = newValue.map(\.uuidString).joined(separator: ",")
        }
    }
}

/// The meal a `FoodEntry` belongs to. Snack may hold multiple entries.
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        }
    }

    /// Display / sort order for the day's sections.
    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch:     return 1
        case .dinner:    return 2
        case .snack:     return 3
        }
    }

    /// Time-of-day suggestion the user can override before logging.
    static func suggested(for date: Date = Date(), calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11:  return .breakfast
        case 11..<16: return .lunch
        case 16..<21: return .dinner
        default:      return .snack
        }
    }
}

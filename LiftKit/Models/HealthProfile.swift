import Foundation
import SwiftData

/// Single per-user record holding the stats needed for BMR / calorie math:
/// height, age, sex, activity level, and weight goal. Stored on-device
/// (CloudKit-compatible: every attribute has a default). A value of 0 means
/// "not set yet".
@Model
final class HealthProfile {
    var id: UUID = UUID()
    var heightInches: Double = 0
    var age: Int = 0
    var biologicalSexRaw: String = BiologicalSex.unspecified.rawValue
    var activityLevelRaw: String = ActivityLevel.moderate.rawValue
    var goalTypeRaw: String = WeightGoalType.maintain.rawValue
    var goalWeightLb: Double = 0
    var weeklyRateLb: Double = 1.0
    /// Grams of protein per lb bodyweight for the macro target.
    var proteinPerLb: Double = 0.8
    /// Share of the calorie target that comes from fat (carbs fill the rest).
    var fatPercent: Double = 0.30

    init() {}

    var biologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: biologicalSexRaw) ?? .unspecified }
        set { biologicalSexRaw = newValue.rawValue }
    }
    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderate }
        set { activityLevelRaw = newValue.rawValue }
    }
    var goalType: WeightGoalType {
        get { WeightGoalType(rawValue: goalTypeRaw) ?? .maintain }
        set { goalTypeRaw = newValue.rawValue }
    }

    /// Whether enough is filled in to compute a BMR.
    var isComplete: Bool { heightInches > 0 && age > 0 }
}

enum BiologicalSex: String, CaseIterable, Identifiable {
    case male, female, unspecified
    var id: String { rawValue }
    var label: String {
        switch self {
        case .male:        return "Male"
        case .female:      return "Female"
        case .unspecified: return "Not specified"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Lightly Active"
        case .moderate:   return "Moderately Active"
        case .active:     return "Active"
        case .veryActive: return "Very Active"
        }
    }
    var detail: String {
        switch self {
        case .sedentary:  return "Little or no exercise"
        case .light:      return "Exercise 1–3 days/week"
        case .moderate:   return "Exercise 3–5 days/week"
        case .active:     return "Exercise 6–7 days/week"
        case .veryActive: return "Hard daily training or physical job"
        }
    }
    /// TDEE multiplier applied to BMR.
    var multiplier: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum WeightGoalType: String, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lose:     return "Lose"
        case .maintain: return "Maintain"
        case .gain:     return "Gain"
        }
    }
}

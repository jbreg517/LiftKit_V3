import Foundation

/// Pure, on-device health math — no network, no integrations. All estimates are
/// rough by design (the UI labels them as such).
enum HealthCalculations {

    // MARK: - Resting / total energy

    /// Mifflin–St Jeor BMR in kcal/day. Returns nil if inputs are incomplete.
    static func bmr(weightLb: Double, heightInches: Double, age: Int, sex: BiologicalSex) -> Double? {
        guard weightLb > 0, heightInches > 0, age > 0 else { return nil }
        let kg = weightLb * 0.453592
        let cm = heightInches * 2.54
        let base = 10 * kg + 6.25 * cm - 5 * Double(age)
        switch sex {
        case .male:        return base + 5
        case .female:      return base - 161
        case .unspecified: return base - 78   // midpoint of the sex constants
        }
    }

    /// Total daily energy expenditure: BMR scaled by everyday activity.
    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    /// Daily calorie target for the chosen goal (~3500 kcal per pound).
    static func goalCalories(tdee: Double, goal: WeightGoalType, weeklyRateLb: Double) -> Double {
        let dailyAdjust = weeklyRateLb * 3500.0 / 7.0
        switch goal {
        case .lose:     return max(1200, tdee - dailyAdjust)
        case .gain:     return tdee + dailyAdjust
        case .maintain: return tdee
        }
    }

    // MARK: - Macro targets

    struct MacroTargets {
        let proteinG: Double
        let fatG: Double
        let carbG: Double
    }

    /// Splits a calorie target into macro gram goals: protein scaled to
    /// bodyweight, fat as a share of calories, carbs filling the remainder.
    static func macroTargets(calories: Double, weightLb: Double,
                             proteinPerLb: Double, fatPercent: Double) -> MacroTargets {
        let protein = max(0, proteinPerLb * weightLb)
        let proteinCals = protein * 4
        let fatCals = calories * fatPercent
        let fat = fatCals / 9
        let carbCals = max(0, calories - proteinCals - fatCals)
        return MacroTargets(proteinG: protein, fatG: fat, carbG: carbCals / 4)
    }

    // MARK: - Workout energy burn (MET method, no heart-rate data)

    /// Rough MET value per workout style.
    static func met(for type: TimerType?) -> Double {
        switch type {
        case .reps:      return 5.0   // vigorous resistance training
        case .amrap:     return 8.0
        case .emom:      return 8.0
        case .forTime:   return 8.0
        case .intervals: return 9.0   // high-intensity intervals (e.g. Tabata)
        case .manual:    return 4.0
        case .none:      return 5.0
        }
    }

    /// Estimated kcal burned: MET × bodyweight(kg) × hours.
    static func caloriesBurned(durationSeconds: Double, weightLb: Double, met: Double) -> Double {
        guard weightLb > 0, durationSeconds > 0 else { return 0 }
        let kg = weightLb * 0.453592
        let hours = durationSeconds / 3600.0
        return met * kg * hours
    }
}

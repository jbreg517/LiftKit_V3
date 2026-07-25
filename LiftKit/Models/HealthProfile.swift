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

// MARK: - Suite-shared profile (LiftKit / RunKit / FuelKit)

/// The health profile the three Ferrixguild apps share.
///
/// Split of responsibilities:
///  • Height & weight are native Apple Health types (`.height` / `.bodyMass`) —
///    written to and read from HealthKit, so they interoperate with any Health
///    app, not just the suite. They're mirrored here too as a fallback for when
///    the user hasn't granted Health access.
///  • The *goal* and nutrition targets are NOT HealthKit concepts, so they're
///    shared through a common App Group container instead.
///
/// This exact struct + keys + App Group id must match in all three apps. String
/// fields carry the same raw values as LiftKit's `WeightGoalType`,
/// `ActivityLevel`, and `BiologicalSex`.
struct SuiteProfile: Codable, Equatable {
    // Measurements (Apple Health is the source of truth; mirrored for fallback)
    var heightInches: Double = 0
    var age: Int = 0
    var biologicalSex: String = BiologicalSex.unspecified.rawValue
    var latestWeightLb: Double = 0

    // Goal + nutrition targets (shared only through the App Group)
    var goalType: String = WeightGoalType.maintain.rawValue
    var goalWeightLb: Double = 0
    var weeklyRateLb: Double = 1.0
    var activityLevel: String = ActivityLevel.moderate.rawValue
    var proteinPerLb: Double = 0.8
    var fatPercent: Double = 0.30

    /// When this was last written, so a reader can tell who is newest.
    var updatedAt: Date = .distantPast
}

/// Reads/writes the one `SuiteProfile` in the shared App Group. Every app in the
/// suite must list `appGroupID` in its entitlements
/// (`com.apple.security.application-groups`); without it `defaults` is nil and
/// all calls are safe no-ops.
///
/// TODO(iCloud): when the suite's iCloud is live, additionally mirror this key to
/// `NSUbiquitousKeyValueStore` so the goal follows across the user's devices.
enum SuiteProfileStore {
    static let appGroupID = "group.com.ferrixguild.suite"
    private static let key = "suiteHealthProfile"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func load() -> SuiteProfile? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SuiteProfile.self, from: data)
    }

    /// Persists `profile`, stamping `updatedAt`. Best-effort; a missing App Group
    /// (unprovisioned) simply does nothing.
    static func save(_ profile: SuiteProfile) {
        guard let defaults else { return }
        var p = profile
        p.updatedAt = Date()
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: key)
        }
    }
}

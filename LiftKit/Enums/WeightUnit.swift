import Foundation

enum WeightUnit: String, CaseIterable, Codable {
    case lb = "lb"
    case kg = "kg"

    func converted(_ value: Double, to target: WeightUnit) -> Double {
        if self == target { return value }
        return self == .lb ? value * 0.453592 : value * 2.20462
    }
}

/// App-wide measurement preference. Weights are stored canonically in lb and
/// body lengths in inches; this converts them to/from the user's chosen system
/// for display and entry.
enum UnitSystem: String, CaseIterable {
    case imperial, metric

    var label: String { self == .metric ? "Metric (kg)" : "Imperial (lb)" }
    var weightUnit: WeightUnit { self == .metric ? .kg : .lb }
    var weightLabel: String { weightUnit.rawValue }   // "kg" / "lb"
    var lengthLabel: String { self == .metric ? "cm" : "in" }

    /// Reads the saved preference (set in Settings). Defaults to imperial.
    static var current: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: "unitSystem") ?? "") ?? .imperial
    }

    func weightFromLb(_ lb: Double) -> Double { self == .metric ? lb * 0.453592 : lb }
    func weightToLb(_ value: Double) -> Double { self == .metric ? value / 0.453592 : value }
    func lengthFromInches(_ inches: Double) -> Double { self == .metric ? inches * 2.54 : inches }
    func lengthToInches(_ value: Double) -> Double { self == .metric ? value / 2.54 : value }
}

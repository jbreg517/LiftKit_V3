import Foundation

enum WeightUnit: String, CaseIterable, Codable {
    case lb = "lb"
    case kg = "kg"

    func converted(_ value: Double, to target: WeightUnit) -> Double {
        if self == target { return value }
        return self == .lb ? value * 0.453592 : value * 2.20462
    }
}

/// How a carry's distance is entered. Short units cover gym work (a 40 m farmer's
/// carry); long units cover rucks. Stored canonically in **meters** — the same
/// pattern as weights (lb) and lengths (inches) — so stats and the suite feed never
/// have to guess.
enum DistanceUnit: String, CaseIterable, Codable, Identifiable {
    case meters = "m"
    case yards  = "yd"
    case kilometers = "km"
    case miles  = "mi"

    var id: String { rawValue }
    var label: String { rawValue }
    /// Short units are for in-gym carries; long units for rucks and marches.
    var isShort: Bool { self == .meters || self == .yards }

    private var metersPerUnit: Double {
        switch self {
        case .meters:     return 1
        case .yards:      return 0.9144
        case .kilometers: return 1000
        case .miles:      return 1609.344
        }
    }

    func toMeters(_ value: Double) -> Double { value * metersPerUnit }
    func fromMeters(_ meters: Double) -> Double { meters / metersPerUnit }

    /// Sensible default for a measurement system: short for gym carries, long for
    /// distance work.
    static func `default`(for system: UnitSystem, short: Bool) -> DistanceUnit {
        switch (system, short) {
        case (.metric, true):   return .meters
        case (.metric, false):  return .kilometers
        case (.imperial, true): return .yards
        case (.imperial, false): return .miles
        }
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

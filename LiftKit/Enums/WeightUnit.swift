import Foundation

enum WeightUnit: String, CaseIterable, Codable {
    case lb = "lb"
    case kg = "kg"

    func converted(_ value: Double, to target: WeightUnit) -> Double {
        if self == target { return value }
        return self == .lb ? value * 0.453592 : value * 2.20462
    }
}

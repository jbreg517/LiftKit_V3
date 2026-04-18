import Foundation

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case lb = "lb"
    case kg = "kg"

    var id: String { rawValue }

    func convert(_ value: Double, to target: WeightUnit) -> Double {
        guard self != target else { return value }
        switch (self, target) {
        case (.lb, .kg): return value * 0.453592
        case (.kg, .lb): return value * 2.20462
        default: return value
        }
    }
}

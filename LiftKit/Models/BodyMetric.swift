import Foundation
import SwiftData

/// A single body measurement taken on a date — bodyweight, body-fat %, or a
/// tape measurement. Stored entirely on-device (CloudKit-compatible: every
/// attribute has a default).
@Model
final class BodyMetric {
    var id: UUID = UUID()
    var date: Date = Date()
    var typeRaw: String = BodyMetricType.bodyweight.rawValue
    var value: Double = 0
    var note: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: BodyMetricType = .bodyweight,
        value: Double = 0,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
        self.value = value
        self.note = note
    }

    var type: BodyMetricType {
        get { BodyMetricType(rawValue: typeRaw) ?? .bodyweight }
        set { typeRaw = newValue.rawValue }
    }
}

enum BodyMetricType: String, CaseIterable, Identifiable {
    case bodyweight, bodyFat, waist, chest, arms, thighs, hips, neck

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bodyweight: return "Bodyweight"
        case .bodyFat:    return "Body Fat"
        case .waist:      return "Waist"
        case .chest:      return "Chest"
        case .arms:       return "Arms"
        case .thighs:     return "Thighs"
        case .hips:       return "Hips"
        case .neck:       return "Neck"
        }
    }

    /// Display unit. Bodyweight uses lb to match the rest of the app.
    var unit: String {
        switch self {
        case .bodyweight: return "lb"
        case .bodyFat:    return "%"
        default:          return "in"
        }
    }

    var icon: String {
        switch self {
        case .bodyweight: return "scalemass.fill"
        case .bodyFat:    return "percent"
        default:          return "ruler.fill"
        }
    }

    /// True when a lower number is the improvement direction (for trend color).
    var lowerIsBetter: Bool {
        switch self {
        case .bodyFat, .waist: return true
        default:               return false
        }
    }

    // Values are stored canonically (bodyweight in lb, lengths in inches).
    // These convert to/from the user's chosen unit system for display & entry.
    func unitLabel(_ system: UnitSystem) -> String {
        switch self {
        case .bodyweight: return system.weightLabel
        case .bodyFat:    return "%"
        default:          return system.lengthLabel
        }
    }
    func toDisplay(_ value: Double, _ system: UnitSystem) -> Double {
        switch self {
        case .bodyweight: return system.weightFromLb(value)
        case .bodyFat:    return value
        default:          return system.lengthFromInches(value)
        }
    }
    func fromDisplay(_ value: Double, _ system: UnitSystem) -> Double {
        switch self {
        case .bodyweight: return system.weightToLb(value)
        case .bodyFat:    return value
        default:          return system.lengthToInches(value)
        }
    }
}

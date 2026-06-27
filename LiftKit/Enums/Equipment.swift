import Foundation

enum Equipment: String, CaseIterable, Identifiable, Codable {
    case none           = "None"
    case barbell        = "Barbell"
    case dumbbell       = "Dumbbell"
    case kettlebell     = "Kettlebell"
    case machine        = "Machine"
    case cable          = "Cable"
    case bodyweight     = "Bodyweight"
    case resistanceBand = "Band"
    case other          = "Other"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .none:           return "questionmark.circle"
        case .barbell:        return "dumbbell.fill"
        case .dumbbell:       return "dumbbell.fill"
        case .kettlebell:     return "circle.circle.fill"
        case .machine:        return "gear"
        case .cable:          return "cable.connector"
        case .bodyweight:     return "figure.walk"
        case .resistanceBand: return "waveform.path"
        case .other:          return "ellipsis.circle"
        }
    }
}

/// The user's "available equipment" preference (stored in UserDefaults as a
/// comma-separated list of raw values under `availableEquipment`).
enum EquipmentPrefs {
    static let key = "availableEquipment"
    /// Gear the user can mark as owned. Bodyweight / none / other need nothing.
    /// Cable was retired as a user-facing option (see `alwaysAvailable`).
    static let selectable: [Equipment] = [.barbell, .dumbbell, .kettlebell, .machine, .resistanceBand]
    static let defaultRaw = "Barbell,Dumbbell,Kettlebell,Machine,Band"

    static func available(_ raw: String) -> Set<Equipment> {
        Set(raw.split(separator: ",").compactMap { Equipment(rawValue: String($0)) })
    }

    static func raw(from set: Set<Equipment>) -> String {
        selectable.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// Equipment that never needs to be owned to count as available. Cable is
    /// here (rather than in `selectable`) so it's no longer a user toggle, but
    /// any existing cable-tagged exercises still count as doable.
    static func alwaysAvailable(_ e: Equipment) -> Bool {
        e == .bodyweight || e == .none || e == .other || e == .cable
    }
}

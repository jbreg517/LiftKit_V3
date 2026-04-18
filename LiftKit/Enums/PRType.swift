import Foundation

enum PRType: String, Codable, CaseIterable, Identifiable {
    case maxWeight = "maxWeight"
    case maxReps   = "maxReps"
    case maxVolume = "maxVolume"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .maxWeight: return "Max Weight"
        case .maxReps:   return "Max Reps"
        case .maxVolume: return "Max Volume"
        }
    }

    var shortLabel: String {
        switch self {
        case .maxWeight: return "lb"
        case .maxReps:   return "reps"
        case .maxVolume: return "lb"
        }
    }
}

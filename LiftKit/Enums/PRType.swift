import Foundation

enum PRType: String, CaseIterable, Codable {
    case maxWeight = "maxWeight"
    case maxReps   = "maxReps"
    case maxVolume = "maxVolume"

    var label: String {
        switch self {
        case .maxWeight: return "Max Weight"
        case .maxReps:   return "Max Reps"
        case .maxVolume: return "Max Volume"
        }
    }
}

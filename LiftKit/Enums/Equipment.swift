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

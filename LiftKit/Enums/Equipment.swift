import Foundation

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case none        = "None"
    case barbell     = "Barbell"
    case dumbbell    = "Dumbbell"
    case kettlebell  = "Kettlebell"
    case machine     = "Machine"
    case cable       = "Cable"
    case bodyweight  = "Bodyweight"
    case bands       = "Bands"
    case ball        = "Ball"
    case other       = "Other"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .none:       return "minus"
        case .barbell:    return "dumbbell.fill"
        case .dumbbell:   return "dumbbell.fill"
        case .kettlebell: return "scalemass.fill"
        case .machine:    return "gearshape.fill"
        case .cable:      return "cable.connector"
        case .bodyweight: return "figure.strengthtraining.traditional"
        case .bands:      return "arrow.left.and.right"
        case .ball:       return "circle.fill"
        case .other:      return "questionmark.circle"
        }
    }
}

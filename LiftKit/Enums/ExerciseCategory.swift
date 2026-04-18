import Foundation

enum ExerciseCategory: String, CaseIterable, Codable {
    case push    = "Push"
    case pull    = "Pull"
    case legs    = "Legs"
    case core    = "Core"
    case cardio  = "Cardio"
    case olympic = "Olympic"
    case custom  = "Custom"
}

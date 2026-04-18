import Foundation
import SwiftData

final class ExerciseLibrary {
    static let shared = ExerciseLibrary()
    private init() {}

    func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom })
        guard let existing = try? context.fetch(descriptor), existing.isEmpty else { return }
        for entry in builtInExercises {
            let ex = Exercise(name: entry.name, category: entry.category, equipment: entry.equipment, isCustom: false)
            context.insert(ex)
        }
        try? context.save()
    }

    private struct LibraryEntry {
        let name: String
        let category: ExerciseCategory
        let equipment: Equipment?
    }

    // swiftlint:disable function_body_length
    private let builtInExercises: [LibraryEntry] = [
        // Push
        LibraryEntry(name: "Bench Press",            category: .push, equipment: .barbell),
        LibraryEntry(name: "Incline Bench Press",    category: .push, equipment: .barbell),
        LibraryEntry(name: "Decline Bench Press",    category: .push, equipment: .barbell),
        LibraryEntry(name: "Dumbbell Press",         category: .push, equipment: .dumbbell),
        LibraryEntry(name: "Incline Dumbbell Press", category: .push, equipment: .dumbbell),
        LibraryEntry(name: "Shoulder Press",         category: .push, equipment: .barbell),
        LibraryEntry(name: "Dumbbell Shoulder Press",category: .push, equipment: .dumbbell),
        LibraryEntry(name: "Push-Up",                category: .push, equipment: .bodyweight),
        LibraryEntry(name: "Dips",                   category: .push, equipment: .bodyweight),
        LibraryEntry(name: "Tricep Pushdown",        category: .push, equipment: .cable),
        LibraryEntry(name: "Skull Crushers",         category: .push, equipment: .barbell),
        LibraryEntry(name: "Overhead Tricep Extension", category: .push, equipment: .dumbbell),
        LibraryEntry(name: "Lateral Raises",         category: .push, equipment: .dumbbell),
        LibraryEntry(name: "Front Raises",           category: .push, equipment: .dumbbell),
        LibraryEntry(name: "Cable Fly",              category: .push, equipment: .cable),
        // Pull
        LibraryEntry(name: "Pull-Up",                category: .pull, equipment: .bodyweight),
        LibraryEntry(name: "Chin-Up",                category: .pull, equipment: .bodyweight),
        LibraryEntry(name: "Barbell Row",            category: .pull, equipment: .barbell),
        LibraryEntry(name: "Dumbbell Row",           category: .pull, equipment: .dumbbell),
        LibraryEntry(name: "Seated Cable Row",       category: .pull, equipment: .cable),
        LibraryEntry(name: "Lat Pulldown",           category: .pull, equipment: .cable),
        LibraryEntry(name: "Face Pull",              category: .pull, equipment: .cable),
        LibraryEntry(name: "Bicep Curl",             category: .pull, equipment: .barbell),
        LibraryEntry(name: "Dumbbell Curl",          category: .pull, equipment: .dumbbell),
        LibraryEntry(name: "Hammer Curl",            category: .pull, equipment: .dumbbell),
        LibraryEntry(name: "Preacher Curl",          category: .pull, equipment: .machine),
        LibraryEntry(name: "Cable Curl",             category: .pull, equipment: .cable),
        LibraryEntry(name: "T-Bar Row",              category: .pull, equipment: .barbell),
        LibraryEntry(name: "Deadlift",               category: .pull, equipment: .barbell),
        // Legs
        LibraryEntry(name: "Back Squat",             category: .legs, equipment: .barbell),
        LibraryEntry(name: "Front Squat",            category: .legs, equipment: .barbell),
        LibraryEntry(name: "Goblet Squat",           category: .legs, equipment: .kettlebell),
        LibraryEntry(name: "Romanian Deadlift",      category: .legs, equipment: .barbell),
        LibraryEntry(name: "Leg Press",              category: .legs, equipment: .machine),
        LibraryEntry(name: "Leg Extension",          category: .legs, equipment: .machine),
        LibraryEntry(name: "Leg Curl",               category: .legs, equipment: .machine),
        LibraryEntry(name: "Calf Raise",             category: .legs, equipment: .machine),
        LibraryEntry(name: "Lunge",                  category: .legs, equipment: .dumbbell),
        LibraryEntry(name: "Bulgarian Split Squat",  category: .legs, equipment: .dumbbell),
        LibraryEntry(name: "Hip Thrust",             category: .legs, equipment: .barbell),
        LibraryEntry(name: "Sumo Deadlift",          category: .legs, equipment: .barbell),
        LibraryEntry(name: "Step-Up",                category: .legs, equipment: .dumbbell),
        // Core
        LibraryEntry(name: "Plank",                  category: .core, equipment: .bodyweight),
        LibraryEntry(name: "Crunches",               category: .core, equipment: .bodyweight),
        LibraryEntry(name: "Sit-Up",                 category: .core, equipment: .bodyweight),
        LibraryEntry(name: "Russian Twist",          category: .core, equipment: .ball),
        LibraryEntry(name: "Leg Raise",              category: .core, equipment: .bodyweight),
        LibraryEntry(name: "Cable Crunch",           category: .core, equipment: .cable),
        LibraryEntry(name: "Ab Wheel Rollout",       category: .core, equipment: .other),
        LibraryEntry(name: "Hanging Leg Raise",      category: .core, equipment: .bodyweight),
        LibraryEntry(name: "Side Plank",             category: .core, equipment: .bodyweight),
        // Cardio
        LibraryEntry(name: "Burpees",                category: .cardio, equipment: .bodyweight),
        LibraryEntry(name: "Box Jump",               category: .cardio, equipment: .other),
        LibraryEntry(name: "Mountain Climbers",      category: .cardio, equipment: .bodyweight),
        LibraryEntry(name: "Jump Rope",              category: .cardio, equipment: .other),
        LibraryEntry(name: "Rowing",                 category: .cardio, equipment: .machine),
        LibraryEntry(name: "Assault Bike",           category: .cardio, equipment: .machine),
        LibraryEntry(name: "Treadmill Run",          category: .cardio, equipment: .machine),
        // Olympic
        LibraryEntry(name: "Clean and Jerk",         category: .olympic, equipment: .barbell),
        LibraryEntry(name: "Snatch",                 category: .olympic, equipment: .barbell),
        LibraryEntry(name: "Power Clean",            category: .olympic, equipment: .barbell),
        LibraryEntry(name: "Push Press",             category: .olympic, equipment: .barbell),
        LibraryEntry(name: "Hang Power Clean",       category: .olympic, equipment: .barbell),
        LibraryEntry(name: "Thruster",               category: .olympic, equipment: .barbell),
    ]
}

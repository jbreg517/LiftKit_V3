import Foundation
import SwiftData

final class ExerciseLibrary {
    static let shared = ExerciseLibrary()
    private init() {}

    /// Exercises that are tracked by hold time rather than reps by default.
    static let timedExerciseNames: Set<String> = [
        "plank", "side plank", "wall sit", "dead hang", "hollow hold", "l-sit",
    ]

    /// Whether a freshly named exercise should default to time-based tracking.
    static func isTimedByDefault(_ name: String) -> Bool {
        timedExerciseNames.contains(name.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// Primary muscle for a known library exercise name (nil if not in the library).
    static func defaultMuscle(forName name: String) -> MuscleGroup? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return shared.builtInExercises.first { $0.name.lowercased() == lower }?.muscle
    }

    func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom })
        guard let existing = try? context.fetch(descriptor), existing.isEmpty else { return }
        for entry in builtInExercises {
            let ex = Exercise(name: entry.name, category: entry.category, equipment: entry.equipment, isCustom: false)
            ex.primaryMuscle = entry.muscle
            context.insert(ex)
        }
        try? context.save()
    }

    /// Fills in primary muscle for existing exercises (library + matching customs)
    /// that predate muscle tagging. Safe to call on every launch.
    func backfillMuscles(context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Exercise>()) else { return }
        let map = Dictionary(builtInExercises.map { ($0.name.lowercased(), $0.muscle) },
                             uniquingKeysWith: { a, _ in a })
        var changed = false
        for ex in all where ex.primaryMuscle == nil {
            if let m = map[ex.name.lowercased()] {
                ex.primaryMuscle = m
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    private struct LibraryEntry {
        let name: String
        let category: ExerciseCategory
        let equipment: Equipment?
        let muscle: MuscleGroup
    }

    // swiftlint:disable function_body_length
    private let builtInExercises: [LibraryEntry] = [
        // Push
        LibraryEntry(name: "Bench Press",            category: .push, equipment: .barbell,   muscle: .chest),
        LibraryEntry(name: "Incline Bench Press",    category: .push, equipment: .barbell,   muscle: .chest),
        LibraryEntry(name: "Decline Bench Press",    category: .push, equipment: .barbell,   muscle: .chest),
        LibraryEntry(name: "Dumbbell Press",         category: .push, equipment: .dumbbell,  muscle: .chest),
        LibraryEntry(name: "Incline Dumbbell Press", category: .push, equipment: .dumbbell,  muscle: .chest),
        LibraryEntry(name: "Shoulder Press",         category: .push, equipment: .barbell,   muscle: .shoulders),
        LibraryEntry(name: "Dumbbell Shoulder Press",category: .push, equipment: .dumbbell,  muscle: .shoulders),
        LibraryEntry(name: "Push-Up",                category: .push, equipment: .bodyweight,muscle: .chest),
        LibraryEntry(name: "Dips",                   category: .push, equipment: .bodyweight,muscle: .chest),
        LibraryEntry(name: "Tricep Pushdown",        category: .push, equipment: .cable,     muscle: .triceps),
        LibraryEntry(name: "Skull Crushers",         category: .push, equipment: .barbell,   muscle: .triceps),
        LibraryEntry(name: "Overhead Tricep Extension", category: .push, equipment: .dumbbell, muscle: .triceps),
        LibraryEntry(name: "Lateral Raises",         category: .push, equipment: .dumbbell,  muscle: .shoulders),
        LibraryEntry(name: "Front Raises",           category: .push, equipment: .dumbbell,  muscle: .shoulders),
        LibraryEntry(name: "Cable Fly",              category: .push, equipment: .cable,     muscle: .chest),
        // Pull
        LibraryEntry(name: "Pull-Up",                category: .pull, equipment: .bodyweight,muscle: .back),
        LibraryEntry(name: "Chin-Up",                category: .pull, equipment: .bodyweight,muscle: .back),
        LibraryEntry(name: "Barbell Row",            category: .pull, equipment: .barbell,   muscle: .back),
        LibraryEntry(name: "Dumbbell Row",           category: .pull, equipment: .dumbbell,  muscle: .back),
        LibraryEntry(name: "Seated Cable Row",       category: .pull, equipment: .cable,     muscle: .back),
        LibraryEntry(name: "Lat Pulldown",           category: .pull, equipment: .cable,     muscle: .back),
        LibraryEntry(name: "Face Pull",              category: .pull, equipment: .cable,     muscle: .back),
        LibraryEntry(name: "Bicep Curl",             category: .pull, equipment: .barbell,   muscle: .biceps),
        LibraryEntry(name: "Dumbbell Curl",          category: .pull, equipment: .dumbbell,  muscle: .biceps),
        LibraryEntry(name: "Hammer Curl",            category: .pull, equipment: .dumbbell,  muscle: .biceps),
        LibraryEntry(name: "Preacher Curl",          category: .pull, equipment: .machine,   muscle: .biceps),
        LibraryEntry(name: "Cable Curl",             category: .pull, equipment: .cable,     muscle: .biceps),
        LibraryEntry(name: "T-Bar Row",              category: .pull, equipment: .barbell,   muscle: .back),
        LibraryEntry(name: "Deadlift",               category: .pull, equipment: .barbell,   muscle: .back),
        // Legs
        LibraryEntry(name: "Back Squat",             category: .legs, equipment: .barbell,   muscle: .quads),
        LibraryEntry(name: "Front Squat",            category: .legs, equipment: .barbell,   muscle: .quads),
        LibraryEntry(name: "Goblet Squat",           category: .legs, equipment: .kettlebell,muscle: .quads),
        LibraryEntry(name: "Romanian Deadlift",      category: .legs, equipment: .barbell,   muscle: .hamstrings),
        LibraryEntry(name: "Leg Press",              category: .legs, equipment: .machine,   muscle: .quads),
        LibraryEntry(name: "Leg Extension",          category: .legs, equipment: .machine,   muscle: .quads),
        LibraryEntry(name: "Leg Curl",               category: .legs, equipment: .machine,   muscle: .hamstrings),
        LibraryEntry(name: "Calf Raise",             category: .legs, equipment: .machine,   muscle: .calves),
        LibraryEntry(name: "Lunge",                  category: .legs, equipment: .dumbbell,  muscle: .quads),
        LibraryEntry(name: "Bulgarian Split Squat",  category: .legs, equipment: .dumbbell,  muscle: .quads),
        LibraryEntry(name: "Hip Thrust",             category: .legs, equipment: .barbell,   muscle: .glutes),
        LibraryEntry(name: "Sumo Deadlift",          category: .legs, equipment: .barbell,   muscle: .glutes),
        LibraryEntry(name: "Step-Up",                category: .legs, equipment: .dumbbell,  muscle: .quads),
        // Core
        LibraryEntry(name: "Plank",                  category: .core, equipment: .bodyweight,muscle: .core),
        LibraryEntry(name: "Crunches",               category: .core, equipment: .bodyweight,muscle: .core),
        LibraryEntry(name: "Sit-Up",                 category: .core, equipment: .bodyweight,muscle: .core),
        LibraryEntry(name: "Russian Twist",          category: .core, equipment: .other,     muscle: .core),
        LibraryEntry(name: "Leg Raise",              category: .core, equipment: .bodyweight,muscle: .core),
        LibraryEntry(name: "Cable Crunch",           category: .core, equipment: .cable,     muscle: .core),
        LibraryEntry(name: "Ab Wheel Rollout",       category: .core, equipment: .other,     muscle: .core),
        LibraryEntry(name: "Hanging Leg Raise",      category: .core, equipment: .bodyweight,muscle: .core),
        LibraryEntry(name: "Side Plank",             category: .core, equipment: .bodyweight,muscle: .core),
        LibraryEntry(name: "Wall Sit",               category: .core, equipment: .bodyweight,muscle: .quads),
        LibraryEntry(name: "Dead Hang",              category: .core, equipment: .bodyweight,muscle: .back),
        LibraryEntry(name: "Hollow Hold",            category: .core, equipment: .bodyweight,muscle: .core),
        // Cardio
        LibraryEntry(name: "Burpees",                category: .cardio, equipment: .bodyweight,muscle: .fullBody),
        LibraryEntry(name: "Box Jump",               category: .cardio, equipment: .other,     muscle: .fullBody),
        LibraryEntry(name: "Mountain Climbers",      category: .cardio, equipment: .bodyweight,muscle: .fullBody),
        LibraryEntry(name: "Jump Rope",              category: .cardio, equipment: .other,     muscle: .fullBody),
        LibraryEntry(name: "Rowing",                 category: .cardio, equipment: .machine,   muscle: .fullBody),
        LibraryEntry(name: "Assault Bike",           category: .cardio, equipment: .machine,   muscle: .fullBody),
        LibraryEntry(name: "Treadmill Run",          category: .cardio, equipment: .machine,   muscle: .fullBody),
        // Olympic
        LibraryEntry(name: "Clean and Jerk",         category: .olympic, equipment: .barbell,  muscle: .fullBody),
        LibraryEntry(name: "Snatch",                 category: .olympic, equipment: .barbell,  muscle: .fullBody),
        LibraryEntry(name: "Power Clean",            category: .olympic, equipment: .barbell,  muscle: .fullBody),
        LibraryEntry(name: "Push Press",             category: .olympic, equipment: .barbell,  muscle: .shoulders),
        LibraryEntry(name: "Hang Power Clean",       category: .olympic, equipment: .barbell,  muscle: .fullBody),
        LibraryEntry(name: "Thruster",               category: .olympic, equipment: .barbell,  muscle: .fullBody),
    ]
}

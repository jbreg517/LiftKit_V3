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

    /// Secondary muscles for a known library exercise name (empty if none / unknown).
    static func defaultSecondaries(forName name: String) -> [MuscleGroup] {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return shared.builtInExercises.first { $0.name.lowercased() == lower }?.secondary ?? []
    }

    func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom })
        guard let existing = try? context.fetch(descriptor), existing.isEmpty else { return }
        for entry in builtInExercises {
            let ex = Exercise(name: entry.name, category: entry.category, equipment: entry.equipment, isCustom: false)
            ex.primaryMuscle = entry.muscle
            ex.secondaryMuscles = entry.secondary
            context.insert(ex)
        }
        try? context.save()
    }

    /// Fills in muscle tags for existing exercises (library seeds + matching
    /// customs) that predate multi-muscle tagging. Safe to call on every launch.
    func backfillMuscles(context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Exercise>()) else { return }
        var changed = false

        // Insert library exercises added in app updates (existing installs were
        // seeded before these were added, so seedIfNeeded won't re-run).
        if !all.isEmpty {
            let existingNames = Set(all.map { $0.name.lowercased() })
            for entry in builtInExercises where !existingNames.contains(entry.name.lowercased()) {
                let ex = Exercise(name: entry.name, category: entry.category, equipment: entry.equipment, isCustom: false)
                ex.primaryMuscle = entry.muscle
                ex.secondaryMuscles = entry.secondary
                context.insert(ex)
                changed = true
            }
        }

        let map = Dictionary(builtInExercises.map { ($0.name.lowercased(), $0) },
                             uniquingKeysWith: { a, _ in a })
        for ex in all {
            guard let entry = map[ex.name.lowercased()] else { continue }
            if ex.primaryMuscle == nil {
                ex.primaryMuscle = entry.muscle
                changed = true
            }
            if ex.secondaryMuscles.isEmpty && !entry.secondary.isEmpty {
                ex.secondaryMuscles = entry.secondary
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
        var secondary: [MuscleGroup] = []
    }

    // swiftlint:disable function_body_length
    private let builtInExercises: [LibraryEntry] = [
        // Push
        LibraryEntry(name: "Bench Press",            category: .push, equipment: .barbell,   muscle: .chest, secondary: [.shoulders, .triceps]),
        LibraryEntry(name: "Incline Bench Press",    category: .push, equipment: .barbell,   muscle: .chest, secondary: [.shoulders, .triceps]),
        LibraryEntry(name: "Decline Bench Press",    category: .push, equipment: .barbell,   muscle: .chest, secondary: [.triceps]),
        LibraryEntry(name: "Close-Grip Bench Press", category: .push, equipment: .barbell,   muscle: .triceps, secondary: [.chest]),
        LibraryEntry(name: "Dumbbell Press",         category: .push, equipment: .dumbbell,  muscle: .chest, secondary: [.shoulders, .triceps]),
        LibraryEntry(name: "Incline Dumbbell Press", category: .push, equipment: .dumbbell,  muscle: .chest, secondary: [.shoulders, .triceps]),
        LibraryEntry(name: "Chest Press Machine",    category: .push, equipment: .machine,   muscle: .chest, secondary: [.triceps]),
        LibraryEntry(name: "Pec Deck",               category: .push, equipment: .machine,   muscle: .chest),
        LibraryEntry(name: "Shoulder Press",         category: .push, equipment: .barbell,   muscle: .shoulders, secondary: [.triceps]),
        LibraryEntry(name: "Dumbbell Shoulder Press",category: .push, equipment: .dumbbell,  muscle: .shoulders, secondary: [.triceps]),
        LibraryEntry(name: "Shoulder Press Machine", category: .push, equipment: .machine,   muscle: .shoulders, secondary: [.triceps]),
        LibraryEntry(name: "Arnold Press",           category: .push, equipment: .dumbbell,  muscle: .shoulders, secondary: [.triceps]),
        LibraryEntry(name: "Push-Up",                category: .push, equipment: .bodyweight,muscle: .chest, secondary: [.shoulders, .triceps]),
        LibraryEntry(name: "Dips",                   category: .push, equipment: .bodyweight,muscle: .chest, secondary: [.triceps, .shoulders]),
        LibraryEntry(name: "Tricep Pushdown",        category: .push, equipment: .cable,     muscle: .triceps),
        LibraryEntry(name: "Skull Crushers",         category: .push, equipment: .barbell,   muscle: .triceps),
        LibraryEntry(name: "Overhead Tricep Extension", category: .push, equipment: .dumbbell, muscle: .triceps),
        LibraryEntry(name: "Lateral Raises",         category: .push, equipment: .dumbbell,  muscle: .shoulders),
        LibraryEntry(name: "Cable Lateral Raise",    category: .push, equipment: .cable,     muscle: .shoulders),
        LibraryEntry(name: "Front Raises",           category: .push, equipment: .dumbbell,  muscle: .shoulders),
        LibraryEntry(name: "Reverse Fly",            category: .push, equipment: .dumbbell,  muscle: .shoulders, secondary: [.back]),
        LibraryEntry(name: "Cable Fly",              category: .push, equipment: .cable,     muscle: .chest),
        // Pull
        LibraryEntry(name: "Pull-Up",                category: .pull, equipment: .bodyweight,muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Chin-Up",                category: .pull, equipment: .bodyweight,muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Assisted Pull-Up Machine", category: .pull, equipment: .machine, muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Barbell Row",            category: .pull, equipment: .barbell,   muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Dumbbell Row",           category: .pull, equipment: .dumbbell,  muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Seated Cable Row",       category: .pull, equipment: .cable,     muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Seated Row Machine",     category: .pull, equipment: .machine,   muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Lat Pulldown",           category: .pull, equipment: .cable,     muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Face Pull",              category: .pull, equipment: .cable,     muscle: .shoulders, secondary: [.back]),
        LibraryEntry(name: "Bicep Curl",             category: .pull, equipment: .barbell,   muscle: .biceps),
        LibraryEntry(name: "Dumbbell Curl",          category: .pull, equipment: .dumbbell,  muscle: .biceps),
        LibraryEntry(name: "Hammer Curl",            category: .pull, equipment: .dumbbell,  muscle: .biceps),
        LibraryEntry(name: "Preacher Curl",          category: .pull, equipment: .machine,   muscle: .biceps),
        LibraryEntry(name: "Cable Curl",             category: .pull, equipment: .cable,     muscle: .biceps),
        LibraryEntry(name: "Shrug",                  category: .pull, equipment: .dumbbell,  muscle: .back),
        LibraryEntry(name: "T-Bar Row",              category: .pull, equipment: .barbell,   muscle: .back, secondary: [.biceps]),
        LibraryEntry(name: "Deadlift",               category: .pull, equipment: .barbell,   muscle: .back, secondary: [.hamstrings, .glutes]),
        // Legs
        LibraryEntry(name: "Back Squat",             category: .legs, equipment: .barbell,   muscle: .quads, secondary: [.glutes, .hamstrings]),
        LibraryEntry(name: "Front Squat",            category: .legs, equipment: .barbell,   muscle: .quads, secondary: [.glutes, .core]),
        LibraryEntry(name: "Hack Squat",             category: .legs, equipment: .machine,   muscle: .quads, secondary: [.glutes]),
        LibraryEntry(name: "Goblet Squat",           category: .legs, equipment: .kettlebell,muscle: .quads, secondary: [.glutes]),
        LibraryEntry(name: "Romanian Deadlift",      category: .legs, equipment: .barbell,   muscle: .hamstrings, secondary: [.glutes, .back]),
        LibraryEntry(name: "Good Morning",           category: .legs, equipment: .barbell,   muscle: .hamstrings, secondary: [.glutes, .back]),
        LibraryEntry(name: "Leg Press",              category: .legs, equipment: .machine,   muscle: .quads, secondary: [.glutes]),
        LibraryEntry(name: "Leg Extension",          category: .legs, equipment: .machine,   muscle: .quads),
        LibraryEntry(name: "Leg Curl",               category: .legs, equipment: .machine,   muscle: .hamstrings),
        LibraryEntry(name: "Calf Raise",             category: .legs, equipment: .machine,   muscle: .calves),
        LibraryEntry(name: "Seated Calf Raise",      category: .legs, equipment: .machine,   muscle: .calves),
        LibraryEntry(name: "Lunge",                  category: .legs, equipment: .dumbbell,  muscle: .quads, secondary: [.glutes, .hamstrings]),
        LibraryEntry(name: "Bulgarian Split Squat",  category: .legs, equipment: .dumbbell,  muscle: .quads, secondary: [.glutes]),
        LibraryEntry(name: "Hip Thrust",             category: .legs, equipment: .barbell,   muscle: .glutes, secondary: [.hamstrings]),
        LibraryEntry(name: "Glute Bridge",           category: .legs, equipment: .bodyweight,muscle: .glutes, secondary: [.hamstrings]),
        LibraryEntry(name: "Hip Abduction Machine",  category: .legs, equipment: .machine,   muscle: .glutes),
        LibraryEntry(name: "Sumo Deadlift",          category: .legs, equipment: .barbell,   muscle: .glutes, secondary: [.hamstrings, .back]),
        LibraryEntry(name: "Step-Up",                category: .legs, equipment: .dumbbell,  muscle: .quads, secondary: [.glutes]),
        // Kettlebell
        LibraryEntry(name: "Kettlebell Swing",       category: .legs, equipment: .kettlebell, muscle: .glutes, secondary: [.hamstrings, .back]),
        LibraryEntry(name: "Kettlebell Clean",       category: .olympic, equipment: .kettlebell, muscle: .fullBody, secondary: [.glutes, .shoulders]),
        LibraryEntry(name: "Kettlebell Snatch",      category: .olympic, equipment: .kettlebell, muscle: .fullBody, secondary: [.shoulders, .glutes]),
        LibraryEntry(name: "Kettlebell Press",       category: .push, equipment: .kettlebell, muscle: .shoulders, secondary: [.triceps]),
        LibraryEntry(name: "Kettlebell Front Squat", category: .legs, equipment: .kettlebell, muscle: .quads, secondary: [.glutes, .core]),
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

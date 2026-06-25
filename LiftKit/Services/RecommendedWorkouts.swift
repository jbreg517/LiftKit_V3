import Foundation

// MARK: - Tagging taxonomies (also reused by future muscle-volume analytics)

enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves, core
    case fullBody, other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .chest:      return "Chest"
        case .back:       return "Back"
        case .shoulders:  return "Shoulders"
        case .biceps:     return "Biceps"
        case .triceps:    return "Triceps"
        case .quads:      return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes:     return "Glutes"
        case .calves:     return "Calves"
        case .core:       return "Core"
        case .fullBody:   return "Full Body"
        case .other:      return "Other"
        }
    }
}

enum WorkoutPurpose: String, CaseIterable, Identifiable {
    case mobility, strength, muscleGrowth, weightLoss

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mobility:     return "Mobility"
        case .strength:     return "Strength"
        case .muscleGrowth: return "Muscle Growth"
        case .weightLoss:   return "Weight Loss"
        }
    }
}

// MARK: - Catalog value types

struct RecExercise {
    var name: String
    var equipment: Equipment = .none
    var sets: Int = 3
    var reps: Int = 10
    var isTimed: Bool = false
    var durationSeconds: Int = 60
}

struct RecSession {
    var name: String
    var equipment: Equipment = .none
    var reps: Int = 10
}

struct RecommendedWorkout: Identifiable {
    let id: String
    let name: String
    let type: TimerType
    let blurb: String
    let purposes: [WorkoutPurpose]
    let muscles: [MuscleGroup]

    var exercises: [RecExercise] = []     // .reps
    var sessions: [RecSession] = []       // .amrap/.emom/.forTime/.intervals/.manual
    var restBetweenSets: Int = 90         // .reps
    var timeCapMinutes: Int = 10          // .amrap/.forTime
    var emomMinutes: Int = 12             // .emom
    var work: Int = 20                    // .intervals
    var rest: Int = 10                    // .intervals
    var rounds: Int = 8                   // .intervals
}

// MARK: - The catalog

enum RecommendedWorkouts {
    static let all: [RecommendedWorkout] = [
        RecommendedWorkout(
            id: "barbell-5x5-a", name: "Barbell 5×5 — A", type: .reps,
            blurb: "Classic strength: squat, bench, row.",
            purposes: [.strength], muscles: [.quads, .chest, .back],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 5, reps: 5),
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 5, reps: 5),
                RecExercise(name: "Barbell Row", equipment: .barbell, sets: 5, reps: 5),
            ],
            restBetweenSets: 180
        ),
        RecommendedWorkout(
            id: "barbell-5x5-b", name: "Barbell 5×5 — B", type: .reps,
            blurb: "Alternates with A: squat, press, deadlift.",
            purposes: [.strength], muscles: [.quads, .shoulders, .back, .hamstrings],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 5, reps: 5),
                RecExercise(name: "Overhead Press", equipment: .barbell, sets: 5, reps: 5),
                RecExercise(name: "Deadlift", equipment: .barbell, sets: 1, reps: 5),
            ],
            restBetweenSets: 180
        ),
        RecommendedWorkout(
            id: "db-hypertrophy-upper", name: "Dumbbell Upper", type: .reps,
            blurb: "Hypertrophy-focused upper body.",
            purposes: [.muscleGrowth], muscles: [.chest, .back, .shoulders, .biceps, .triceps],
            exercises: [
                RecExercise(name: "Dumbbell Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Shoulder Press", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Hammer Curl", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Overhead Tricep Extension", equipment: .dumbbell, sets: 3, reps: 12),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "bodyweight-full-body", name: "Bodyweight Full Body", type: .reps,
            blurb: "No equipment full-body circuit.",
            purposes: [.muscleGrowth, .weightLoss], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Push-Up", equipment: .bodyweight, sets: 3, reps: 12),
                RecExercise(name: "Bodyweight Squat", equipment: .bodyweight, sets: 3, reps: 20),
                RecExercise(name: "Lunge", equipment: .bodyweight, sets: 3, reps: 10),
                RecExercise(name: "Plank", equipment: .bodyweight, sets: 3, reps: 1, isTimed: true, durationSeconds: 45),
                RecExercise(name: "Sit-Up", equipment: .bodyweight, sets: 3, reps: 15),
            ],
            restBetweenSets: 60
        ),
        RecommendedWorkout(
            id: "kb-emom-12", name: "Kettlebell EMOM 12", type: .emom,
            blurb: "Every minute, 12 min — alternate swings & clean-press.",
            purposes: [.strength, .weightLoss], muscles: [.fullBody, .glutes],
            sessions: [
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 15),
                RecSession(name: "Kettlebell Clean & Press", equipment: .kettlebell, reps: 8),
            ],
            emomMinutes: 12
        ),
        RecommendedWorkout(
            id: "kb-amrap-20", name: "Kettlebell AMRAP 20", type: .amrap,
            blurb: "As many rounds as possible in 20 min.",
            purposes: [.weightLoss, .muscleGrowth], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Kettlebell Snatch", equipment: .kettlebell, reps: 10),
                RecSession(name: "Kettlebell Front Squat", equipment: .kettlebell, reps: 10),
                RecSession(name: "Kettlebell Push Press", equipment: .kettlebell, reps: 10),
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 20),
            ],
            timeCapMinutes: 20
        ),
        RecommendedWorkout(
            id: "kb-chipper", name: "Kettlebell Chipper", type: .forTime,
            blurb: "Work down the list for time (cap 20 min).",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 50),
                RecSession(name: "Goblet Squat", equipment: .kettlebell, reps: 40),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 30),
                RecSession(name: "Kettlebell Clean & Press", equipment: .kettlebell, reps: 20),
                RecSession(name: "Burpees", equipment: .bodyweight, reps: 10),
            ],
            timeCapMinutes: 20
        ),
        RecommendedWorkout(
            id: "tabata-full-body", name: "Tabata Full Body", type: .intervals,
            blurb: "20s work / 10s rest × 8, cycling four moves.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Bodyweight Squat", equipment: .bodyweight),
                RecSession(name: "Push-Up", equipment: .bodyweight),
                RecSession(name: "Mountain Climbers", equipment: .bodyweight),
                RecSession(name: "Plank", equipment: .bodyweight),
            ],
            work: 20, rest: 10, rounds: 8
        ),
        RecommendedWorkout(
            id: "daily-mobility", name: "Daily Mobility", type: .reps,
            blurb: "Timed mobility holds to loosen up.",
            purposes: [.mobility], muscles: [.fullBody, .core],
            exercises: [
                RecExercise(name: "Cat-Cow", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
                RecExercise(name: "World's Greatest Stretch", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Hip Flexor Stretch", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Thoracic Rotation", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Deep Squat Hold", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
            ],
            restBetweenSets: 15
        ),
    ]
}

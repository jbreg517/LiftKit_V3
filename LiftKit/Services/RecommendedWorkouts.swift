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

        // MARK: Push / Pull / Legs (hypertrophy split)
        RecommendedWorkout(
            id: "ppl-push", name: "Push Day", type: .reps,
            blurb: "Chest, shoulders & triceps volume.",
            purposes: [.muscleGrowth], muscles: [.chest, .shoulders, .triceps],
            exercises: [
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 4, reps: 8),
                RecExercise(name: "Incline Dumbbell Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Shoulder Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Lateral Raises", equipment: .dumbbell, sets: 3, reps: 15),
                RecExercise(name: "Tricep Pushdown", equipment: .cable, sets: 3, reps: 12),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "ppl-pull", name: "Pull Day", type: .reps,
            blurb: "Back & biceps, vertical and horizontal pulls.",
            purposes: [.muscleGrowth], muscles: [.back, .biceps],
            exercises: [
                RecExercise(name: "Deadlift", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Pull-Up", equipment: .bodyweight, sets: 3, reps: 8),
                RecExercise(name: "Barbell Row", equipment: .barbell, sets: 3, reps: 10),
                RecExercise(name: "Lat Pulldown", equipment: .cable, sets: 3, reps: 12),
                RecExercise(name: "Bicep Curl", equipment: .barbell, sets: 3, reps: 12),
                RecExercise(name: "Face Pull", equipment: .cable, sets: 3, reps: 15),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "ppl-legs", name: "Leg Day", type: .reps,
            blurb: "Quads, hamstrings, glutes & calves.",
            purposes: [.muscleGrowth, .strength], muscles: [.quads, .hamstrings, .glutes, .calves],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 4, reps: 8),
                RecExercise(name: "Romanian Deadlift", equipment: .barbell, sets: 3, reps: 10),
                RecExercise(name: "Leg Press", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Leg Curl", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Calf Raise", equipment: .machine, sets: 4, reps: 15),
            ],
            restBetweenSets: 120
        ),

        // MARK: Upper / Lower (strength split)
        RecommendedWorkout(
            id: "upper-strength", name: "Upper Body Strength", type: .reps,
            blurb: "Heavy presses and pulls.",
            purposes: [.strength], muscles: [.chest, .back, .shoulders],
            exercises: [
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 4, reps: 6),
                RecExercise(name: "Barbell Row", equipment: .barbell, sets: 4, reps: 6),
                RecExercise(name: "Overhead Press", equipment: .barbell, sets: 3, reps: 8),
                RecExercise(name: "Pull-Up", equipment: .bodyweight, sets: 3, reps: 8),
            ],
            restBetweenSets: 150
        ),
        RecommendedWorkout(
            id: "lower-strength", name: "Lower Body Strength", type: .reps,
            blurb: "Squat-and-hinge lower strength.",
            purposes: [.strength], muscles: [.quads, .hamstrings, .glutes],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 4, reps: 6),
                RecExercise(name: "Romanian Deadlift", equipment: .barbell, sets: 3, reps: 8),
                RecExercise(name: "Lunge", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Calf Raise", equipment: .machine, sets: 4, reps: 12),
            ],
            restBetweenSets: 150
        ),

        // MARK: Kettlebell complexes & finishers (from Chronicles of Strength)
        RecommendedWorkout(
            id: "kb-great-destroyer", name: "The Great Destroyer", type: .reps,
            blurb: "Double-KB complex, 10 reps each — don’t set the bells down. 2 rounds.",
            purposes: [.strength, .weightLoss], muscles: [.fullBody, .glutes, .shoulders, .back],
            exercises: [
                RecExercise(name: "Double Kettlebell Swing", equipment: .kettlebell, sets: 2, reps: 10),
                RecExercise(name: "Double Kettlebell Snatch", equipment: .kettlebell, sets: 2, reps: 10),
                RecExercise(name: "Double Kettlebell Front Squat", equipment: .kettlebell, sets: 2, reps: 10),
                RecExercise(name: "Double Kettlebell Clean & Press", equipment: .kettlebell, sets: 2, reps: 10),
                RecExercise(name: "Push-Up", equipment: .bodyweight, sets: 2, reps: 10),
                RecExercise(name: "Bent-Over Row", equipment: .kettlebell, sets: 2, reps: 10),
            ],
            restBetweenSets: 120
        ),
        RecommendedWorkout(
            id: "kb-fibonacci-finisher", name: "Fibonacci Finisher", type: .forTime,
            blurb: "5 rounds in 10 min: 8-5-3-2 reps, then a 1-min plank.",
            purposes: [.weightLoss], muscles: [.fullBody, .core],
            sessions: [
                RecSession(name: "Double Kettlebell Clean", equipment: .kettlebell, reps: 8),
                RecSession(name: "Kettlebell Front Squat", equipment: .kettlebell, reps: 5),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 3),
                RecSession(name: "Renegade Row", equipment: .kettlebell, reps: 2),
                RecSession(name: "Plank (1 min)", equipment: .bodyweight, reps: 1),
            ],
            timeCapMinutes: 10
        ),
        RecommendedWorkout(
            id: "kb-armor-building", name: "Armor Building Complex", type: .emom,
            blurb: "Heavy double-KB EMOM: clean, press, front squats.",
            purposes: [.strength], muscles: [.fullBody, .shoulders, .quads],
            sessions: [
                RecSession(name: "Double Kettlebell Clean", equipment: .kettlebell, reps: 2),
                RecSession(name: "Double Kettlebell Press", equipment: .kettlebell, reps: 1),
                RecSession(name: "Double Kettlebell Front Squat", equipment: .kettlebell, reps: 3),
            ],
            emomMinutes: 10
        ),
        RecommendedWorkout(
            id: "kb-single-finisher", name: "Single Kettlebell Finisher", type: .amrap,
            blurb: "AMRAP 15: 3 reps each of swing, snatch, press, squat.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "One-Arm Kettlebell Swing", equipment: .kettlebell, reps: 3),
                RecSession(name: "Kettlebell Snatch", equipment: .kettlebell, reps: 3),
                RecSession(name: "Kettlebell Press", equipment: .kettlebell, reps: 3),
                RecSession(name: "Kettlebell Squat", equipment: .kettlebell, reps: 3),
            ],
            timeCapMinutes: 15
        ),
        RecommendedWorkout(
            id: "dumbbell-complex", name: "Dumbbell Complex", type: .reps,
            blurb: "Six moves, one pair of dumbbells, 4 rounds.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Dumbbell Romanian Deadlift", equipment: .dumbbell, sets: 4, reps: 8),
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 4, reps: 8),
                RecExercise(name: "Dumbbell Clean", equipment: .dumbbell, sets: 4, reps: 6),
                RecExercise(name: "Dumbbell Front Squat", equipment: .dumbbell, sets: 4, reps: 8),
                RecExercise(name: "Dumbbell Push Press", equipment: .dumbbell, sets: 4, reps: 6),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "bodyweight-finisher", name: "Bodyweight Finisher", type: .amrap,
            blurb: "No-equipment 6-minute AMRAP.",
            purposes: [.weightLoss], muscles: [.fullBody, .quads, .core],
            sessions: [
                RecSession(name: "Jump Squat", equipment: .bodyweight, reps: 10),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 10),
                RecSession(name: "Mountain Climbers", equipment: .bodyweight, reps: 20),
            ],
            timeCapMinutes: 6
        ),

        // MARK: Extra mobility options (used for recovery recommendations)
        RecommendedWorkout(
            id: "lower-mobility", name: "Lower Body Mobility", type: .reps,
            blurb: "Loosen hips, hamstrings and ankles.",
            purposes: [.mobility], muscles: [.quads, .hamstrings, .glutes, .calves],
            exercises: [
                RecExercise(name: "Deep Squat Hold", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
                RecExercise(name: "Hip Flexor Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Hamstring Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Ankle Rocks", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Glute Bridge Hold", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 15
        ),
        RecommendedWorkout(
            id: "upper-mobility", name: "Shoulder & Upper Mobility", type: .reps,
            blurb: "Open up shoulders, chest and t-spine.",
            purposes: [.mobility], muscles: [.shoulders, .chest, .back],
            exercises: [
                RecExercise(name: "Thoracic Rotation", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Shoulder Dislocates", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Doorway Chest Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Wall Slides", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Neck CARs", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 15
        ),
    ]
}

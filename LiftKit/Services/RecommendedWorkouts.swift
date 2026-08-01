import Foundation
import SwiftData

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
    var forTimeRounds: Int = 1            // .forTime
    var emomMinutes: Int = 12             // .emom
    var work: Int = 20                    // .intervals
    var rest: Int = 10                    // .intervals
    var rounds: Int = 8                   // .intervals

    /// Optional credit for a workout adapted from a named coach/program. We use
    /// our own structure and wording (an exercise sequence isn't copyrightable),
    /// abstract branded program names, and surface an "Inspired by ___" link to
    /// the author's page rather than reproduce their material.
    var attribution: String? = nil        // e.g. "Dan John"
    var attributionURL: String? = nil     // e.g. "https://danjohn.net"
}

extension RecommendedWorkout {
    /// All equipment this workout uses (across exercises & sessions).
    var allEquipment: Set<Equipment> {
        var s = Set<Equipment>()
        for e in exercises { s.insert(e.equipment) }
        for sess in sessions { s.insert(sess.equipment) }
        return s
    }
    /// Equipment that must be owned (excludes gear-free items).
    var requiredEquipment: Set<Equipment> {
        allEquipment.filter { !EquipmentPrefs.alwaysAvailable($0) }
    }
    /// True when every required piece is in the available set.
    func isDoable(with available: Set<Equipment>) -> Bool {
        requiredEquipment.isSubset(of: available)
    }
    /// True when the workout uses the given equipment (for the chip filter).
    func uses(_ e: Equipment) -> Bool { allEquipment.contains(e) }

    /// The user's `WorkoutTemplate` materialised from this prebuilt workout —
    /// created once and reused (keyed on `recommendedSourceID`), so scheduling the
    /// same prebuilt twice doesn't duplicate it. This is what lets a prebuilt
    /// workout be scheduled exactly like a saved plan. Mirrors the mapping in
    /// `WorkoutViewModel.saveAsTemplate`.
    func materializedTemplate(in context: ModelContext) -> WorkoutTemplate {
        let sourceID = id
        if let existing = (try? context.fetch(FetchDescriptor<WorkoutTemplate>()))?
            .first(where: { $0.recommendedSourceID == sourceID }) {
            return existing
        }
        let template = WorkoutTemplate(name: name)
        template.recommendedSourceID = sourceID
        context.insert(template)

        if type == .reps {
            for (i, ex) in exercises.enumerated() {
                let te = TemplateExercise(
                    exerciseName: ex.name,
                    timerType: ex.isTimed ? .forTime : .reps,
                    targetSets: ex.sets,
                    targetReps: ex.reps,
                    targetDuration: ex.isTimed ? ex.durationSeconds : 0,
                    sortOrder: i,
                    equipment: ex.equipment == .none ? nil : ex.equipment)
                te.restSeconds = restBetweenSets
                te.template = template
                context.insert(te)
            }
        } else {
            for (i, s) in sessions.enumerated() {
                let te = TemplateExercise(
                    exerciseName: s.name,
                    timerType: type,
                    targetSets: 3,
                    targetReps: s.reps,
                    sortOrder: i,
                    equipment: s.equipment == .none ? nil : s.equipment)
                te.template = template
                context.insert(te)
            }
        }
        // Carry the workout's timings onto the plan so a scheduled prebuilt opens
        // with its real cap/rounds/work-rest, not defaults.
        var config = TimerConfig(type: type)
        switch type {
        case .amrap, .forTime:
            config.totalDuration = TimeInterval(timeCapMinutes * 60)
            if type == .forTime { config.forTimeRounds = max(1, forTimeRounds) }
        case .emom:
            config.rounds = emomMinutes
        case .intervals:
            config.workDuration = TimeInterval(work)
            config.restDuration = TimeInterval(rest)
            config.intervalRounds = rounds
        case .reps:
            config.restBetweenSets = TimeInterval(restBetweenSets)
        case .manual:
            break
        }
        template.storedConfig = config
        Persist.save(context)
        return template
    }
}

// MARK: - The catalog

enum RecommendedWorkouts {
    /// The full catalog surfaced to users.
    static let all: [RecommendedWorkout] = coreCatalog + expandedCatalog

    private static let coreCatalog: [RecommendedWorkout] = [
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

        // MARK: Kettlebell complexes & finishers
        // Structures adapted with original wording; branded program names are
        // abstracted and credited via "Inspired by" links (see attribution).
        RecommendedWorkout(
            id: "kb-great-destroyer", name: "Double-KB Grinder Complex", type: .reps,
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
            restBetweenSets: 120,
            attribution: "Pat Flynn", attributionURL: "https://chroniclesofstrength.com"
        ),
        RecommendedWorkout(
            id: "kb-fibonacci-finisher", name: "8-5-3-2 Ladder Finisher", type: .forTime,
            blurb: "5 rounds in 10 min: 8-5-3-2 reps, then a 1-min plank.",
            purposes: [.weightLoss], muscles: [.fullBody, .core],
            sessions: [
                RecSession(name: "Double Kettlebell Clean", equipment: .kettlebell, reps: 8),
                RecSession(name: "Kettlebell Front Squat", equipment: .kettlebell, reps: 5),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 3),
                RecSession(name: "Renegade Row", equipment: .kettlebell, reps: 2),
                RecSession(name: "Plank (1 min)", equipment: .bodyweight, reps: 1),
            ],
            timeCapMinutes: 10,
            attribution: "Pat Flynn", attributionURL: "https://chroniclesofstrength.com"
        ),
        RecommendedWorkout(
            id: "kb-armor-building", name: "KB Clean, Squat & Press Complex", type: .emom,
            blurb: "Heavy double-KB EMOM: clean, press, front squats.",
            purposes: [.strength], muscles: [.fullBody, .shoulders, .quads],
            sessions: [
                RecSession(name: "Double Kettlebell Clean", equipment: .kettlebell, reps: 2),
                RecSession(name: "Double Kettlebell Press", equipment: .kettlebell, reps: 1),
                RecSession(name: "Double Kettlebell Front Squat", equipment: .kettlebell, reps: 3),
            ],
            emomMinutes: 10,
            attribution: "Dan John", attributionURL: "https://danjohn.net"
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
            timeCapMinutes: 15,
            attribution: "Pat Flynn", attributionURL: "https://chroniclesofstrength.com"
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

    // MARK: - Expanded catalog
    // Structures are facts (an exercise sequence isn't copyrightable) rendered in
    // our own words. Community benchmark names (CrossFit "Girls"/Hero WODs) are
    // kept; living coaches' branded program names are abstracted and credited via
    // an "Inspired by" link (attribution / attributionURL).
    private static let expandedCatalog: [RecommendedWorkout] = [

        // MARK: CrossFit benchmark "Girls"
        RecommendedWorkout(
            id: "cf-fran", name: "Fran", type: .forTime,
            blurb: "Classic benchmark — 21-15-9 thrusters & pull-ups, for time.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody, .quads, .shoulders],
            sessions: [
                RecSession(name: "Thruster", equipment: .barbell, reps: 21),
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 21),
            ],
            timeCapMinutes: 10,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-cindy", name: "Cindy", type: .amrap,
            blurb: "AMRAP 20 — 5 pull-ups, 10 push-ups, 15 air squats.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 5),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 10),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 15),
            ],
            timeCapMinutes: 20,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-angie", name: "Angie", type: .forTime,
            blurb: "For time — 100 pull-ups, 100 push-ups, 100 sit-ups, 100 squats, in order.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 100),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 100),
                RecSession(name: "Sit-Up", equipment: .bodyweight, reps: 100),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 100),
            ],
            timeCapMinutes: 25,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-barbara", name: "Barbara", type: .forTime,
            blurb: "5 rounds for time — 20 pull-ups, 30 push-ups, 40 sit-ups, 50 squats.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 20),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 30),
                RecSession(name: "Sit-Up", equipment: .bodyweight, reps: 40),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 50),
            ],
            timeCapMinutes: 40, forTimeRounds: 5,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-chelsea", name: "Chelsea", type: .emom,
            blurb: "EMOM 30 — 5 pull-ups, 10 push-ups, 15 squats every minute.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 5),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 10),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 15),
            ],
            emomMinutes: 30,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-grace", name: "Grace", type: .forTime,
            blurb: "For time — 30 clean & jerks (135/95 lb).",
            purposes: [.strength, .weightLoss], muscles: [.fullBody, .shoulders],
            sessions: [
                RecSession(name: "Clean & Jerk", equipment: .barbell, reps: 30),
            ],
            timeCapMinutes: 10,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-isabel", name: "Isabel", type: .forTime,
            blurb: "For time — 30 snatches (135/95 lb).",
            purposes: [.strength], muscles: [.fullBody, .shoulders],
            sessions: [
                RecSession(name: "Snatch", equipment: .barbell, reps: 30),
            ],
            timeCapMinutes: 10,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-diane", name: "Diane", type: .forTime,
            blurb: "21-15-9 — deadlifts (225/155) & handstand push-ups, for time.",
            purposes: [.strength], muscles: [.fullBody, .back, .shoulders],
            sessions: [
                RecSession(name: "Deadlift", equipment: .barbell, reps: 21),
                RecSession(name: "Handstand Push-Up", equipment: .bodyweight, reps: 21),
            ],
            timeCapMinutes: 12,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-elizabeth", name: "Elizabeth", type: .forTime,
            blurb: "21-15-9 — squat cleans (135/95) & ring dips, for time.",
            purposes: [.strength], muscles: [.fullBody, .quads, .triceps],
            sessions: [
                RecSession(name: "Squat Clean", equipment: .barbell, reps: 21),
                RecSession(name: "Ring Dip", equipment: .bodyweight, reps: 21),
            ],
            timeCapMinutes: 12,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-helen", name: "Helen", type: .forTime,
            blurb: "3 rounds for time — 400 m run, 21 KB swings (24/16 kg), 12 pull-ups.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "400 m Run", equipment: .bodyweight, reps: 1),
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 21),
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 12),
            ],
            timeCapMinutes: 15, forTimeRounds: 3,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-annie", name: "Annie", type: .forTime,
            blurb: "50-40-30-20-10 — double-unders & sit-ups, for time.",
            purposes: [.weightLoss], muscles: [.core, .fullBody],
            sessions: [
                RecSession(name: "Double-Under", equipment: .other, reps: 50),
                RecSession(name: "Sit-Up", equipment: .bodyweight, reps: 50),
            ],
            timeCapMinutes: 12,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-karen", name: "Karen", type: .forTime,
            blurb: "For time — 150 wall-ball shots (20/14 lb).",
            purposes: [.weightLoss, .strength], muscles: [.fullBody, .quads, .shoulders],
            sessions: [
                RecSession(name: "Wall-Ball Shot", equipment: .other, reps: 150),
            ],
            timeCapMinutes: 15,
            attribution: "CrossFit benchmark"
        ),

        // MARK: CrossFit Hero WODs
        RecommendedWorkout(
            id: "cf-murph", name: "Murph", type: .forTime,
            blurb: "1 mi run, 100 pull-ups, 200 push-ups, 300 squats, 1 mi run. Vest optional.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "1 Mile Run", equipment: .bodyweight, reps: 1),
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 100),
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 200),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 300),
                RecSession(name: "1 Mile Run", equipment: .bodyweight, reps: 1),
            ],
            timeCapMinutes: 60,
            attribution: "CrossFit Hero WOD"
        ),
        RecommendedWorkout(
            id: "cf-dt", name: "DT", type: .forTime,
            blurb: "5 rounds — 12 deadlifts, 9 hang power cleans, 6 push jerks (155/105).",
            purposes: [.strength, .weightLoss], muscles: [.fullBody, .back, .shoulders],
            sessions: [
                RecSession(name: "Deadlift", equipment: .barbell, reps: 12),
                RecSession(name: "Hang Power Clean", equipment: .barbell, reps: 9),
                RecSession(name: "Push Jerk", equipment: .barbell, reps: 6),
            ],
            timeCapMinutes: 20, forTimeRounds: 5,
            attribution: "CrossFit Hero WOD"
        ),

        // MARK: Barbell strength programs (Reps + progression)
        RecommendedWorkout(
            id: "ss-a", name: "Starting Strength — A", type: .reps,
            blurb: "Squat, bench, deadlift — heavy triples & fives.",
            purposes: [.strength], muscles: [.quads, .chest, .back],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Deadlift", equipment: .barbell, sets: 1, reps: 5),
            ],
            restBetweenSets: 240,
            attribution: "Mark Rippetoe", attributionURL: "https://startingstrength.com"
        ),
        RecommendedWorkout(
            id: "ss-b", name: "Starting Strength — B", type: .reps,
            blurb: "Squat, press, power clean.",
            purposes: [.strength], muscles: [.quads, .shoulders, .back],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Overhead Press", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Power Clean", equipment: .barbell, sets: 5, reps: 3),
            ],
            restBetweenSets: 240,
            attribution: "Mark Rippetoe", attributionURL: "https://startingstrength.com"
        ),
        RecommendedWorkout(
            id: "wendler-squat", name: "5/3/1 — Squat Day", type: .reps,
            blurb: "Main squat top sets, then leg volume.",
            purposes: [.strength, .muscleGrowth], muscles: [.quads, .hamstrings, .core],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Leg Press", equipment: .machine, sets: 5, reps: 10),
                RecExercise(name: "Leg Curl", equipment: .machine, sets: 5, reps: 10),
                RecExercise(name: "Hanging Leg Raise", equipment: .bodyweight, sets: 3, reps: 15),
            ],
            restBetweenSets: 180,
            attribution: "Jim Wendler", attributionURL: "https://jimwendler.com"
        ),
        RecommendedWorkout(
            id: "wendler-bench", name: "5/3/1 — Bench Day", type: .reps,
            blurb: "Main bench top sets, then pressing & rowing volume.",
            purposes: [.strength, .muscleGrowth], muscles: [.chest, .back, .triceps],
            exercises: [
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Dumbbell Bench Press", equipment: .dumbbell, sets: 5, reps: 10),
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 5, reps: 10),
            ],
            restBetweenSets: 180,
            attribution: "Jim Wendler", attributionURL: "https://jimwendler.com"
        ),
        RecommendedWorkout(
            id: "wendler-deadlift", name: "5/3/1 — Deadlift Day", type: .reps,
            blurb: "Main deadlift top sets, then posterior-chain volume.",
            purposes: [.strength, .muscleGrowth], muscles: [.back, .hamstrings, .glutes],
            exercises: [
                RecExercise(name: "Deadlift", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Good Morning", equipment: .barbell, sets: 5, reps: 10),
                RecExercise(name: "Hanging Leg Raise", equipment: .bodyweight, sets: 5, reps: 15),
            ],
            restBetweenSets: 180,
            attribution: "Jim Wendler", attributionURL: "https://jimwendler.com"
        ),
        RecommendedWorkout(
            id: "wendler-press", name: "5/3/1 — Press Day", type: .reps,
            blurb: "Main overhead press top sets, then dips & chins.",
            purposes: [.strength, .muscleGrowth], muscles: [.shoulders, .triceps, .back],
            exercises: [
                RecExercise(name: "Overhead Press", equipment: .barbell, sets: 3, reps: 5),
                RecExercise(name: "Dip", equipment: .bodyweight, sets: 5, reps: 10),
                RecExercise(name: "Chin-Up", equipment: .bodyweight, sets: 5, reps: 10),
            ],
            restBetweenSets: 180,
            attribution: "Jim Wendler", attributionURL: "https://jimwendler.com"
        ),
        RecommendedWorkout(
            id: "gzclp-a1", name: "GZCLP — A1", type: .reps,
            blurb: "Squat T1, bench T2, pulldown T3.",
            purposes: [.strength, .muscleGrowth], muscles: [.quads, .chest, .back],
            exercises: [
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 5, reps: 3),
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 3, reps: 10),
                RecExercise(name: "Lat Pulldown", equipment: .machine, sets: 3, reps: 15),
            ],
            restBetweenSets: 150,
            attribution: "Cody Lefever (GZCLP)", attributionURL: "https://www.gainzfever.com"
        ),
        RecommendedWorkout(
            id: "gzclp-a2", name: "GZCLP — A2", type: .reps,
            blurb: "Press T1, deadlift T2, row T3.",
            purposes: [.strength, .muscleGrowth], muscles: [.shoulders, .back, .hamstrings],
            exercises: [
                RecExercise(name: "Overhead Press", equipment: .barbell, sets: 5, reps: 3),
                RecExercise(name: "Deadlift", equipment: .barbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 3, reps: 15),
            ],
            restBetweenSets: 150,
            attribution: "Cody Lefever (GZCLP)", attributionURL: "https://www.gainzfever.com"
        ),
        RecommendedWorkout(
            id: "gzclp-b1", name: "GZCLP — B1", type: .reps,
            blurb: "Bench T1, squat T2, pulldown T3.",
            purposes: [.strength, .muscleGrowth], muscles: [.chest, .quads, .back],
            exercises: [
                RecExercise(name: "Bench Press", equipment: .barbell, sets: 5, reps: 3),
                RecExercise(name: "Back Squat", equipment: .barbell, sets: 3, reps: 10),
                RecExercise(name: "Lat Pulldown", equipment: .machine, sets: 3, reps: 15),
            ],
            restBetweenSets: 150,
            attribution: "Cody Lefever (GZCLP)", attributionURL: "https://www.gainzfever.com"
        ),
        RecommendedWorkout(
            id: "gzclp-b2", name: "GZCLP — B2", type: .reps,
            blurb: "Deadlift T1, press T2, row T3.",
            purposes: [.strength, .muscleGrowth], muscles: [.back, .shoulders, .hamstrings],
            exercises: [
                RecExercise(name: "Deadlift", equipment: .barbell, sets: 5, reps: 3),
                RecExercise(name: "Overhead Press", equipment: .barbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 3, reps: 15),
            ],
            restBetweenSets: 150,
            attribution: "Cody Lefever (GZCLP)", attributionURL: "https://www.gainzfever.com"
        ),
        RecommendedWorkout(
            id: "bb-bear-complex", name: "Barbell Bear Complex", type: .forTime,
            blurb: "5 rounds of 7 unbroken cycles: clean, front squat, press, back squat, press.",
            purposes: [.strength, .weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Power Clean", equipment: .barbell, reps: 7),
                RecSession(name: "Front Squat", equipment: .barbell, reps: 7),
                RecSession(name: "Push Press", equipment: .barbell, reps: 7),
                RecSession(name: "Back Squat", equipment: .barbell, reps: 7),
                RecSession(name: "Push Press (behind neck)", equipment: .barbell, reps: 7),
            ],
            timeCapMinutes: 20, forTimeRounds: 5
        ),

        // MARK: Dumbbell
        RecommendedWorkout(
            id: "db-full-a", name: "Dumbbell Full Body — A", type: .reps,
            blurb: "Balanced full-body session with one pair of dumbbells.",
            purposes: [.muscleGrowth, .strength], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Goblet Squat", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Bench Press", equipment: .dumbbell, sets: 3, reps: 8),
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 3, reps: 8),
                RecExercise(name: "Dumbbell Romanian Deadlift", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Dumbbell Curl", equipment: .dumbbell, sets: 3, reps: 12),
            ],
            restBetweenSets: 90,
            attribution: "Muscle & Strength", attributionURL: "https://www.muscleandstrength.com"
        ),
        RecommendedWorkout(
            id: "db-full-b", name: "Dumbbell Full Body — B", type: .reps,
            blurb: "Alternates with A — unilateral & overhead focus.",
            purposes: [.muscleGrowth, .strength], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Dumbbell Reverse Lunge", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Shoulder Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Pullover", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Hammer Curl", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Dumbbell Skullcrusher", equipment: .dumbbell, sets: 3, reps: 12),
            ],
            restBetweenSets: 90,
            attribution: "Muscle & Strength", attributionURL: "https://www.muscleandstrength.com"
        ),
        RecommendedWorkout(
            id: "db-full-c", name: "Dumbbell Full Body — C", type: .reps,
            blurb: "Third rotation — incline press & rows.",
            purposes: [.muscleGrowth], muscles: [.fullBody, .chest, .back],
            exercises: [
                RecExercise(name: "Dumbbell Front Squat", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Incline Dumbbell Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Renegade Row", equipment: .dumbbell, sets: 3, reps: 8),
                RecExercise(name: "Lateral Raise", equipment: .dumbbell, sets: 3, reps: 15),
                RecExercise(name: "Dumbbell Calf Raise", equipment: .dumbbell, sets: 3, reps: 15),
            ],
            restBetweenSets: 90,
            attribution: "Muscle & Strength", attributionURL: "https://www.muscleandstrength.com"
        ),
        RecommendedWorkout(
            id: "db-push", name: "Dumbbell Push", type: .reps,
            blurb: "Chest, shoulders & triceps.",
            purposes: [.muscleGrowth], muscles: [.chest, .shoulders, .triceps],
            exercises: [
                RecExercise(name: "Dumbbell Bench Press", equipment: .dumbbell, sets: 4, reps: 8),
                RecExercise(name: "Incline Dumbbell Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Dumbbell Shoulder Press", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Lateral Raise", equipment: .dumbbell, sets: 3, reps: 15),
                RecExercise(name: "Dumbbell Skullcrusher", equipment: .dumbbell, sets: 3, reps: 12),
            ],
            restBetweenSets: 75
        ),
        RecommendedWorkout(
            id: "db-pull", name: "Dumbbell Pull", type: .reps,
            blurb: "Back & biceps.",
            purposes: [.muscleGrowth], muscles: [.back, .biceps],
            exercises: [
                RecExercise(name: "Dumbbell Row", equipment: .dumbbell, sets: 4, reps: 8),
                RecExercise(name: "Chest-Supported Row", equipment: .dumbbell, sets: 3, reps: 10),
                RecExercise(name: "Reverse Fly", equipment: .dumbbell, sets: 3, reps: 15),
                RecExercise(name: "Dumbbell Shrug", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Dumbbell Curl", equipment: .dumbbell, sets: 3, reps: 12),
            ],
            restBetweenSets: 75
        ),
        RecommendedWorkout(
            id: "db-legs", name: "Dumbbell Legs", type: .reps,
            blurb: "Quads, hamstrings, glutes & calves.",
            purposes: [.muscleGrowth, .strength], muscles: [.quads, .hamstrings, .glutes, .calves],
            exercises: [
                RecExercise(name: "Goblet Squat", equipment: .dumbbell, sets: 4, reps: 10),
                RecExercise(name: "Dumbbell Romanian Deadlift", equipment: .dumbbell, sets: 4, reps: 10),
                RecExercise(name: "Walking Lunge", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Dumbbell Calf Raise", equipment: .dumbbell, sets: 4, reps: 15),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "db-arms", name: "Dumbbell Arms", type: .reps,
            blurb: "Biceps & triceps pump.",
            purposes: [.muscleGrowth], muscles: [.biceps, .triceps],
            exercises: [
                RecExercise(name: "Dumbbell Curl", equipment: .dumbbell, sets: 4, reps: 12),
                RecExercise(name: "Hammer Curl", equipment: .dumbbell, sets: 3, reps: 12),
                RecExercise(name: "Overhead Tricep Extension", equipment: .dumbbell, sets: 4, reps: 12),
                RecExercise(name: "Dumbbell Kickback", equipment: .dumbbell, sets: 3, reps: 15),
                RecExercise(name: "Concentration Curl", equipment: .dumbbell, sets: 3, reps: 12),
            ],
            restBetweenSets: 60
        ),
        RecommendedWorkout(
            id: "db-amrap-15", name: "Dumbbell AMRAP 15", type: .amrap,
            blurb: "AMRAP 15 — thrusters, snatches, push-up rows.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Dumbbell Thruster", equipment: .dumbbell, reps: 10),
                RecSession(name: "Dumbbell Snatch", equipment: .dumbbell, reps: 10),
                RecSession(name: "Push-Up Row", equipment: .dumbbell, reps: 10),
            ],
            timeCapMinutes: 15
        ),

        // MARK: Kettlebell
        RecommendedWorkout(
            id: "kb-swing-getup", name: "Swing & Get-Up Minimalist", type: .reps,
            blurb: "Two moves, big returns — 100 one-arm swings, then Turkish get-ups.",
            purposes: [.strength, .weightLoss], muscles: [.fullBody, .glutes, .core],
            exercises: [
                RecExercise(name: "One-Arm Kettlebell Swing", equipment: .kettlebell, sets: 10, reps: 10),
                RecExercise(name: "Turkish Get-Up", equipment: .kettlebell, sets: 10, reps: 1),
            ],
            restBetweenSets: 60,
            attribution: "Pavel Tsatsouline", attributionURL: "https://www.strongfirst.com"
        ),
        RecommendedWorkout(
            id: "kb-double-cp-builder", name: "Double Clean & Press Builder", type: .emom,
            blurb: "Double-KB clean & press — quality reps every minute.",
            purposes: [.strength, .muscleGrowth], muscles: [.fullBody, .shoulders, .back],
            sessions: [
                RecSession(name: "Double Kettlebell Clean & Press", equipment: .kettlebell, reps: 5),
            ],
            emomMinutes: 15,
            attribution: "Geoff Neupert", attributionURL: "https://www.chasingstrength.com"
        ),
        RecommendedWorkout(
            id: "kb-swing-emom-10", name: "KB Swing EMOM 10", type: .emom,
            blurb: "15 two-hand swings at the top of every minute — 150 total.",
            purposes: [.weightLoss, .strength], muscles: [.glutes, .hamstrings, .back],
            sessions: [
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 15),
            ],
            emomMinutes: 10
        ),
        RecommendedWorkout(
            id: "kb-snatch-test", name: "KB Snatch Test", type: .forTime,
            blurb: "100 snatches for time — switch hands as needed.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody, .shoulders],
            sessions: [
                RecSession(name: "Kettlebell Snatch", equipment: .kettlebell, reps: 100),
            ],
            timeCapMinutes: 10
        ),
        RecommendedWorkout(
            id: "kb-goblet-ladder", name: "Goblet Squat & Swing Ladder", type: .reps,
            blurb: "Descending goblet squats paired with swings.",
            purposes: [.strength, .weightLoss], muscles: [.quads, .glutes, .core],
            exercises: [
                RecExercise(name: "Goblet Squat", equipment: .kettlebell, sets: 5, reps: 12),
                RecExercise(name: "Kettlebell Swing", equipment: .kettlebell, sets: 5, reps: 15),
            ],
            restBetweenSets: 75,
            attribution: "Dan John", attributionURL: "https://danjohn.net"
        ),
        RecommendedWorkout(
            id: "kb-getup-practice", name: "Turkish Get-Up Practice", type: .reps,
            blurb: "Slow, controlled get-ups for shoulder resilience & core.",
            purposes: [.strength, .mobility], muscles: [.core, .shoulders, .fullBody],
            exercises: [
                RecExercise(name: "Turkish Get-Up", equipment: .kettlebell, sets: 5, reps: 2),
            ],
            restBetweenSets: 60
        ),
        RecommendedWorkout(
            id: "kb-cp-complex", name: "KB Clean & Press Complex", type: .reps,
            blurb: "Single-bell complex per side — clean, press, squat, row.",
            purposes: [.strength, .muscleGrowth], muscles: [.fullBody, .shoulders, .back],
            exercises: [
                RecExercise(name: "Kettlebell Clean", equipment: .kettlebell, sets: 5, reps: 3),
                RecExercise(name: "Kettlebell Press", equipment: .kettlebell, sets: 5, reps: 3),
                RecExercise(name: "Kettlebell Front Squat", equipment: .kettlebell, sets: 5, reps: 3),
                RecExercise(name: "Kettlebell Row", equipment: .kettlebell, sets: 5, reps: 3),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "kb-500-swing", name: "500-Swing Challenge", type: .emom,
            blurb: "Accumulate 500 swings in sets of 10, 15, 25 and 50.",
            purposes: [.weightLoss, .strength], muscles: [.glutes, .hamstrings, .back],
            sessions: [
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 25),
            ],
            emomMinutes: 20,
            attribution: "Dan John", attributionURL: "https://danjohn.net"
        ),
        RecommendedWorkout(
            id: "kb-man-maker", name: "KB Man Maker", type: .forTime,
            blurb: "21-15-9 man makers & swings, for time.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Kettlebell Man Maker", equipment: .kettlebell, reps: 21),
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell, reps: 21),
            ],
            timeCapMinutes: 15
        ),
        RecommendedWorkout(
            id: "kb-tabata-swings", name: "KB Tabata Swings", type: .intervals,
            blurb: "20s swing / 10s rest × 8.",
            purposes: [.weightLoss], muscles: [.glutes, .hamstrings, .back],
            sessions: [
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell),
            ],
            work: 20, rest: 10, rounds: 8
        ),

        // MARK: Bodyweight
        RecommendedWorkout(
            id: "bw-beginner", name: "Beginner Bodyweight", type: .reps,
            blurb: "A gentle full-body starter — 3 rounds.",
            purposes: [.muscleGrowth, .weightLoss], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Air Squat", equipment: .bodyweight, sets: 3, reps: 20),
                RecExercise(name: "Push-Up", equipment: .bodyweight, sets: 3, reps: 10),
                RecExercise(name: "Inverted Row", equipment: .bodyweight, sets: 3, reps: 10),
                RecExercise(name: "Reverse Lunge", equipment: .bodyweight, sets: 3, reps: 15),
                RecExercise(name: "Plank", equipment: .bodyweight, sets: 3, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 60,
            attribution: "Nerd Fitness", attributionURL: "https://www.nerdfitness.com"
        ),
        RecommendedWorkout(
            id: "bw-recommended-routine", name: "Bodyweight Basics", type: .reps,
            blurb: "Push/pull/legs pairs — the community strength staple.",
            purposes: [.strength, .muscleGrowth], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Pull-Up", equipment: .bodyweight, sets: 3, reps: 6),
                RecExercise(name: "Dip", equipment: .bodyweight, sets: 3, reps: 8),
                RecExercise(name: "Bulgarian Split Squat", equipment: .bodyweight, sets: 3, reps: 8),
                RecExercise(name: "Push-Up", equipment: .bodyweight, sets: 3, reps: 10),
                RecExercise(name: "Inverted Row", equipment: .bodyweight, sets: 3, reps: 10),
            ],
            restBetweenSets: 90,
            attribution: "r/bodyweightfitness", attributionURL: "https://www.reddit.com/r/bodyweightfitness/wiki/kb/recommended_routine"
        ),
        RecommendedWorkout(
            id: "bw-prisoner", name: "Prisoner Bodyweight", type: .reps,
            blurb: "No-gear grinder — 5 rounds.",
            purposes: [.muscleGrowth, .weightLoss], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Push-Up", equipment: .bodyweight, sets: 5, reps: 10),
                RecExercise(name: "Air Squat", equipment: .bodyweight, sets: 5, reps: 15),
                RecExercise(name: "Pike Push-Up", equipment: .bodyweight, sets: 5, reps: 10),
                RecExercise(name: "Reverse Lunge", equipment: .bodyweight, sets: 5, reps: 20),
            ],
            restBetweenSets: 60
        ),
        RecommendedWorkout(
            id: "bw-death-by-burpees", name: "Death by Burpees", type: .emom,
            blurb: "Add one burpee each minute — 1, then 2, then 3… until you can't keep up.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Burpee", equipment: .bodyweight, reps: 1),
            ],
            emomMinutes: 20
        ),
        RecommendedWorkout(
            id: "bw-core-circuit", name: "Core Circuit", type: .reps,
            blurb: "Five-move core burner — 3 rounds.",
            purposes: [.strength], muscles: [.core],
            exercises: [
                RecExercise(name: "Plank", equipment: .bodyweight, sets: 3, reps: 1, isTimed: true, durationSeconds: 45),
                RecExercise(name: "Sit-Up", equipment: .bodyweight, sets: 3, reps: 20),
                RecExercise(name: "Leg Raise", equipment: .bodyweight, sets: 3, reps: 20),
                RecExercise(name: "Mountain Climbers", equipment: .bodyweight, sets: 3, reps: 30),
                RecExercise(name: "Hollow Hold", equipment: .bodyweight, sets: 3, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 45
        ),
        RecommendedWorkout(
            id: "bw-emom-15", name: "Bodyweight EMOM 15", type: .emom,
            blurb: "Rotate push-ups, squats & sit-ups each minute for 15.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 12),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 18),
                RecSession(name: "Sit-Up", equipment: .bodyweight, reps: 15),
            ],
            emomMinutes: 15
        ),
        RecommendedWorkout(
            id: "bw-pushup-squat-ladder", name: "Push-Up & Squat Ladder", type: .forTime,
            blurb: "Descending push-ups paired with ascending squats, for time.",
            purposes: [.weightLoss, .strength], muscles: [.chest, .quads],
            sessions: [
                RecSession(name: "Push-Up", equipment: .bodyweight, reps: 10),
                RecSession(name: "Air Squat", equipment: .bodyweight, reps: 10),
            ],
            timeCapMinutes: 12
        ),
        RecommendedWorkout(
            id: "bw-cardio-blast", name: "Bodyweight Cardio Blast", type: .intervals,
            blurb: "40s work / 20s rest × 10 — jacks, high knees, burpees, skaters.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Jumping Jacks", equipment: .bodyweight),
                RecSession(name: "High Knees", equipment: .bodyweight),
                RecSession(name: "Burpee", equipment: .bodyweight),
                RecSession(name: "Skater Jumps", equipment: .bodyweight),
            ],
            work: 40, rest: 20, rounds: 10
        ),

        // MARK: Machine & Cable
        RecommendedWorkout(
            id: "machine-full-body", name: "Machine Full-Body Circuit", type: .reps,
            blurb: "Guided-path full-body loop — beginner friendly.",
            purposes: [.muscleGrowth, .weightLoss], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Leg Press", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Chest Press Machine", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Lat Pulldown", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Shoulder Press Machine", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Seated Leg Curl", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Ab Crunch Machine", equipment: .machine, sets: 3, reps: 15),
            ],
            restBetweenSets: 60,
            attribution: "Planet Fitness", attributionURL: "https://www.planetfitness.com"
        ),
        RecommendedWorkout(
            id: "machine-push", name: "Machine Push", type: .reps,
            blurb: "Chest, shoulders & triceps on machines.",
            purposes: [.muscleGrowth], muscles: [.chest, .shoulders, .triceps],
            exercises: [
                RecExercise(name: "Chest Press Machine", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Shoulder Press Machine", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Pec Deck", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Triceps Pushdown", equipment: .cable, sets: 3, reps: 15),
            ],
            restBetweenSets: 60
        ),
        RecommendedWorkout(
            id: "machine-pull", name: "Machine Pull", type: .reps,
            blurb: "Back & biceps on machines.",
            purposes: [.muscleGrowth], muscles: [.back, .biceps],
            exercises: [
                RecExercise(name: "Lat Pulldown", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Seated Row Machine", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Rear Delt Fly Machine", equipment: .machine, sets: 3, reps: 15),
                RecExercise(name: "Biceps Curl Machine", equipment: .machine, sets: 3, reps: 12),
            ],
            restBetweenSets: 60
        ),
        RecommendedWorkout(
            id: "machine-legs", name: "Machine Legs", type: .reps,
            blurb: "Full lower body on machines.",
            purposes: [.muscleGrowth, .strength], muscles: [.quads, .hamstrings, .glutes, .calves],
            exercises: [
                RecExercise(name: "Leg Press", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Leg Extension", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Seated Leg Curl", equipment: .machine, sets: 3, reps: 12),
                RecExercise(name: "Calf Raise Machine", equipment: .machine, sets: 3, reps: 15),
                RecExercise(name: "Hip Abduction Machine", equipment: .machine, sets: 3, reps: 15),
            ],
            restBetweenSets: 75
        ),
        RecommendedWorkout(
            id: "machine-beginner-30", name: "Machine Beginner 30-Min", type: .reps,
            blurb: "Quick six-machine loop, 2 sets each.",
            purposes: [.weightLoss, .muscleGrowth], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Leg Press", equipment: .machine, sets: 2, reps: 10),
                RecExercise(name: "Chest Press Machine", equipment: .machine, sets: 2, reps: 10),
                RecExercise(name: "Seated Row Machine", equipment: .machine, sets: 2, reps: 10),
                RecExercise(name: "Shoulder Press Machine", equipment: .machine, sets: 2, reps: 10),
                RecExercise(name: "Leg Curl", equipment: .machine, sets: 2, reps: 10),
                RecExercise(name: "Ab Crunch Machine", equipment: .machine, sets: 2, reps: 15),
            ],
            restBetweenSets: 45,
            attribution: "Gold's Gym", attributionURL: "https://www.goldsgym.com"
        ),
        RecommendedWorkout(
            id: "cable-full-body", name: "Cable Full Body", type: .reps,
            blurb: "Constant-tension full-body cable session.",
            purposes: [.muscleGrowth], muscles: [.fullBody, .core],
            exercises: [
                RecExercise(name: "Cable Chest Press", equipment: .cable, sets: 3, reps: 12),
                RecExercise(name: "Cable Row", equipment: .cable, sets: 3, reps: 12),
                RecExercise(name: "Cable Woodchop", equipment: .cable, sets: 3, reps: 12),
                RecExercise(name: "Face Pull", equipment: .cable, sets: 3, reps: 15),
                RecExercise(name: "Cable Curl", equipment: .cable, sets: 3, reps: 12),
            ],
            restBetweenSets: 60
        ),

        // MARK: Resistance band
        RecommendedWorkout(
            id: "band-full-body", name: "Band Full Body", type: .reps,
            blurb: "Portable full-body strength with one band.",
            purposes: [.muscleGrowth, .strength], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Band Squat", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Chest Press", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Row", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Overhead Press", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Deadlift", equipment: .resistanceBand, sets: 3, reps: 15),
            ],
            restBetweenSets: 45,
            attribution: "ISSA", attributionURL: "https://www.issaonline.com"
        ),
        RecommendedWorkout(
            id: "band-upper", name: "Band Upper Body", type: .reps,
            blurb: "Push & pull for the upper body with bands.",
            purposes: [.muscleGrowth], muscles: [.chest, .back, .shoulders, .biceps, .triceps],
            exercises: [
                RecExercise(name: "Band Chest Press", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Row", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Pull-Apart", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Overhead Press", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Curl", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Pushdown", equipment: .resistanceBand, sets: 3, reps: 15),
            ],
            restBetweenSets: 45
        ),
        RecommendedWorkout(
            id: "band-lower", name: "Band Lower Body", type: .reps,
            blurb: "Legs & glutes with bands.",
            purposes: [.muscleGrowth, .strength], muscles: [.quads, .hamstrings, .glutes, .calves],
            exercises: [
                RecExercise(name: "Band Squat", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Romanian Deadlift", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Lateral Walk", equipment: .resistanceBand, sets: 3, reps: 20),
                RecExercise(name: "Band Glute Kickback", equipment: .resistanceBand, sets: 3, reps: 15),
                RecExercise(name: "Band Calf Press", equipment: .resistanceBand, sets: 3, reps: 20),
            ],
            restBetweenSets: 45
        ),
        RecommendedWorkout(
            id: "band-core", name: "Band Core", type: .reps,
            blurb: "Anti-rotation & rotation core work — 3 rounds.",
            purposes: [.strength], muscles: [.core],
            exercises: [
                RecExercise(name: "Pallof Press", equipment: .resistanceBand, sets: 3, reps: 12),
                RecExercise(name: "Band Woodchop", equipment: .resistanceBand, sets: 3, reps: 12),
                RecExercise(name: "Band Dead Bug", equipment: .resistanceBand, sets: 3, reps: 12),
                RecExercise(name: "Anti-Rotation Hold", equipment: .resistanceBand, sets: 3, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 45
        ),
        RecommendedWorkout(
            id: "band-shoulder-prehab", name: "Band Shoulder Prehab", type: .reps,
            blurb: "Timed rotator-cuff & scapular work to keep shoulders healthy.",
            purposes: [.mobility], muscles: [.shoulders],
            exercises: [
                RecExercise(name: "Band Pull-Apart", equipment: .resistanceBand, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Band External Rotation", equipment: .resistanceBand, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Band Face Pull", equipment: .resistanceBand, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Band Dislocates", equipment: .resistanceBand, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 15
        ),
        RecommendedWorkout(
            id: "band-glute-activation", name: "Band Glute Activation", type: .reps,
            blurb: "Wake up the glutes before you train — 3 rounds.",
            purposes: [.mobility, .strength], muscles: [.glutes],
            exercises: [
                RecExercise(name: "Band Lateral Walk", equipment: .resistanceBand, sets: 3, reps: 20),
                RecExercise(name: "Band Monster Walk", equipment: .resistanceBand, sets: 3, reps: 20),
                RecExercise(name: "Band Glute Bridge", equipment: .resistanceBand, sets: 3, reps: 20),
                RecExercise(name: "Band Clamshell", equipment: .resistanceBand, sets: 3, reps: 20),
                RecExercise(name: "Band Glute Kickback", equipment: .resistanceBand, sets: 3, reps: 20),
            ],
            restBetweenSets: 30
        ),

        // MARK: Intervals / HIIT
        RecommendedWorkout(
            id: "tabata-squats", name: "Tabata Squats", type: .intervals,
            blurb: "20s work / 10s rest × 8 — air squats.",
            purposes: [.weightLoss], muscles: [.quads, .glutes],
            sessions: [ RecSession(name: "Air Squat", equipment: .bodyweight) ],
            work: 20, rest: 10, rounds: 8
        ),
        RecommendedWorkout(
            id: "tabata-pushups", name: "Tabata Push-Ups", type: .intervals,
            blurb: "20s work / 10s rest × 8 — push-ups.",
            purposes: [.weightLoss, .strength], muscles: [.chest, .triceps],
            sessions: [ RecSession(name: "Push-Up", equipment: .bodyweight) ],
            work: 20, rest: 10, rounds: 8
        ),
        RecommendedWorkout(
            id: "tabata-burpees", name: "Tabata Burpees", type: .intervals,
            blurb: "20s work / 10s rest × 8 — burpees.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [ RecSession(name: "Burpee", equipment: .bodyweight) ],
            work: 20, rest: 10, rounds: 8
        ),
        RecommendedWorkout(
            id: "tabata-mountain-climbers", name: "Tabata Mountain Climbers", type: .intervals,
            blurb: "20s work / 10s rest × 8 — mountain climbers.",
            purposes: [.weightLoss], muscles: [.core, .fullBody],
            sessions: [ RecSession(name: "Mountain Climbers", equipment: .bodyweight) ],
            work: 20, rest: 10, rounds: 8
        ),
        RecommendedWorkout(
            id: "tabata-core", name: "Core Tabata", type: .intervals,
            blurb: "20s / 10s × 8 — rotate plank, hollow, flutter, sit-ups.",
            purposes: [.weightLoss, .strength], muscles: [.core],
            sessions: [
                RecSession(name: "Plank", equipment: .bodyweight),
                RecSession(name: "Hollow Hold", equipment: .bodyweight),
                RecSession(name: "Flutter Kicks", equipment: .bodyweight),
                RecSession(name: "Sit-Up", equipment: .bodyweight),
            ],
            work: 20, rest: 10, rounds: 8
        ),
        RecommendedWorkout(
            id: "hiit-30-30", name: "30/30 Cardio", type: .intervals,
            blurb: "30s work / 30s rest × 10 — rotating cardio moves.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Jumping Jacks", equipment: .bodyweight),
                RecSession(name: "Mountain Climbers", equipment: .bodyweight),
                RecSession(name: "Burpee", equipment: .bodyweight),
                RecSession(name: "High Knees", equipment: .bodyweight),
            ],
            work: 30, rest: 30, rounds: 10
        ),
        RecommendedWorkout(
            id: "hiit-40-20", name: "40/20 Conditioning", type: .intervals,
            blurb: "40s work / 20s rest × 12 — full-body conditioning rotation.",
            purposes: [.weightLoss], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Squat Jumps", equipment: .bodyweight),
                RecSession(name: "Push-Up", equipment: .bodyweight),
                RecSession(name: "Burpee", equipment: .bodyweight),
                RecSession(name: "Mountain Climbers", equipment: .bodyweight),
            ],
            work: 40, rest: 20, rounds: 12
        ),
        RecommendedWorkout(
            id: "hiit-dumbbell", name: "Dumbbell HIIT", type: .intervals,
            blurb: "40s work / 20s rest × 10 — dumbbell conditioning.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Dumbbell Thruster", equipment: .dumbbell),
                RecSession(name: "Dumbbell Row", equipment: .dumbbell),
                RecSession(name: "Goblet Squat", equipment: .dumbbell),
                RecSession(name: "Dumbbell Push Press", equipment: .dumbbell),
                RecSession(name: "Dumbbell Snatch", equipment: .dumbbell),
            ],
            work: 40, rest: 20, rounds: 10
        ),
        RecommendedWorkout(
            id: "hiit-kettlebell", name: "Kettlebell HIIT", type: .intervals,
            blurb: "30s work / 15s rest × 12 — kettlebell conditioning.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Kettlebell Swing", equipment: .kettlebell),
                RecSession(name: "Goblet Squat", equipment: .kettlebell),
                RecSession(name: "Kettlebell High Pull", equipment: .kettlebell),
                RecSession(name: "Kettlebell Push Press", equipment: .kettlebell),
            ],
            work: 30, rest: 15, rounds: 12,
            attribution: "ACE Fitness", attributionURL: "https://www.acefitness.org"
        ),

        // MARK: Mobility & recovery
        RecommendedWorkout(
            id: "mobility-full-body", name: "Full-Body Mobility Flow", type: .reps,
            blurb: "Six timed holds to move well head to toe.",
            purposes: [.mobility], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Cat-Cow", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
                RecExercise(name: "World's Greatest Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "90/90 Hip Switch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Thoracic Rotation", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Deep Squat Hold", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
                RecExercise(name: "Hip Flexor Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 15
        ),
        RecommendedWorkout(
            id: "mobility-hip", name: "Hip Mobility", type: .reps,
            blurb: "Free up tight hips before or after training.",
            purposes: [.mobility], muscles: [.glutes, .hamstrings, .quads],
            exercises: [
                RecExercise(name: "Pigeon Pose", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 40),
                RecExercise(name: "90/90 Hip Switch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Hip Flexor Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Adductor Rock", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Deep Squat Hold", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
            ],
            restBetweenSets: 15
        ),
        RecommendedWorkout(
            id: "mobility-spine", name: "Thoracic & Spine Mobility", type: .reps,
            blurb: "Restore rotation and extension through the mid-back.",
            purposes: [.mobility], muscles: [.back, .core],
            exercises: [
                RecExercise(name: "Cat-Cow", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 40),
                RecExercise(name: "Thread the Needle", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Open Book", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Cobra / Extension", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Child's Pose", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 45),
            ],
            restBetweenSets: 15
        ),
        RecommendedWorkout(
            id: "mobility-post-workout", name: "Post-Workout Stretch", type: .reps,
            blurb: "Six static holds to cool down and recover.",
            purposes: [.mobility], muscles: [.fullBody],
            exercises: [
                RecExercise(name: "Hamstring Stretch", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Quad Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Doorway Chest Stretch", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Lat Stretch", equipment: .bodyweight, sets: 1, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Calf Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
                RecExercise(name: "Figure-4 Glute Stretch", equipment: .bodyweight, sets: 2, reps: 1, isTimed: true, durationSeconds: 30),
            ],
            restBetweenSets: 15
        ),

        // MARK: More benchmarks & variety
        RecommendedWorkout(
            id: "cf-nancy", name: "Nancy", type: .forTime,
            blurb: "5 rounds for time — 400 m run + 15 overhead squats (95/65).",
            purposes: [.strength, .weightLoss], muscles: [.fullBody, .quads, .shoulders],
            sessions: [
                RecSession(name: "400 m Run", equipment: .bodyweight, reps: 1),
                RecSession(name: "Overhead Squat", equipment: .barbell, reps: 15),
            ],
            timeCapMinutes: 20, forTimeRounds: 5,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "cf-jackie", name: "Jackie", type: .forTime,
            blurb: "For time — 1000 m row, 50 thrusters (45 lb), 30 pull-ups.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "1000 m Row", equipment: .other, reps: 1),
                RecSession(name: "Thruster", equipment: .barbell, reps: 50),
                RecSession(name: "Pull-Up", equipment: .bodyweight, reps: 30),
            ],
            timeCapMinutes: 15,
            attribution: "CrossFit benchmark"
        ),
        RecommendedWorkout(
            id: "kb-double-fsq-ladder", name: "Double KB Front Squat Ladder", type: .reps,
            blurb: "Ascending double-kettlebell front squats — build the legs.",
            purposes: [.strength, .muscleGrowth], muscles: [.quads, .glutes, .core],
            exercises: [
                RecExercise(name: "Double Kettlebell Front Squat", equipment: .kettlebell, sets: 5, reps: 8),
                RecExercise(name: "Kettlebell Swing", equipment: .kettlebell, sets: 5, reps: 12),
            ],
            restBetweenSets: 90
        ),
        RecommendedWorkout(
            id: "db-full-emom", name: "Dumbbell Full-Body EMOM", type: .emom,
            blurb: "EMOM 16 — rotate four dumbbell moves each minute.",
            purposes: [.weightLoss, .strength], muscles: [.fullBody],
            sessions: [
                RecSession(name: "Dumbbell Thruster", equipment: .dumbbell, reps: 10),
                RecSession(name: "Dumbbell Romanian Deadlift", equipment: .dumbbell, reps: 12),
                RecSession(name: "Renegade Row", equipment: .dumbbell, reps: 8),
                RecSession(name: "Dumbbell Push Press", equipment: .dumbbell, reps: 10),
            ],
            emomMinutes: 16
        ),
        RecommendedWorkout(
            id: "tabata-lunges", name: "Tabata Lunges", type: .intervals,
            blurb: "20s work / 10s rest × 8 — alternating lunges.",
            purposes: [.weightLoss], muscles: [.quads, .glutes],
            sessions: [ RecSession(name: "Alternating Lunge", equipment: .bodyweight) ],
            work: 20, rest: 10, rounds: 8
        ),
    ]
}

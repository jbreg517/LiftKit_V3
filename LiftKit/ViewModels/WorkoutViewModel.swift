import Foundation
import SwiftData
import SwiftUI

// MARK: - Session Card (used in setup screen)
struct SessionCard: Identifiable {
    var id = UUID()
    /// The chosen library/custom Exercise's stable id (Option C). nil until picked.
    var exerciseID: UUID? = nil
    var name: String = ""
    var equipment: Equipment = .none
    var weight: Double = 0
    var weightUnit: WeightUnit = .lb
    var reps: Int = 10
}

// MARK: - Exercise Card (Reps setup)
struct ExerciseCard: Identifiable {
    var id = UUID()
    /// The chosen library/custom Exercise's stable id (Option C). nil until picked.
    var exerciseID: UUID? = nil
    var name: String = ""
    var equipment: Equipment = .none
    var weight: Double = 0
    var weightUnit: WeightUnit = .lb
    var sets: Int = 3
    var reps: Int = 10
    /// Track hold time (e.g. planks) instead of reps.
    var isTimed: Bool = false
    var durationSeconds: Int = 60
    /// Supersetted with the next exercise in the list (alternate between them).
    var linkedToNext: Bool = false
    // Transient progression hint shown in setup (not persisted).
    var progressionNote: String? = nil
    var progressionReason: ProgressionService.Reason? = nil
}

// MARK: - Active Set State
struct ActiveSet: Identifiable {
    var id: UUID
    var setNumber: Int
    var isTimed: Bool
    var plannedReps: Int
    var actualReps: Int
    var plannedDuration: Int   // seconds
    var actualDuration: Int    // seconds
    var isCompleted: Bool = false
    var weight: Double
    var weightUnit: WeightUnit
    var setType: SetType = .normal
    var rpe: Double? = nil
}

// MARK: - Active Exercise State
struct ActiveExercise: Identifiable {
    var id = UUID()
    var name: String
    var equipment: Equipment
    var weight: Double
    var weightUnit: WeightUnit
    var isTimed: Bool
    var sets: [ActiveSet]
    /// "Last: 135×5 · 135×5" from the previous session, computed once at start.
    var previousSummary: String? = nil
    /// Superset group index (nil = standalone). Consecutive exercises sharing
    /// a non-nil value are performed as a superset.
    var supersetGroup: Int? = nil

    init(from card: ExerciseCard) {
        self.name = card.name.isEmpty ? "Exercise" : card.name
        self.equipment = card.equipment
        self.weight = card.weight
        self.weightUnit = card.weightUnit
        self.isTimed = card.isTimed
        self.sets = (0..<card.sets).map { i in
            ActiveSet(
                id: UUID(),
                setNumber: i + 1,
                isTimed: card.isTimed,
                plannedReps: card.reps,
                actualReps: card.reps,
                plannedDuration: card.durationSeconds,
                actualDuration: card.durationSeconds,
                weight: card.weight,
                weightUnit: card.weightUnit
            )
        }
    }
}

// MARK: - Completion Messages
let completionMessages: [String] = [
    "You worked out. Hooray.",
    "Wow. You actually finished.",
    "You showed up. That's like 90% of it. The other 90% is doing it again tomorrow.",
    "Congratulations. Your couch misses you.",
    "You did more than everyone still in bed.",
    "Legend has it, you almost quit three times.",
    "You're welcome, future you.",
    "Sweat is just your fat crying. Let it cry.",
    "You didn't die. That's a win.",
    "Rest day has been earned. Use it wisely. Or don't.",
    "The hardest part was opening this app.",
    "Another workout in the books. The book nobody asked for.",
    "You could've napped. But you didn't. Probably a good choice.",
    "One step closer to whatever it is you're doing. What do I know. I'm just your tracking app.",
    "The bar was on the floor. You picked it up. Literally.",
    "Tell everyone at dinner. They'll love hearing about it.",
    "Remember this feeling next time you don't want to start.",
    "Your past self is jealous. Your future self says thanks.",
    "Calories burned. Dignity intact. Mostly.",
    "You just lapped everyone on the couch.",
    "Somewhere, a personal trainer is mildly proud.",
    "Your body just filed a complaint.",
    "Well, that happened.",
    "You showed up and that's more than most.",
    "You're basically superhuman. With limitations.",
    "That was either impressive or concerning. Either way, done.",
    "Fitness journey: 1% complete.",
    "You exercised on purpose. Wild.",
    "Your potential is showing.",
    "You could've scrolled social media instead. Respect.",
    "You're the hero nobody asked for, but here you are.",
    "Good job. Now stop reading this and go stretch.",
    "You just peaked. Or at least you're getting closer.",
    "Not all heroes wear capes. Some just finish their sets.",
    "You chose pain. Voluntarily. That's character.",
    "Post-workout glow: activated. Post-workout soreness: loading.",
    "Consider this your participation trophy.",
    "You just proved your excuses wrong.",
    "Still standing? Overachiever.",
    "You showed up. Gold star.",
    "Results may vary. Effort did not.",
    "Day one or day one hundred – doesn't matter. You're here.",
    "Your couch is filing a missing person report.",
    "You deserve a slow clap.",
    "That was tougher than it looked. And it looked tough.",
    "Proof that stubbornness has its benefits.",
    "Strong is a process. You're processing.",
    "You came, you saw, you sweat.",
    "A round of applause. From you. To you.",
    "Consider yourself 1 rep closer to greatness.",
    "Your body is a temple. That temple just got renovated.",
    "The workout is done. The soreness is coming.",
    "That's called discipline. Or stubbornness. Same thing.",
    "Plot twist: you did it.",
    "Good news: it's over. Bad news: there's always tomorrow."
]

// MARK: - WorkoutViewModel

@Observable
final class WorkoutViewModel {
    // MARK: Navigation state
    var showTypePicker        = false
    var showLogin             = false
    var showActiveWorkout     = false
    var showSaveTemplate      = false
    var showWorkoutSetup      = false

    // MARK: Setup state
    var selectedTimerType: TimerType = .amrap
    var workoutName: String = ""
    var notes: String = ""

    // AMRAP / For Time
    var timeLimitMinutes: Int = 10
    var timeLimitSeconds: Int = 0
    var sessions: [SessionCard] = [SessionCard()]

    // EMOM
    var emomMinutes: Int = 10
    var emomSessions: [SessionCard] = [SessionCard()]

    // Intervals
    var workSeconds: Int = 40
    var restSeconds: Int = 20
    var intervalRounds: Int = 8
    var intervalSessions: [SessionCard] = [SessionCard()]

    // Reps
    var restBetweenSets: Int = 90
    var exercises: [ExerciseCard] = [ExerciseCard()]

    // Manual
    var manualSessions: [SessionCard] = [SessionCard()]

    // MARK: Active workout state
    var activeSession: WorkoutSession?
    var activeConfig: TimerConfig = TimerConfig(type: .manual)
    var activeSessionCards: [SessionCard] = []
    var activeExercises: [ActiveExercise] = []
    var currentSessionIndex: Int = 0
    var completedRounds: Int = 0
    var isShowingComplete: Bool = false
    var completionMessage: String = ""
    var newPRTypes: [PRType] = []
    var showPRBanner: Bool = false
    var prBannerMessage: String = ""

    // Template saving
    var templateName: String = ""
    var templateNameError: String = ""
    /// Set when the current setup was loaded from an existing plan/template,
    /// enabling "Save as New" + "Update Workout". nil for a fresh workout.
    var editingTemplate: WorkoutTemplate?

    // User profile cache
    var userProfile: UserProfile?

    // MARK: - Setup helpers

    func loadFromTemplate(_ template: WorkoutTemplate, type: TimerType) {
        editingTemplate = template
        selectedTimerType = type
        workoutName = template.name
        // Templates don't store rest time, so seed it from the Settings default.
        restBetweenSets = Int(UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Double ?? 90)
        let sorted = template.sortedExercises
        exercises = sorted.map { ex in
            var card = ExerciseCard()
            card.name = ex.exerciseName
            card.equipment = ex.equipment ?? .none
            card.weight = ex.targetWeight
            card.weightUnit = ex.weightUnit
            card.sets = ex.targetSets
            card.reps = ex.targetReps
            card.isTimed = ex.timerType == .forTime
            card.durationSeconds = ex.targetDuration > 0 ? ex.targetDuration : 60
            card.linkedToNext = ex.linkedToNext
            return card
        }
        sessions = sorted.map { ex in
            var card = SessionCard()
            card.name = ex.exerciseName
            card.equipment = ex.equipment ?? .none
            card.weight = ex.targetWeight
            card.weightUnit = ex.weightUnit
            return card
        }
    }

    /// Applies Stronglifts-style weight progression to the current rep-based
    /// exercise cards, overriding the working weight with the next suggested
    /// weight when prior history exists. Used when entering setup from a
    /// template or a repeated session.
    func applyProgression(context: ModelContext) {
        for i in exercises.indices {
            let name = exercises[i].name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !exercises[i].isTimed else { continue }
            if let prog = ProgressionService.shared.suggest(
                exerciseID: exercises[i].exerciseID, exerciseName: name,
                equipment: exercises[i].equipment, in: context
            ) {
                exercises[i].weight = prog.weight
                exercises[i].weightUnit = prog.unit
                exercises[i].progressionNote = prog.note
                exercises[i].progressionReason = prog.reason
            }
        }
    }

    /// Loads a pre-built recommended workout into the setup screen so the user
    /// can review it, then Start or Save it as their own plan.
    func loadRecommended(_ rec: RecommendedWorkout) {
        resetSetup()
        selectedTimerType = rec.type
        workoutName = rec.name
        restBetweenSets = rec.restBetweenSets
        timeLimitMinutes = rec.timeCapMinutes
        timeLimitSeconds = 0
        emomMinutes = rec.emomMinutes
        workSeconds = rec.work
        restSeconds = rec.rest
        intervalRounds = rec.rounds

        let exCards: [ExerciseCard] = rec.exercises.map { r in
            var c = ExerciseCard()
            c.name = r.name
            c.equipment = r.equipment
            c.sets = r.sets
            c.reps = r.reps
            c.isTimed = r.isTimed
            c.durationSeconds = r.durationSeconds
            return c
        }
        let sessCards: [SessionCard] = rec.sessions.map { r in
            var c = SessionCard()
            c.name = r.name
            c.equipment = r.equipment
            c.reps = r.reps
            return c
        }

        switch rec.type {
        case .reps:      exercises = exCards.isEmpty ? [ExerciseCard()] : exCards
        case .amrap, .forTime: sessions = sessCards.isEmpty ? [SessionCard()] : sessCards
        case .emom:      emomSessions = sessCards.isEmpty ? [SessionCard()] : sessCards
        case .intervals: intervalSessions = sessCards.isEmpty ? [SessionCard()] : sessCards
        case .manual:    manualSessions = sessCards.isEmpty ? [SessionCard()] : sessCards
        }
        showWorkoutSetup = true
    }

    func buildTimerConfig() -> TimerConfig {
        var config = TimerConfig(type: selectedTimerType)
        switch selectedTimerType {
        case .amrap:
            config.totalDuration = Double(timeLimitMinutes * 60 + timeLimitSeconds)
        case .emom:
            config.rounds = emomMinutes
        case .forTime:
            config.totalDuration = Double(timeLimitMinutes * 60 + timeLimitSeconds)
        case .intervals:
            config.workDuration = Double(workSeconds)
            config.restDuration = Double(restSeconds)
            config.intervalRounds = intervalRounds
        case .reps:
            config.restBetweenSets = Double(restBetweenSets)
        case .manual:
            break
        }
        return config
    }

    var currentSessionCards: [SessionCard] {
        switch selectedTimerType {
        case .amrap, .forTime: return sessions
        case .emom:            return emomSessions
        case .intervals:       return intervalSessions
        case .manual:          return manualSessions
        case .reps:            return []
        }
    }

    // MARK: - Workout start

    func startTimedWorkout(context: ModelContext) {
        let name = workoutName.isEmpty ? selectedTimerType.rawValue : workoutName
        let session = WorkoutSession(name: name, workoutType: selectedTimerType.rawValue)
        session.notes = notes.isEmpty ? nil : notes
        context.insert(session)

        // Create entries
        let cards = activeSessions(for: selectedTimerType)
        for (i, card) in cards.enumerated() {
            let exName = card.name.isEmpty ? "Workout \(i + 1)" : card.name
            let exercise = findOrCreateExercise(id: card.exerciseID, name: exName, equipment: card.equipment, context: context)
            let entry = WorkoutEntry(timerType: selectedTimerType, sortOrder: i)
            entry.equipmentRaw = card.equipment == .none ? nil : card.equipment.rawValue
            entry.session = session
            entry.exercise = exercise
            context.insert(entry)
        }

        let groups = supersetGroups()
        if selectedTimerType == .reps {
            for (i, card) in exercises.enumerated() {
                let exName = card.name.isEmpty ? "Exercise \(i + 1)" : card.name
                let exercise = findOrCreateExercise(id: card.exerciseID, name: exName, equipment: card.equipment, context: context)
                let entry = WorkoutEntry(
                    timerType: card.isTimed ? .forTime : .reps,
                    sortOrder: i,
                    plannedSets: card.sets
                )
                entry.equipmentRaw = card.equipment == .none ? nil : card.equipment.rawValue
                entry.supersetGroup = groups[i]
                entry.session = session
                entry.exercise = exercise
                context.insert(entry)
            }
        }

        try? context.save()

        activeSession = session
        activeConfig  = buildTimerConfig()
        activeSessionCards = cards
        if selectedTimerType == .reps {
            activeExercises = exercises.map { ActiveExercise(from: $0) }
            // Cache each exercise's previous-session summary once (avoids per-render fetches).
            for (i, card) in exercises.enumerated() where i < activeExercises.count {
                activeExercises[i].previousSummary = WeightCache.shared.previousSummary(
                    exerciseID: card.exerciseID, exerciseName: activeExercises[i].name,
                    equipment: card.equipment, excluding: session.id, in: context
                )
                activeExercises[i].supersetGroup = groups[i]
            }
        }
        currentSessionIndex = 0
        completedRounds = 0
        isShowingComplete = false
        completionMessage = completionMessages.randomElement() ?? ""
        showActiveWorkout = true
    }

    func loadFromSession(_ session: WorkoutSession) {
        resetSetup()
        let type = session.timerType ?? .manual
        selectedTimerType = type
        workoutName = session.name
        notes = session.notes ?? ""
        let entries = session.sortedEntries
        switch type {
        case .reps:
            exercises = entries.map { entry in
                var card = ExerciseCard()
                card.exerciseID = entry.exercise?.id
                card.name = entry.exercise?.name ?? ""
                card.equipment = entry.exercise.flatMap { $0.equipmentEnum } ?? Equipment.none
                let sets = entry.sortedSets
                card.sets = max(1, entry.plannedSets > 0 ? entry.plannedSets : sets.count)
                card.reps = sets.first?.plannedReps ?? sets.first?.reps ?? 10
                card.weight = sets.first?.weight ?? 0
                card.weightUnit = sets.first?.weightUnitEnum ?? .lb
                card.isTimed = entry.timerType == .forTime
                if let dur = sets.first?.duration { card.durationSeconds = Int(dur) }
                return card
            }
            // Restore superset links: consecutive entries sharing a group are linked.
            for i in exercises.indices where i + 1 < entries.count {
                let g = entries[i].supersetGroup
                if g != nil && g == entries[i + 1].supersetGroup {
                    exercises[i].linkedToNext = true
                }
            }
            if exercises.isEmpty { exercises = [ExerciseCard()] }
        case .amrap, .forTime:
            sessions = entries.map { entry in
                var card = SessionCard()
                card.name = entry.exercise?.name ?? ""
                card.equipment = entry.exercise.flatMap { $0.equipmentEnum } ?? Equipment.none
                let sets = entry.sortedSets
                card.reps = sets.first?.plannedReps ?? sets.first?.reps ?? 10
                card.weight = sets.first?.weight ?? 0
                card.weightUnit = sets.first?.weightUnitEnum ?? .lb
                return card
            }
            if sessions.isEmpty { sessions = [SessionCard()] }
        case .emom:
            emomSessions = entries.map { entry in
                var card = SessionCard()
                card.name = entry.exercise?.name ?? ""
                card.equipment = entry.exercise.flatMap { $0.equipmentEnum } ?? Equipment.none
                let sets = entry.sortedSets
                card.reps = sets.first?.plannedReps ?? sets.first?.reps ?? 10
                card.weight = sets.first?.weight ?? 0
                card.weightUnit = sets.first?.weightUnitEnum ?? .lb
                return card
            }
            if emomSessions.isEmpty { emomSessions = [SessionCard()] }
        case .intervals:
            intervalSessions = entries.map { entry in
                var card = SessionCard()
                card.name = entry.exercise?.name ?? ""
                card.equipment = entry.exercise.flatMap { $0.equipmentEnum } ?? Equipment.none
                let sets = entry.sortedSets
                card.weight = sets.first?.weight ?? 0
                card.weightUnit = sets.first?.weightUnitEnum ?? .lb
                return card
            }
            if intervalSessions.isEmpty { intervalSessions = [SessionCard()] }
        case .manual:
            manualSessions = entries.map { entry in
                var card = SessionCard()
                card.name = entry.exercise?.name ?? ""
                card.equipment = entry.exercise.flatMap { $0.equipmentEnum } ?? Equipment.none
                return card
            }
            if manualSessions.isEmpty { manualSessions = [SessionCard()] }
        }
        showWorkoutSetup = true
    }

    func repeatWorkout(session: WorkoutSession, context: ModelContext) {
        let newSession = WorkoutSession(name: session.name, workoutType: session.workoutType)
        context.insert(newSession)

        for entry in session.sortedEntries {
            let newEntry = WorkoutEntry(timerType: entry.timerType, sortOrder: entry.sortOrder)
            newEntry.session = newSession
            newEntry.exercise = entry.exercise
            context.insert(newEntry)
        }

        try? context.save()
        activeSession = newSession
        activeConfig  = TimerConfig.defaultConfig(for: session.timerType ?? .manual)
        showActiveWorkout = true
    }

    // MARK: - Active workout actions

    func logSet(
        exerciseIndex: Int,
        setIndex: Int,
        context: ModelContext
    ) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        guard setIndex < ex.sets.count else { return }

        ex.sets[setIndex].isCompleted = true
        activeExercises[exerciseIndex] = ex
        let set = ex.sets[setIndex]

        // Persist set record
        guard let session = activeSession else { return }
        let entry = session.sortedEntries.first { $0.exercise?.name.lowercased() == ex.name.lowercased() }

        let record: SetRecord
        if set.isTimed {
            let usesWeight = set.weight > 0
            record = SetRecord(
                setNumber: setIndex + 1,
                weight: usesWeight ? set.weight : nil,
                weightUnit: set.weightUnit,
                reps: nil,
                duration: TimeInterval(set.actualDuration),
                plannedWeight: usesWeight ? set.weight : nil,
                plannedReps: nil,
                plannedDuration: set.plannedDuration,
                setType: set.setType,
                rpe: set.rpe
            )
        } else {
            record = SetRecord(
                setNumber: setIndex + 1,
                weight: set.weight,
                weightUnit: set.weightUnit,
                reps: set.actualReps,
                plannedWeight: set.weight,
                plannedReps: set.plannedReps,
                setType: set.setType,
                rpe: set.rpe
            )
        }
        record.entry = entry
        context.insert(record)
        try? context.save()

        // PR detection (rep-based only; timed holds don't produce weight/rep/volume PRs)
        if !set.isTimed, let exercise = entry?.exercise {
            let prs = PRDetectionService.shared.checkAndRecord(set: record, exercise: exercise, context: context)
            if !prs.isEmpty {
                newPRTypes = prs
                prBannerMessage = "New PR! \(prs.map(\.label).joined(separator: ", "))"
                showPRBanner = true
                HapticManager.shared.personalRecord()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.showPRBanner = false
                }
            } else {
                HapticManager.shared.setLogged()
            }
        } else {
            HapticManager.shared.setLogged()
        }

        // Auto-finish the reps workout once every set has been completed.
        if !isShowingComplete && activeRepsAllComplete {
            completeWorkout(context: context)
        }
    }

    /// True when a reps workout has every set of every exercise completed.
    var activeRepsAllComplete: Bool {
        !activeExercises.isEmpty && activeExercises.allSatisfy { ex in
            !ex.sets.isEmpty && ex.sets.allSatisfy(\.isCompleted)
        }
    }

    func adjustWeight(exerciseIndex: Int, delta: Double) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        ex.weight = max(0, min(999, ex.weight + delta))
        for i in ex.sets.indices { ex.sets[i].weight = ex.weight }
        activeExercises[exerciseIndex] = ex
    }

    /// Updates a logged set's reps/duration, RPE and set type, persisting to the SetRecord.
    func updateSet(exerciseIndex: Int, setIndex: Int, repsOrDuration: Int, rpe: Double?, setType: SetType, context: ModelContext) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        guard setIndex < ex.sets.count else { return }
        let clamped = max(0, repsOrDuration)
        if ex.sets[setIndex].isTimed {
            ex.sets[setIndex].actualDuration = clamped
        } else {
            ex.sets[setIndex].actualReps = clamped
        }
        if clamped == 0 { ex.sets[setIndex].isCompleted = false }
        ex.sets[setIndex].rpe = rpe
        ex.sets[setIndex].setType = setType
        let isTimed = ex.sets[setIndex].isTimed
        activeExercises[exerciseIndex] = ex

        let setNumber = setIndex + 1
        let entry = activeSession?.sortedEntries.first { $0.exercise?.name.lowercased() == ex.name.lowercased() }
        if let record = entry?.sortedSets.first(where: { $0.setNumber == setNumber }) {
            if isTimed {
                record.duration = clamped > 0 ? TimeInterval(clamped) : nil
            } else {
                record.reps = clamped > 0 ? clamped : nil
            }
            record.rpe = rpe
            record.setType = setType
            try? context.save()
        }
    }

    func adjustReps(exerciseIndex: Int, setIndex: Int, newReps: Int, context: ModelContext? = nil) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        guard setIndex < ex.sets.count else { return }
        let clamped = max(0, newReps)
        let wasCompleted = ex.sets[setIndex].isCompleted
        if clamped == 0 {
            ex.sets[setIndex].isCompleted = false
        }
        ex.sets[setIndex].actualReps = clamped
        activeExercises[exerciseIndex] = ex

        // Update the persisted SetRecord when the set was already logged
        if wasCompleted, let ctx = context, let session = activeSession {
            let setNumber = setIndex + 1
            let entry = session.sortedEntries.first { $0.exercise?.name.lowercased() == ex.name.lowercased() }
            if let record = entry?.sortedSets.first(where: { $0.setNumber == setNumber }) {
                record.reps = clamped > 0 ? clamped : nil
                try? ctx.save()
            }
        }
    }

    func adjustDuration(exerciseIndex: Int, setIndex: Int, newDuration: Int, context: ModelContext? = nil) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        guard setIndex < ex.sets.count else { return }
        let clamped = max(0, newDuration)
        let wasCompleted = ex.sets[setIndex].isCompleted
        if clamped == 0 {
            ex.sets[setIndex].isCompleted = false
        }
        ex.sets[setIndex].actualDuration = clamped
        activeExercises[exerciseIndex] = ex

        // Update the persisted SetRecord when the set was already logged
        if wasCompleted, let ctx = context, let session = activeSession {
            let setNumber = setIndex + 1
            let entry = session.sortedEntries.first { $0.exercise?.name.lowercased() == ex.name.lowercased() }
            if let record = entry?.sortedSets.first(where: { $0.setNumber == setNumber }) {
                record.duration = clamped > 0 ? TimeInterval(clamped) : nil
                try? ctx.save()
            }
        }
    }

    func adjustSessionWeight(sessionIndex: Int, delta: Double) {
        guard sessionIndex < activeSessionCards.count else { return }
        let current = activeSessionCards[sessionIndex].weight
        activeSessionCards[sessionIndex].weight = max(0, min(999, current + delta))
    }

    /// Records an elapsed-time split (AMRAP round / For Time checkpoint).
    func recordSplit(_ seconds: TimeInterval, context: ModelContext) {
        guard let session = activeSession, seconds > 0 else { return }
        session.splits = session.splits + [seconds]   // reassign so SwiftData persists the change
        try? context.save()
    }

    // MARK: - Complete workout

    func completeWorkout(context: ModelContext) {
        guard let session = activeSession else { return }
        session.completedAt = Date()
        try? context.save()
        isShowingComplete = true
    }

    func endWorkout(context: ModelContext) {
        guard let session = activeSession else { return }
        if session.completedAt == nil {
            session.completedAt = Date()
        }
        try? context.save()
        activeSession = nil
        showActiveWorkout = false
        isShowingComplete = false
    }

    func discardWorkout(context: ModelContext) {
        if let session = activeSession {
            context.delete(session)
            try? context.save()
        }
        activeSession = nil
        showActiveWorkout = false
        isShowingComplete = false
    }

    // MARK: - Templates

    func saveAsTemplate(name: String, context: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            templateNameError = "Name cannot be empty"
            return false
        }

        // Check template limit
        let descriptor = FetchDescriptor<WorkoutTemplate>()
        let count = (try? context.fetch(descriptor).count) ?? 0
        let isPremium = userProfile?.isPremium ?? false
        if !isPremium && count >= UserProfile.maxFreeTemplates {
            templateNameError = "Upgrade to premium for more templates"
            return false
        }

        let template = WorkoutTemplate(name: trimmed)
        context.insert(template)

        if selectedTimerType == .reps {
            for (i, card) in exercises.enumerated() {
                let te = TemplateExercise(
                    exerciseName: card.name,
                    timerType: card.isTimed ? .forTime : .reps,
                    targetSets: card.sets,
                    targetReps: card.reps,
                    targetDuration: card.isTimed ? card.durationSeconds : 0,
                    sortOrder: i,
                    equipment: card.equipment == .none ? nil : card.equipment,
                    targetWeight: card.weight,
                    weightUnit: card.weightUnit,
                    linkedToNext: card.linkedToNext
                )
                te.template = template
                context.insert(te)
            }
        } else {
            let cards = activeSessions(for: selectedTimerType)
            for (i, card) in cards.enumerated() {
                let te = TemplateExercise(
                    exerciseName: card.name,
                    timerType: selectedTimerType,
                    targetSets: 3,
                    targetReps: card.reps,
                    sortOrder: i,
                    equipment: card.equipment == .none ? nil : card.equipment,
                    targetWeight: card.weight,
                    weightUnit: card.weightUnit
                )
                te.template = template
                context.insert(te)
            }
        }
        try? context.save()
        return true
    }

    /// Overwrites the exercises (and name) of the template the setup was loaded
    /// from with the current setup. Used by the "Update Workout" button.
    @discardableResult
    func updateTemplate(context: ModelContext) -> Bool {
        guard let template = editingTemplate else { return false }

        // Update the plan name from the setup field when provided.
        let trimmed = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { template.name = trimmed }

        // Replace the stored exercises with the current setup.
        for te in Array(template.exercises) { context.delete(te) }

        if selectedTimerType == .reps {
            for (i, card) in exercises.enumerated() {
                let te = TemplateExercise(
                    exerciseName: card.name,
                    timerType: card.isTimed ? .forTime : .reps,
                    targetSets: card.sets,
                    targetReps: card.reps,
                    targetDuration: card.isTimed ? card.durationSeconds : 0,
                    sortOrder: i,
                    equipment: card.equipment == .none ? nil : card.equipment,
                    targetWeight: card.weight,
                    weightUnit: card.weightUnit,
                    linkedToNext: card.linkedToNext
                )
                te.template = template
                context.insert(te)
            }
        } else {
            let cards = activeSessions(for: selectedTimerType)
            for (i, card) in cards.enumerated() {
                let te = TemplateExercise(
                    exerciseName: card.name,
                    timerType: selectedTimerType,
                    targetSets: 3,
                    targetReps: card.reps,
                    sortOrder: i,
                    equipment: card.equipment == .none ? nil : card.equipment,
                    targetWeight: card.weight,
                    weightUnit: card.weightUnit
                )
                te.template = template
                context.insert(te)
            }
        }
        template.lastUsedAt = Date()
        try? context.save()
        return true
    }

    func markTemplateUsed(_ template: WorkoutTemplate, context: ModelContext) {
        template.lastUsedAt = Date()
        try? context.save()
    }

    // MARK: - Helpers

    private func activeSessions(for type: TimerType) -> [SessionCard] {
        switch type {
        case .amrap, .forTime: return sessions
        case .emom:            return emomSessions
        case .intervals:       return intervalSessions
        case .manual:          return manualSessions
        case .reps:            return []
        }
    }

    /// Superset group index per exercise (nil = standalone). Consecutive cards
    /// linked via `linkedToNext` share an index; singleton groups return nil.
    private func supersetGroups() -> [Int?] {
        let n = exercises.count
        guard n > 0 else { return [] }
        var raw = Array(repeating: 0, count: n)
        var g = 0
        for i in 0..<n {
            raw[i] = g
            if i < n - 1 && !exercises[i].linkedToNext { g += 1 }
        }
        var counts: [Int: Int] = [:]
        for gid in raw { counts[gid, default: 0] += 1 }
        return raw.map { (counts[$0] ?? 0) > 1 ? $0 : nil }
    }

    private func findOrCreateExercise(id: UUID? = nil, name: String, equipment: Equipment, context: ModelContext) -> Exercise {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        // 1) Exact id match — the user picked this from the library/custom list.
        if let id, let found = all.first(where: { $0.id == id }) { return found }
        // 2) Normalized name match (case-insensitive, trimmed) so typed variants
        //    like "bench press" / "Bench Press " don't fork the history.
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()
        if !lower.isEmpty, let existing = all.first(where: { $0.name.lowercased() == lower }) {
            return existing
        }
        // 3) Create a new custom exercise.
        let ex = Exercise(name: normalized.isEmpty ? name : normalized,
                          equipment: equipment == .none ? nil : equipment, isCustom: true)
        context.insert(ex)
        return ex
    }

    func resetSetup() {
        editingTemplate = nil
        workoutName = ""
        notes = ""
        timeLimitMinutes = 10
        timeLimitSeconds = 0
        sessions = [SessionCard()]
        emomMinutes = 10
        emomSessions = [SessionCard()]
        workSeconds = 40
        restSeconds = 20
        intervalRounds = 8
        intervalSessions = [SessionCard()]
        // Seed rest-between-sets from the user's Settings default (falls back to 90s).
        restBetweenSets = Int(UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Double ?? 90)
        exercises = [ExerciseCard()]
        manualSessions = [SessionCard()]
    }
}

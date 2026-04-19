import Foundation
import SwiftData
import SwiftUI

// MARK: - Session Card (used in setup screen)
struct SessionCard: Identifiable {
    var id = UUID()
    var name: String = ""
    var equipment: Equipment = .none
    var weight: Double = 0
    var weightUnit: WeightUnit = .lb
}

// MARK: - Exercise Card (Reps setup)
struct ExerciseCard: Identifiable {
    var id = UUID()
    var name: String = ""
    var equipment: Equipment = .none
    var weight: Double = 0
    var weightUnit: WeightUnit = .lb
    var sets: Int = 3
    var reps: Int = 10
}

// MARK: - Active Set State
struct ActiveSet: Identifiable {
    var id: UUID
    var setNumber: Int
    var plannedReps: Int
    var actualReps: Int
    var isCompleted: Bool = false
    var weight: Double
    var weightUnit: WeightUnit
}

// MARK: - Active Exercise State
struct ActiveExercise: Identifiable {
    var id = UUID()
    var name: String
    var equipment: Equipment
    var weight: Double
    var weightUnit: WeightUnit
    var sets: [ActiveSet]

    init(from card: ExerciseCard) {
        self.name = card.name.isEmpty ? "Exercise" : card.name
        self.equipment = card.equipment
        self.weight = card.weight
        self.weightUnit = card.weightUnit
        self.sets = (0..<card.sets).map { i in
            ActiveSet(
                id: UUID(),
                setNumber: i + 1,
                plannedReps: card.reps,
                actualReps: card.reps,
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
    var showCreateWorkout     = false
    var showLogin             = false
    var showActiveWorkout     = false
    var showSaveTemplate      = false

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

    // User profile cache
    var userProfile: UserProfile?

    // MARK: - Setup helpers

    func loadFromTemplate(_ template: WorkoutTemplate, type: TimerType) {
        selectedTimerType = type
        workoutName = template.name
        let sorted = template.sortedExercises
        exercises = sorted.map { ex in
            var card = ExerciseCard()
            card.name = ex.exerciseName
            card.equipment = ex.equipment ?? .none
            card.weight = ex.targetWeight
            card.weightUnit = ex.weightUnit
            card.sets = ex.targetSets
            card.reps = ex.targetReps
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
            let exercise = findOrCreateExercise(name: exName, equipment: card.equipment, context: context)
            let entry = WorkoutEntry(timerType: selectedTimerType, sortOrder: i)
            entry.session = session
            entry.exercise = exercise
            context.insert(entry)
        }

        if selectedTimerType == .reps {
            for (i, card) in exercises.enumerated() {
                let exName = card.name.isEmpty ? "Exercise \(i + 1)" : card.name
                let exercise = findOrCreateExercise(name: exName, equipment: card.equipment, context: context)
                let entry = WorkoutEntry(timerType: .reps, sortOrder: i)
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
        }
        currentSessionIndex = 0
        completedRounds = 0
        isShowingComplete = false
        completionMessage = completionMessages.randomElement() ?? ""
        showActiveWorkout = true
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

        // Persist set record
        guard let session = activeSession else { return }
        let entry = session.sortedEntries.first { $0.exercise?.name.lowercased() == ex.name.lowercased() }

        let record = SetRecord(
            setNumber: setIndex + 1,
            weight: ex.sets[setIndex].weight,
            weightUnit: ex.sets[setIndex].weightUnit,
            reps: ex.sets[setIndex].actualReps,
            plannedWeight: ex.sets[setIndex].weight,
            plannedReps: ex.sets[setIndex].plannedReps
        )
        record.entry = entry
        context.insert(record)
        try? context.save()

        // PR detection
        if let exercise = entry?.exercise {
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
        }
    }

    func adjustWeight(exerciseIndex: Int, delta: Double) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        ex.weight = max(0, min(999, ex.weight + delta))
        for i in ex.sets.indices { ex.sets[i].weight = ex.weight }
        activeExercises[exerciseIndex] = ex
    }

    func adjustReps(exerciseIndex: Int, setIndex: Int, newReps: Int) {
        guard exerciseIndex < activeExercises.count else { return }
        var ex = activeExercises[exerciseIndex]
        guard setIndex < ex.sets.count else { return }
        let clamped = max(0, newReps)
        if clamped == 0 {
            ex.sets[setIndex].isCompleted = false
        }
        ex.sets[setIndex].actualReps = clamped
        activeExercises[exerciseIndex] = ex
    }

    func adjustSessionWeight(sessionIndex: Int, delta: Double) {
        guard sessionIndex < activeSessionCards.count else { return }
        let current = activeSessionCards[sessionIndex].weight
        activeSessionCards[sessionIndex].weight = max(0, min(999, current + delta))
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
        let cards = activeSessions(for: selectedTimerType)
        for (i, card) in cards.enumerated() {
            let te = TemplateExercise(
                exerciseName: card.name,
                timerType: selectedTimerType,
                targetSets: 3,
                targetReps: 10,
                sortOrder: i,
                equipment: card.equipment == .none ? nil : card.equipment,
                targetWeight: card.weight,
                weightUnit: card.weightUnit
            )
            te.template = template
            context.insert(te)
        }
        context.insert(template)
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

    private func findOrCreateExercise(name: String, equipment: Equipment, context: ModelContext) -> Exercise {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let ex = Exercise(name: name, equipment: equipment == .none ? nil : equipment, isCustom: true)
        context.insert(ex)
        return ex
    }

    func resetSetup() {
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
        restBetweenSets = 90
        exercises = [ExerciseCard()]
        manualSessions = [SessionCard()]
    }
}

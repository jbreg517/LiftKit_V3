import XCTest
import SwiftData
@testable import LiftKit

final class FeatureGapTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            Exercise.self, WorkoutSession.self, WorkoutEntry.self,
            SetRecord.self, PersonalRecord.self, WorkoutTemplate.self,
            TemplateExercise.self, UserProfile.self, WorkoutSchedule.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - SetRecord planned vs actual

    func testSetRecordTracksPlannedReps() {
        let record = SetRecord(setNumber: 1, reps: 8, plannedReps: 10)
        XCTAssertEqual(record.reps, 8)
        XCTAssertEqual(record.plannedReps, 10)
    }

    func testSetRecordTracksPlannedWeight() {
        let record = SetRecord(setNumber: 1, weight: 185, plannedWeight: 200)
        XCTAssertEqual(record.weight, 185)
        XCTAssertEqual(record.plannedWeight, 200)
    }

    func testSetRecordNilPlannedValues() {
        let record = SetRecord(setNumber: 1)
        XCTAssertNil(record.plannedWeight)
        XCTAssertNil(record.plannedReps)
    }

    // MARK: - Notes persistence

    func testWorkoutSessionStoresNotes() throws {
        let session = WorkoutSession(name: "Test", notes: "Push hard")
        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<WorkoutSession>()
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.first?.notes, "Push hard")
    }

    func testWorkoutNotesPassedFromSetupToSession() {
        let vm = WorkoutViewModel()
        vm.notes = "My notes"
        vm.workoutName = "Test"
        vm.selectedTimerType = .amrap
        vm.startTimedWorkout(context: context)
        XCTAssertEqual(vm.activeSession?.notes, "My notes")
    }

    func testWorkoutTypeSavedToSession() {
        let vm = WorkoutViewModel()
        vm.selectedTimerType = .intervals
        vm.workoutName = "Test"
        vm.startTimedWorkout(context: context)
        XCTAssertEqual(vm.activeSession?.workoutType, TimerType.intervals.rawValue)
        XCTAssertEqual(vm.activeSession?.timerType, .intervals)
    }

    // MARK: - WeightCache

    func testWeightCacheLookup() throws {
        let ex = Exercise(name: "Bench Press", equipment: .barbell)
        context.insert(ex)
        let session = WorkoutSession(name: "Test")
        context.insert(session)
        let entry = WorkoutEntry(timerType: .reps)
        entry.session = session
        entry.exercise = ex
        context.insert(entry)
        let set = SetRecord(setNumber: 1, weight: 185, weightUnit: .lb, reps: 8)
        set.entry = entry
        context.insert(set)
        try context.save()

        let result = WeightCache.shared.lookup(exerciseName: "Bench Press", in: context)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.weight, 185)
        XCTAssertEqual(result?.unit, .lb)
    }

    func testWeightCacheBatchLookup() throws {
        let ex1 = Exercise(name: "Squat")
        let ex2 = Exercise(name: "Deadlift")
        context.insert(ex1); context.insert(ex2)
        let session = WorkoutSession(name: "Legs")
        context.insert(session)

        for (ex, weight) in [(ex1, 200.0), (ex2, 315.0)] {
            let entry = WorkoutEntry(timerType: .reps)
            entry.session = session; entry.exercise = ex
            context.insert(entry)
            let set = SetRecord(setNumber: 1, weight: weight, reps: 5)
            set.entry = entry
            context.insert(set)
        }
        try context.save()

        let batch = WeightCache.shared.batchLookup(names: ["Squat", "Deadlift"], in: context)
        XCTAssertEqual(batch["squat"]?.weight, 200)
        XCTAssertEqual(batch["deadlift"]?.weight, 315)
    }

    func testWeightCacheMiss() {
        let result = WeightCache.shared.lookup(exerciseName: "Unicorn Curl", in: context)
        XCTAssertNil(result)
    }

    // MARK: - Template limits

    func testMaxTemplatesForNonPremium() throws {
        // Insert 5 templates already
        for i in 1...5 {
            let t = WorkoutTemplate(name: "Template \(i)")
            context.insert(t)
        }
        try context.save()

        let vm = WorkoutViewModel()
        let saved = vm.saveAsTemplate(name: "Sixth Template", context: context)
        XCTAssertFalse(saved)
    }

    func testPremiumCanSaveUnlimitedTemplates() throws {
        let profile = UserProfile(isPremium: true)
        context.insert(profile)
        for i in 1...6 {
            let t = WorkoutTemplate(name: "Template \(i)")
            context.insert(t)
        }
        try context.save()

        let vm = WorkoutViewModel()
        vm.userProfile = profile
        let saved = vm.saveAsTemplate(name: "Seventh Template", context: context)
        XCTAssertTrue(saved)
    }

    // MARK: - Completion messages

    func testCompletionMessagesExist() {
        XCTAssertGreaterThan(completionMessages.count, 10)
    }

    func testCompletionMessageRandom() {
        let msg = completionMessages.randomElement() ?? ""
        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(completionMessages.contains(msg))
    }

    // MARK: - Repeat workout

    func testRepeatWorkoutCreatesNewSession() throws {
        let session = WorkoutSession(name: "Push Day", workoutType: TimerType.reps.rawValue)
        context.insert(session)
        try context.save()

        let vm = WorkoutViewModel()
        vm.repeatWorkout(session: session, context: context)

        XCTAssertNotNil(vm.activeSession)
        XCTAssertNotEqual(vm.activeSession?.id, session.id)
        XCTAssertEqual(vm.activeSession?.name, session.name)
    }

    // MARK: - Template validation

    func testSaveAsTemplateRequiresName() {
        let vm = WorkoutViewModel()
        let saved = vm.saveAsTemplate(name: "", context: context)
        XCTAssertFalse(saved)
        XCTAssertFalse(vm.templateNameError.isEmpty)
    }

    func testSaveAsTemplateWhitespaceOnlyName() {
        let vm = WorkoutViewModel()
        let saved = vm.saveAsTemplate(name: "   ", context: context)
        XCTAssertFalse(saved)
    }

    func testSaveAsTemplateValidName() throws {
        let vm = WorkoutViewModel()
        let saved = vm.saveAsTemplate(name: "My Push Day", context: context)
        XCTAssertTrue(saved)

        let descriptor = FetchDescriptor<WorkoutTemplate>()
        let templates = try context.fetch(descriptor)
        XCTAssertTrue(templates.contains { $0.name == "My Push Day" })
    }

    // MARK: - Reps adjustment

    func testRepsCanBeAdjustedDuringWorkout() {
        let vm = WorkoutViewModel()
        vm.selectedTimerType = .reps
        vm.exercises = [ExerciseCard(name: "Squat", sets: 3, reps: 10)]
        vm.activeExercises = vm.exercises.map { ActiveExercise(from: $0) }

        vm.adjustReps(exerciseIndex: 0, setIndex: 0, newReps: 8)
        XCTAssertEqual(vm.activeExercises[0].sets[0].actualReps, 8)

        vm.adjustReps(exerciseIndex: 0, setIndex: 0, newReps: -1)
        XCTAssertEqual(vm.activeExercises[0].sets[0].actualReps, 0)
    }

    func testWeightCanBeAdjustedDuringWorkout() {
        let vm = WorkoutViewModel()
        vm.activeExercises = [ActiveExercise(from: ExerciseCard(name: "Bench", weight: 100))]

        vm.adjustWeight(exerciseIndex: 0, delta: 5)
        XCTAssertEqual(vm.activeExercises[0].weight, 105)

        vm.adjustWeight(exerciseIndex: 0, delta: -200)
        XCTAssertEqual(vm.activeExercises[0].weight, 0)
    }

    // MARK: - Scheduled workouts

    func testScheduledWorkoutCreation() throws {
        let sched = WorkoutSchedule(date: Date())
        context.insert(sched)
        try context.save()

        let descriptor = FetchDescriptor<WorkoutSchedule>()
        let results = try context.fetch(descriptor)
        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(results.first!.isCompleted)
    }

    func testScheduledWorkoutWithTemplate() throws {
        let template = WorkoutTemplate(name: "Leg Day")
        context.insert(template)
        let sched = WorkoutSchedule(date: Date(), template: template)
        context.insert(sched)
        try context.save()

        XCTAssertEqual(sched.displayName, "Leg Day")
    }

    // MARK: - UserProfile

    func testUserProfileCreation() throws {
        let profile = UserProfile(displayName: "Alex", email: "alex@test.com", authProvider: "apple", isPremium: true)
        context.insert(profile)
        try context.save()

        let descriptor = FetchDescriptor<UserProfile>()
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.first?.displayName, "Alex")
        XCTAssertEqual(results.first?.email, "alex@test.com")
        XCTAssertTrue(results.first?.isPremium ?? false)
    }

    func testUserProfileDefaultsNotPremium() {
        let profile = UserProfile()
        XCTAssertFalse(profile.isPremium)
        XCTAssertNil(profile.authProvider)
    }
}

// Make ExerciseCard test-initializable
extension ExerciseCard {
    init(name: String = "", weight: Double = 0, sets: Int = 3, reps: Int = 10) {
        self.init()
        self.name = name
        self.weight = weight
        self.sets = sets
        self.reps = reps
    }
}

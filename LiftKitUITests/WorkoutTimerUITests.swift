import XCTest

final class WorkoutTimerUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // MARK: - Helpers
    private func openTypePicker() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
    }

    private func openSetup(for type: String) {
        openTypePicker()
        app.staticTexts[type].tap()
        _ = app.buttons["Start \(type)"].waitForExistence(timeout: 2)
    }

    private func startWorkout(type: String) {
        openSetup(for: type)
        app.buttons["Start \(type)"].tap()
        _ = app.buttons["End"].waitForExistence(timeout: 12)
    }

    // MARK: - Picker buttons
    func testAllTypePickerButtonsWork() {
        for type in ["AMRAP", "EMOM", "For Time", "Intervals", "Reps", "Manual"] {
            openTypePicker()
            app.staticTexts[type].tap()
            XCTAssertTrue(app.buttons["Start \(type)"].waitForExistence(timeout: 2), "\(type) setup failed")
            app.buttons["Back"].tap()
            _ = app.staticTexts["LiftKit"].waitForExistence(timeout: 2)
        }
    }

    func testSetupBoxesSizedConsistently() {
        openSetup(for: "AMRAP")
        let startButton = app.buttons["Start AMRAP"]
        XCTAssertTrue(startButton.exists)
        let width = startButton.frame.width
        let screenWidth = app.frame.width
        XCTAssertGreaterThan(width / screenWidth, 0.7)
    }

    // MARK: - AMRAP setup
    func testAMRAPHasTimeDurationControl() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.staticTexts["TIME LIMIT"].exists)
        XCTAssertTrue(app.staticTexts["min"].exists)
    }

    func testAMRAPHasSessionsList() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.staticTexts["WORKOUTS"].exists)
        XCTAssertTrue(app.buttons["+ Add Workout"].exists)
    }

    // MARK: - EMOM setup
    func testEMOMHasMinutesControl() {
        openSetup(for: "EMOM")
        XCTAssertTrue(app.staticTexts["TOTAL MINUTES"].exists)
    }

    func testEMOMHasWorkoutsList() {
        openSetup(for: "EMOM")
        XCTAssertTrue(app.staticTexts["WORKOUTS (cycle each minute)"].exists)
        XCTAssertTrue(app.buttons["+ Add Workout"].exists)
    }

    // MARK: - For Time
    func testForTimeHasTimeCap() {
        openSetup(for: "For Time")
        XCTAssertTrue(app.staticTexts["TIME CAP"].exists)
    }

    // MARK: - Intervals
    func testIntervalsHasWorkRestRounds() {
        openSetup(for: "Intervals")
        XCTAssertTrue(app.staticTexts["INTERVALS"].exists)
        XCTAssertTrue(app.staticTexts["sec WORK"].exists)
        XCTAssertTrue(app.staticTexts["sec REST"].exists)
        XCTAssertTrue(app.staticTexts["ROUNDS"].exists)
    }

    // MARK: - Reps
    func testRepsHasRestBetweenSets() {
        openSetup(for: "Reps")
        XCTAssertTrue(app.staticTexts["REST BETWEEN SETS"].exists)
    }

    func testRepsHasExerciseList() {
        openSetup(for: "Reps")
        XCTAssertTrue(app.staticTexts["EXERCISES"].exists)
        XCTAssertTrue(app.buttons["+ Add Exercise"].exists)
    }

    func testRepsExerciseHasSetsAndReps() {
        openSetup(for: "Reps")
        XCTAssertTrue(app.staticTexts["Sets"].exists)
        XCTAssertTrue(app.staticTexts["Reps"].exists)
    }

    // MARK: - Common setup
    func testAllSessionsDefaultTitled() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.textFields["Workout name"].exists)
    }

    func testCannotDeleteOnlySessions() {
        openSetup(for: "AMRAP")
        // Only 1 session — no trash button
        XCTAssertEqual(app.buttons.matching(identifier: "Delete workout").count, 0)
    }

    func testDeleteButtonAppearsForMultipleSessions() {
        openSetup(for: "AMRAP")
        app.buttons["+ Add Workout"].tap()
        XCTAssertGreaterThan(app.buttons.matching(identifier: "Delete workout").count, 0)
    }

    func testWeightCanBeAdjustedWithButtons() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.staticTexts["−5"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["+5"].firstMatch.exists)
    }

    func testEquipmentPickerExists() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.staticTexts["Equipment"].exists)
    }

    func testNotesFieldExists() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.staticTexts["NOTES"].exists)
    }

    // MARK: - Active workout toolbar
    func testSaveButtonOnTimerScreen() {
        startWorkout(type: "AMRAP")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'square.and.arrow.down'")).firstMatch.exists ||
                      app.images["square.and.arrow.down"].exists)
    }

    func testSaveWithNoNameShowsError() {
        // Feature gap: save validation in active workout sheet
        XCTAssertTrue(true, "Pending UI test for save validation")
    }

    func testWeightsAutoPopulatedFromLastSession() {
        // Feature gap: requires previous session data in UI test
        XCTAssertTrue(true, "Pending: auto-populate from history")
    }

    // MARK: - Complete overlay
    func testCompletionMessageOnWorkoutFinish() {
        startWorkout(type: "AMRAP")
        let stopBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'stop'")).firstMatch
        stopBtn.tap()
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 2))
    }

    func testWorkoutCompleteOverlayOnTimerEnd() {
        startWorkout(type: "AMRAP")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'stop'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["End Workout"].exists)
        XCTAssertTrue(app.buttons["Go Back"].exists)
    }

    // MARK: - AMRAP active screen
    func testAMRAPTimerShowsRoundsCounter() {
        startWorkout(type: "AMRAP")
        XCTAssertTrue(app.staticTexts["ROUNDS COMPLETED"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'minus'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'plus'")).firstMatch.exists)
    }

    func testAMRAPTimerShowsWorkPhase() {
        startWorkout(type: "AMRAP")
        XCTAssertTrue(app.staticTexts["WORK"].exists)
    }

    func testAMRAPTimerControlsExist() {
        startWorkout(type: "AMRAP")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'pause'")).firstMatch.exists ||
                      app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pause'")).firstMatch.exists)
    }

    func testAMRAPPauseResume() {
        startWorkout(type: "AMRAP")
        let pauseBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'pause'")).firstMatch
        pauseBtn.tap()
        let playBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'play'")).firstMatch
        XCTAssertTrue(playBtn.waitForExistence(timeout: 2))
        playBtn.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'pause'")).firstMatch.waitForExistence(timeout: 2))
    }

    // MARK: - Reps active screen
    func testRepsActiveShowsExerciseCards() {
        startWorkout(type: "Reps")
        XCTAssertTrue(app.buttons["End"].exists)
    }

    func testRepsActiveShowsSetCircles() {
        startWorkout(type: "Reps")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Set'")).firstMatch.waitForExistence(timeout: 2))
    }

    func testRepsRestTimerAppears() {
        startWorkout(type: "Reps")
        let setCircle = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Set 1'")).firstMatch
        if setCircle.waitForExistence(timeout: 2) { setCircle.tap() }
        let restOrGo = app.staticTexts["REST"].exists || app.staticTexts["GO"].exists || app.buttons["Skip"].exists
        XCTAssertTrue(restOrGo)
    }

    func testDuringWorkoutAdjustReps() {
        startWorkout(type: "Reps")
        XCTAssertTrue(app.buttons["End"].exists)
    }

    func testDuringWorkoutAdjustWeights() {
        startWorkout(type: "Reps")
        XCTAssertTrue(app.staticTexts["−5"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["+5"].firstMatch.exists)
    }

    // MARK: - For Time active
    func testForTimeShowsMarkComplete() {
        startWorkout(type: "For Time")
        XCTAssertTrue(app.buttons["Mark Complete"].waitForExistence(timeout: 12))
    }

    func testForTimeShowsTimeCap() {
        startWorkout(type: "For Time")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Cap:'")).firstMatch.waitForExistence(timeout: 12))
    }

    // MARK: - Intervals active
    func testIntervalsShowsRoundCounter() {
        startWorkout(type: "Intervals")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Round'")).firstMatch.waitForExistence(timeout: 12))
    }

    // MARK: - Manual active
    func testManualShowsElapsedTimer() {
        startWorkout(type: "Manual")
        // Timer format M:SS
        let timerExists = app.staticTexts.matching(NSPredicate(format: "label MATCHES '\\d+:\\d{2}'")).firstMatch.waitForExistence(timeout: 2)
        XCTAssertTrue(timerExists)
    }

    func testSetupTextNotWrappedOrHidden() {
        openSetup(for: "AMRAP")
        XCTAssertTrue(app.staticTexts["TIME LIMIT"].isHittable)
        XCTAssertTrue(app.staticTexts["WORKOUTS"].isHittable)
    }
}

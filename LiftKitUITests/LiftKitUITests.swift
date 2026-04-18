import XCTest

final class LiftKitUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testAppLaunches() {
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Workout"].exists)
        XCTAssertTrue(app.tabBars.buttons["History"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testNavigateToSettings() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    func testNavigateToHistory() {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].exists)
    }

    func testNavigateToProgress() {
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].exists)
    }

    func testStartWorkoutOpensTypePicker() {
        app.buttons["Start Workout Timer"].tap()
        XCTAssertTrue(app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2))
    }

    func testTypePickerShowsAllTypes() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        XCTAssertTrue(app.staticTexts["AMRAP"].exists)
        XCTAssertTrue(app.staticTexts["EMOM"].exists)
        XCTAssertTrue(app.staticTexts["For Time"].exists)
        XCTAssertTrue(app.staticTexts["Intervals"].exists)
        XCTAssertTrue(app.staticTexts["Reps"].exists)
        XCTAssertTrue(app.staticTexts["Manual"].exists)
    }

    func testTypePickerCancel() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["LiftKit"].exists)
    }

    func testAMRAPSetupFlow() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["AMRAP"].tap()
        XCTAssertTrue(app.staticTexts["TIME LIMIT"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Start AMRAP"].exists)
    }

    func testAMRAPSetupBackButton() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["AMRAP"].tap()
        _ = app.buttons["Start AMRAP"].waitForExistence(timeout: 2)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["LiftKit"].waitForExistence(timeout: 2))
    }

    func testEMOMSetupFlow() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["EMOM"].tap()
        XCTAssertTrue(app.staticTexts["TOTAL MINUTES"].waitForExistence(timeout: 2))
    }

    func testForTimeSetupFlow() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["For Time"].tap()
        XCTAssertTrue(app.staticTexts["TIME CAP"].waitForExistence(timeout: 2))
    }

    func testIntervalsSetupFlow() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["Intervals"].tap()
        XCTAssertTrue(app.staticTexts["INTERVALS"].waitForExistence(timeout: 2))
    }

    func testRepsSetupFlow() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["Reps"].tap()
        XCTAssertTrue(app.staticTexts["REST BETWEEN SETS"].waitForExistence(timeout: 2))
    }

    func testManualSetupFlow() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["Manual"].tap()
        XCTAssertTrue(app.buttons["Start Manual"].waitForExistence(timeout: 2))
    }

    func testStartAMRAPWorkout() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["AMRAP"].tap()
        _ = app.buttons["Start AMRAP"].waitForExistence(timeout: 2)
        app.buttons["Start AMRAP"].tap()
        XCTAssertTrue(app.buttons["End"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["WORK"].exists)
        XCTAssertTrue(app.staticTexts["ROUNDS COMPLETED"].exists)
    }

    func testEndWorkoutConfirmation() {
        app.buttons["Start Workout Timer"].tap()
        _ = app.navigationBars["Choose Workout Type"].waitForExistence(timeout: 2)
        app.staticTexts["AMRAP"].tap()
        _ = app.buttons["Start AMRAP"].waitForExistence(timeout: 2)
        app.buttons["Start AMRAP"].tap()
        _ = app.buttons["End"].waitForExistence(timeout: 12)
        app.buttons["End"].tap()
        XCTAssertTrue(app.buttons["Save & End"].exists)
        XCTAssertTrue(app.buttons["Discard"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testAddNewWorkoutPlanButton() {
        app.buttons["Add New Workout Plan"].tap()
        XCTAssertTrue(app.navigationBars["New Workout"].waitForExistence(timeout: 2))
    }

    func testCreateWorkoutCancel() {
        app.buttons["Add New Workout Plan"].tap()
        _ = app.navigationBars["New Workout"].waitForExistence(timeout: 2)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["LiftKit"].waitForExistence(timeout: 2))
    }
}

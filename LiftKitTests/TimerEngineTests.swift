import XCTest
@testable import LiftKit

final class TimerEngineTests: XCTestCase {

    func testAMRAPStartsInWorkPhase() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .amrap)
        config.totalDuration = 600
        engine.start(config: config)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.timeRemaining, 600, accuracy: 1.0)
    }

    func testAMRAPSingleRound() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .amrap)
        config.totalDuration = 600
        engine.start(config: config)
        XCTAssertEqual(engine.totalRounds, 1)
        XCTAssertEqual(engine.currentRound, 1)
    }

    func testEMOMStartsWithCorrectRounds() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .emom)
        config.rounds = 10
        engine.start(config: config)
        XCTAssertEqual(engine.totalRounds, 10)
        XCTAssertEqual(engine.currentRound, 1)
    }

    func testEMOMSkipAdvancesRound() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .emom)
        config.rounds = 5
        engine.start(config: config)
        engine.skip()
        XCTAssertEqual(engine.currentRound, 2)
    }

    func testEMOMCompletesAfterAllRounds() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .emom)
        config.rounds = 2
        engine.start(config: config)
        engine.skip()
        engine.skip()
        XCTAssertEqual(engine.phase, .complete)
    }

    func testIntervalsStartsInWorkPhase() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .intervals)
        config.workDuration = 40
        config.restDuration = 20
        config.intervalRounds = 8
        engine.start(config: config)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.totalRounds, 8)
    }

    func testIntervalsWorkToRestTransition() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .intervals)
        config.workDuration = 40
        config.restDuration = 20
        config.intervalRounds = 3
        engine.start(config: config)
        engine.skip() // work → rest
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertEqual(engine.currentRound, 1)
    }

    func testIntervalsRestToNextWorkTransition() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .intervals)
        config.workDuration = 40
        config.restDuration = 20
        config.intervalRounds = 3
        engine.start(config: config)
        engine.skip() // work → rest
        engine.skip() // rest → work (round 2)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.currentRound, 2)
    }

    func testIntervalsCompletesAfterAllRounds() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .intervals)
        config.workDuration = 40
        config.restDuration = 20
        config.intervalRounds = 2
        engine.start(config: config)
        engine.skip(); engine.skip() // round 1 done
        engine.skip(); engine.skip() // round 2 done
        XCTAssertEqual(engine.phase, .complete)
    }

    func testRepsRestTimerStarts() {
        let engine = TimerEngine()
        engine.startRestTimer(90)
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertEqual(engine.timeRemaining, 90, accuracy: 1.0)
    }

    func testRepsRestTimerSkipCompletes() {
        let engine = TimerEngine()
        engine.startRestTimer(90)
        engine.skipRestTimer()
        XCTAssertEqual(engine.phase, .complete)
    }

    func testForTimeStartsCountUp() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .forTime)
        config.totalDuration = 1200
        engine.start(config: config)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.elapsedTime, 0, accuracy: 0.5)
    }

    func testManualStartsCountUp() {
        let engine = TimerEngine()
        let config = TimerConfig(type: .manual)
        engine.start(config: config)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.elapsedTime, 0, accuracy: 0.5)
    }

    func testPauseStopsRunning() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .amrap)
        config.totalDuration = 600
        engine.start(config: config)
        engine.pause()
        XCTAssertFalse(engine.isRunning)
        XCTAssertGreaterThan(engine.timeRemaining, 0)
    }

    func testResumeAfterPause() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .amrap)
        config.totalDuration = 600
        engine.start(config: config)
        engine.pause()
        let pausedRemaining = engine.timeRemaining
        engine.resume()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.timeRemaining, pausedRemaining, accuracy: 1.0)
    }

    func testStopResetsEverything() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .amrap)
        config.totalDuration = 600
        engine.start(config: config)
        engine.stop()
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.currentRound, 1)
        XCTAssertEqual(engine.timeRemaining, 0)
    }

    func testFormattedTime() {
        let engine = TimerEngine()
        var config = TimerConfig(type: .amrap)
        config.totalDuration = 600
        engine.start(config: config)
        XCTAssertTrue(engine.formattedTime.contains(":"))
    }

    func testTimerConfigTotalTime() {
        var intervalsConfig = TimerConfig(type: .intervals)
        intervalsConfig.workDuration = 40
        intervalsConfig.restDuration = 20
        intervalsConfig.intervalRounds = 8
        XCTAssertEqual(intervalsConfig.totalTime, 480, accuracy: 0.01)

        var amrapConfig = TimerConfig(type: .amrap)
        amrapConfig.totalDuration = 600
        XCTAssertEqual(amrapConfig.totalTime, 600, accuracy: 0.01)
    }

    func testDefaultConfigs() {
        for type in TimerType.allCases {
            let config = TimerConfig.defaultConfig(for: type)
            XCTAssertEqual(config.type, type, "Default config type mismatch for \(type.rawValue)")
        }
    }
}

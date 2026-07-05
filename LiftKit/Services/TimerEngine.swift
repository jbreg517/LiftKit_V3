import Foundation
import UserNotifications

// MARK: - Timer Config
struct TimerConfig {
    var type: TimerType
    // AMRAP / For Time / Manual
    var totalDuration: TimeInterval = 600
    // EMOM
    var rounds: Int = 10
    // Intervals
    var workDuration: TimeInterval = 40
    var restDuration: TimeInterval = 20
    var intervalRounds: Int = 8
    // Reps rest
    var restBetweenSets: TimeInterval = 90

    static func defaultConfig(for type: TimerType) -> TimerConfig {
        var c = TimerConfig(type: type)
        switch type {
        case .amrap:     c.totalDuration = 600
        case .emom:      c.rounds = 10
        case .forTime:   c.totalDuration = 1200
        case .intervals: c.workDuration = 40; c.restDuration = 20; c.intervalRounds = 8
        case .reps:      c.restBetweenSets = 90
        case .manual:    break
        }
        return c
    }

    var totalTime: TimeInterval {
        switch type {
        case .intervals: return (workDuration + restDuration) * Double(intervalRounds)
        case .amrap:     return totalDuration
        case .emom:      return Double(rounds) * 60
        case .forTime:   return totalDuration
        default:         return 0
        }
    }
}

// MARK: - Timer Engine
@Observable
final class TimerEngine {
    private(set) var phase: TimerPhase = .idle
    private(set) var timeRemaining: TimeInterval = 0
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var currentRound: Int = 1
    private(set) var totalRounds: Int = 1
    private(set) var isRunning: Bool = false
    private(set) var config: TimerConfig = TimerConfig(type: .manual)

    // Wall-clock anchors
    private(set) var phaseEndDate: Date?
    private var pausedTimeRemaining: TimeInterval?
    private var countUpStartDate: Date?
    private var pausedElapsed: TimeInterval?

    private var ticker: Timer?
    private var notificationPrefix: String

    var onPhaseChange: ((TimerPhase) -> Void)?
    var onComplete: (() -> Void)?
    var onTick: (() -> Void)?

    /// Title for the phase-change notifications shown while backgrounded
    /// (the workout's name; defaults to the app name).
    var notificationTitle: String = "LiftKit"
    /// Supplies "Bench Press · 10 reps · 135 lb"-style detail for the round
    /// that is starting, so backgrounded alerts carry the exercise, reps and
    /// weight alongside the minute/round number.
    var roundDetail: ((Int) -> String?)?

    // Sound
    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }
    /// Tracks which whole-second values have already had a countdown beep played
    private var beepedSeconds: Set<Int> = []
    private var countdownPlayed = false

    init(notificationPrefix: String = UUID().uuidString) {
        self.notificationPrefix = notificationPrefix
    }

    // MARK: - Public API

    func start(config: TimerConfig) {
        self.config = config
        stop()

        switch config.type {
        case .amrap:
            totalRounds = 1
            currentRound = 1
            startWorkPhase(duration: config.totalDuration)
        case .emom:
            totalRounds = config.rounds
            currentRound = 1
            startWorkPhase(duration: 60)
        case .forTime:
            startCountUp()
        case .intervals:
            totalRounds = config.intervalRounds
            currentRound = 1
            startWorkPhase(duration: config.workDuration)
        case .reps:
            phase = .idle
            isRunning = false
        case .manual:
            startCountUp()
        }

        ScreenSleepManager.shared.hold()
        scheduleNotifications()
    }

    func startRestTimer(_ duration: TimeInterval) {
        // The rest engine is created with a default `.manual` config, which makes
        // `tick()` count up. Force a countdown config so the rest timer actually
        // ticks down and completes (advancePhase → completePhase for `.reps`).
        config = TimerConfig(type: .reps)
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = duration
        phase = .rest
        isRunning = true
        countdownPlayed = false
        beepedSeconds = []
        startTicker()
        ScreenSleepManager.shared.hold()
        scheduleNotifications()
        HapticManager.shared.phaseStart()
        onPhaseChange?(.rest)
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        cancelNotifications()

        if config.type == .forTime || config.type == .manual {
            pausedElapsed = elapsedTime
        } else if phase == .work || phase == .rest {
            pausedTimeRemaining = phaseEndDate.map { max(0, $0.timeIntervalSinceNow) }
        }
    }

    func resume() {
        guard !isRunning else { return }
        isRunning = true

        if let remaining = pausedTimeRemaining, remaining > 0 {
            phaseEndDate = Date().addingTimeInterval(remaining)
            pausedTimeRemaining = nil
        } else if let elapsed = pausedElapsed {
            countUpStartDate = Date().addingTimeInterval(-elapsed)
            pausedElapsed = nil
        }

        startTicker()
        scheduleNotifications()
    }

    func skip() {
        cancelNotifications()
        advancePhase()
    }

    func stop() {
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        phase = .idle
        timeRemaining = 0
        elapsedTime = 0
        currentRound = 1
        phaseEndDate = nil
        countUpStartDate = nil
        pausedTimeRemaining = nil
        pausedElapsed = nil
        countdownPlayed = false
        beepedSeconds = []
        cancelNotifications()
        ScreenSleepManager.shared.release()
    }

    func skipRestTimer() {
        guard phase == .rest else { return }
        cancelNotifications()
        completePhase()
    }

    /// Adds/subtracts time from a running rest timer (e.g. −15s / +15s).
    func adjustRest(by delta: TimeInterval) {
        guard phase == .rest, let end = phaseEndDate else { return }
        let newEnd = max(Date(), end.addingTimeInterval(delta))
        phaseEndDate = newEnd
        timeRemaining = max(0, newEnd.timeIntervalSinceNow)
        beepedSeconds = []
    }

    // MARK: - Internal

    private func startWorkPhase(duration: TimeInterval) {
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = duration
        phase = .work
        isRunning = true
        countdownPlayed = false
        beepedSeconds = []
        startTicker()
        playPhaseBeep()
        HapticManager.shared.phaseStart()
        onPhaseChange?(.work)
    }

    private func startCountUp() {
        countUpStartDate = Date()
        elapsedTime = 0
        phase = .work
        isRunning = true
        startTicker()
        onPhaseChange?(.work)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    @objc private func tick() {
        switch config.type {
        case .forTime, .manual:
            if let start = countUpStartDate {
                elapsedTime = Date().timeIntervalSince(start)
            }
            onTick?()

        default:
            guard let endDate = phaseEndDate else { return }
            let remaining = max(0, endDate.timeIntervalSinceNow)
            timeRemaining = remaining

            // Countdown cues: play once per whole-second tick at 3, 2, 1
            if remaining <= 3.5 && remaining > 0 {
                let sec = Int(remaining.rounded(.up))
                if sec >= 1 && sec <= 3 && !beepedSeconds.contains(sec) {
                    beepedSeconds.insert(sec)
                    playCountdownBeep()
                    HapticManager.shared.countdownTick()
                }
            }

            onTick?()

            if remaining <= 0 {
                advancePhase()
            }
        }
    }

    private func advancePhase() {
        ticker?.invalidate()
        ticker = nil

        switch config.type {
        case .amrap:
            completePhase()

        case .emom:
            if currentRound < totalRounds {
                currentRound += 1
                startWorkPhase(duration: 60)
            } else {
                completePhase()
            }

        case .forTime:
            completePhase()

        case .intervals:
            if phase == .work {
                // Move to rest
                phase = .rest
                phaseEndDate = Date().addingTimeInterval(config.restDuration)
                timeRemaining = config.restDuration
                countdownPlayed = false
                beepedSeconds = []
                startTicker()
                playPhaseBeep()
                HapticManager.shared.phaseStart()
                onPhaseChange?(.rest)
            } else {
                // Rest finished — next round
                if currentRound < totalRounds {
                    currentRound += 1
                    startWorkPhase(duration: config.workDuration)
                } else {
                    completePhase()
                }
            }

        case .reps:
            completePhase()

        case .manual:
            completePhase()
        }
    }

    private func completePhase() {
        isRunning = false
        phase = .complete
        timeRemaining = 0
        cancelNotifications()
        ScreenSleepManager.shared.release()
        HapticManager.shared.timerComplete()
        onPhaseChange?(.complete)
        onComplete?()
    }

    // MARK: - Notifications

    private func scheduleNotifications() {
        cancelNotifications()
        let center = UNUserNotificationCenter.current()

        var notifications: [(TimeInterval, String, String)] = []

        switch config.type {
        case .amrap:
            if let end = phaseEndDate {
                let delta = end.timeIntervalSinceNow
                if delta > 0 {
                    notifications.append((delta, "\(notificationPrefix)-end", "AMRAP Complete!"))
                }
            }
        case .emom:
            if let end = phaseEndDate {
                let delta = end.timeIntervalSinceNow
                if delta > 0 {
                    for r in currentRound...totalRounds {
                        let offset = delta + Double(r - currentRound) * 60
                        if r < totalRounds {
                            // The alert fires as minute r ends, i.e. minute r+1
                            // begins — describe the exercise for that minute.
                            let detail = (roundDetail?(r + 1) ?? nil).map { " — \($0)" } ?? ""
                            notifications.append((offset, "\(notificationPrefix)-round-\(r)", "Minute \(r + 1) of \(totalRounds)\(detail)"))
                        } else {
                            notifications.append((offset, "\(notificationPrefix)-end", "EMOM Complete!"))
                        }
                    }
                }
            }
        case .intervals:
            var offset: TimeInterval = 0
            if let end = phaseEndDate {
                offset = end.timeIntervalSinceNow
            }
            if offset > 0 {
                let isWork = phase == .work
                var nextIsRest = isWork
                var round = currentRound
                var idx = 0
                while round <= totalRounds && idx < 30 {
                    let body: String
                    if nextIsRest {
                        body = "Rest!"
                    } else {
                        let detail = (roundDetail?(round) ?? nil).map { " — \($0)" } ?? ""
                        body = "Work!\(detail)"
                    }
                    notifications.append((offset, "\(notificationPrefix)-\(idx)", body))
                    offset += nextIsRest ? config.restDuration : config.workDuration
                    if !nextIsRest { round += 1 }
                    nextIsRest.toggle()
                    idx += 1
                }
            }
        case .forTime:
            let remaining = config.totalDuration - elapsedTime
            if remaining > 0 {
                notifications.append((remaining, "\(notificationPrefix)-end", "⏱ Time cap reached!"))
            }
        default:
            break
        }

        for (delay, id, body) in notifications {
            guard delay > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = notificationTitle
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func cancelNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: pendingIdentifiers()
        )
    }

    private func pendingIdentifiers() -> [String] {
        var ids: [String] = []
        ids.append("\(notificationPrefix)-end")
        for i in 0..<40 {
            ids.append("\(notificationPrefix)-\(i)")
        }
        for i in 1...60 {
            ids.append("\(notificationPrefix)-round-\(i)")
        }
        return ids
    }

    // MARK: - Sound

    private func playCountdownBeep() {
        guard soundEnabled else { return }
        SoundEngine.shared.playCountdownTick()
    }

    private func playPhaseBeep() {
        guard soundEnabled else { return }
        SoundEngine.shared.playPhaseStart()
    }

    // MARK: - Background restore

    func restoreFromBackground() {
        guard isRunning else { return }
        cancelNotifications()

        switch config.type {
        case .forTime, .manual:
            if let start = countUpStartDate {
                elapsedTime = Date().timeIntervalSince(start)
            }
        case .intervals:
            fastForwardIntervals()
        case .emom:
            fastForwardEMOM()
        default:
            if let end = phaseEndDate {
                timeRemaining = max(0, end.timeIntervalSinceNow)
                if timeRemaining <= 0 {
                    completePhase()
                }
            }
        }

        scheduleNotifications()
    }

    private func fastForwardIntervals() {
        guard let endDate = phaseEndDate else { return }
        var simulatedEnd = endDate
        var simulatedPhase = phase
        var simulatedRound = currentRound

        while simulatedEnd.timeIntervalSinceNow < 0 {
            if simulatedPhase == .work {
                simulatedPhase = .rest
                simulatedEnd = simulatedEnd.addingTimeInterval(config.restDuration)
            } else {
                simulatedRound += 1
                if simulatedRound > totalRounds {
                    completePhase()
                    return
                }
                simulatedPhase = .work
                simulatedEnd = simulatedEnd.addingTimeInterval(config.workDuration)
            }
        }

        phase = simulatedPhase
        currentRound = simulatedRound
        phaseEndDate = simulatedEnd
        timeRemaining = max(0, simulatedEnd.timeIntervalSinceNow)
        onPhaseChange?(simulatedPhase)
    }

    private func fastForwardEMOM() {
        guard let endDate = phaseEndDate else { return }
        var simulatedEnd = endDate
        var simulatedRound = currentRound

        while simulatedEnd.timeIntervalSinceNow < 0 {
            simulatedRound += 1
            if simulatedRound > totalRounds {
                completePhase()
                return
            }
            simulatedEnd = simulatedEnd.addingTimeInterval(60)
        }

        currentRound = simulatedRound
        phaseEndDate = simulatedEnd
        timeRemaining = max(0, simulatedEnd.timeIntervalSinceNow)
    }

    // MARK: - Helpers

    var formattedTime: String {
        let t: TimeInterval
        if config.type == .forTime || config.type == .manual {
            t = elapsedTime
        } else {
            t = timeRemaining
        }
        return Self.format(t)
    }

    static func format(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let mins  = total / 60
        let secs  = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}


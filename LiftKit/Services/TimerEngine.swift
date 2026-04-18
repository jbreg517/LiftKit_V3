import Foundation
import UserNotifications
import AVFoundation

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
    private var phaseEndDate: Date?
    private var pausedTimeRemaining: TimeInterval?
    private var countUpStartDate: Date?
    private var pausedElapsed: TimeInterval?

    private var ticker: Timer?
    private var notificationPrefix: String

    var onPhaseChange: ((TimerPhase) -> Void)?
    var onComplete: (() -> Void)?
    var onTick: (() -> Void)?

    // Sound
    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }
    private var audioPlayer: AVAudioPlayer?
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
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = duration
        phase = .rest
        isRunning = true
        countdownPlayed = false
        startTicker()
        ScreenSleepManager.shared.hold()
        scheduleNotifications()
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
        cancelNotifications()
        ScreenSleepManager.shared.release()
    }

    func skipRestTimer() {
        guard phase == .rest else { return }
        cancelNotifications()
        completePhase()
    }

    // MARK: - Internal

    private func startWorkPhase(duration: TimeInterval) {
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = duration
        phase = .work
        isRunning = true
        countdownPlayed = false
        startTicker()
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

            // Countdown beeps in last 3 seconds
            if remaining <= 3 && remaining > 0 && soundEnabled && !countdownPlayed {
                playBeep()
                countdownPlayed = remaining <= 1
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
                startTicker()
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
                            notifications.append((offset, "\(notificationPrefix)-round-\(r)", "Minute \(r + 1)!"))
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
                    notifications.append((offset, "\(notificationPrefix)-\(idx)", nextIsRest ? "Rest!" : "Work!"))
                    offset += nextIsRest ? config.restDuration : config.workDuration
                    if !nextIsRest { round += 1 }
                    nextIsRest.toggle()
                    idx += 1
                }
            }
        default:
            break
        }

        for (delay, id, body) in notifications {
            guard delay > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "LiftKit"
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

    private func playBeep() {
        guard soundEnabled else { return }
        // Use system sound for countdown
        AudioServicesPlaySystemSound(1057)
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

// AVFoundation system sound
import AudioToolbox

import UIKit

final class ScreenSleepManager {
    static let shared = ScreenSleepManager()
    private init() {}

    private var holdCount = 0

    func hold() {
        holdCount += 1
        updateIdleTimer()
    }

    func release() {
        holdCount = max(0, holdCount - 1)
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = self.holdCount > 0
        }
    }
}

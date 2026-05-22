import UIKit

final class HapticManager {
    static let shared = HapticManager()
    private init() {}

    private let light  = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    func buttonTap() {
        guard isEnabled else { return }
        light.impactOccurred()
    }

    func setLogged() {
        guard isEnabled else { return }
        medium.impactOccurred()
    }

    func personalRecord() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func timerComplete() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    /// Short light pulse — each 3-2-1 countdown tick
    func countdownTick() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.55)
    }

    /// Slightly heavier pulse — new phase or minute begins
    func phaseStart() {
        guard isEnabled else { return }
        medium.impactOccurred(intensity: 0.75)
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
}

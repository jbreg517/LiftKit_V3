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

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
}

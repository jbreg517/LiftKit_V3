import Foundation
import Observation
import WatchConnectivity

/// Holds the menu the phone last sent.
///
/// No local persistence of its own — `WCSession.receivedApplicationContext` already
/// survives relaunch, so the last menu is on disk for free and there is no second
/// copy to fall out of step with the first.
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()

    /// What the phone last sent. Empty until the first sync.
    private(set) var menu = WatchMenu()
    /// True once any menu has arrived. Distinguishes "nothing scheduled and no saved
    /// plans" from "never synced" — different empty states, and telling someone to
    /// open their phone when they've simply saved nothing would be wrong.
    private(set) var hasSynced = false

    var unit: UnitSystem { menu.unit }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            adopt(session.receivedApplicationContext)
        }
    }

    /// Tell the phone this watch has started or finished a workout, so it warns
    /// rather than recording the same session twice.
    ///
    /// Best-effort by design: out of range there is no message and no error worth
    /// showing. Training with the phone in a locker is a case this must not obstruct.
    func announce(active: Bool, label: String) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(WorkoutOwner.message(active: active, label: label),
                            replyHandler: nil) { _ in }
    }

    /// Decodes a context payload into the published menu. Ignores anything it can't
    /// read, so a malformed or future payload leaves the last good menu in place
    /// rather than blanking the screen mid-workout.
    private func adopt(_ context: [String: Any]) {
        guard let decoded = WatchLink.decode(WatchMenu.self, from: context[WatchLink.menuKey]) else { return }
        DispatchQueue.main.async {
            self.menu = decoded
            self.hasSynced = true
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchStore: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        guard state == .activated else { return }
        // The context the system was already holding — this is what makes the menu
        // present at launch instead of blank until the phone next pushes.
        adopt(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        adopt(context)
    }

    /// The phone telling us it started or finished a workout.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { WorkoutOwner.shared.handle(message: message) }
    }
}

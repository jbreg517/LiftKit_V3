import Foundation
import Observation

/// Tracks whether the *other* device currently has a workout running.
///
/// Both the phone and the watch can run a workout, and they must never run the same
/// one at once: two recordings means two workouts in Apple Health and double the
/// active energy, which then flows into FuelKit as real intake headroom. Nothing can
/// deduplicate that afterwards — by then there are two legitimate-looking workouts
/// from two sources.
///
/// The rule is simply **whichever device you tapped Start on owns the session**, and
/// only that device writes to Health. The other says what's running and offers
/// nothing else.
///
/// ## What this can and cannot do
///
/// It is a courtesy signal over `sendMessage`, which only arrives when the two
/// devices are in contact. Out of range neither knows about the other and both will
/// happily start. That is *correct* for the case this exists to serve — training with
/// the phone in a locker — and the realistic failure it prevents is the common one:
/// both devices on you, and you forget the watch is already going.
///
/// So this is a guard, not a lock. It deliberately does not block starting; it tells
/// the user what's already running and lets them decide. A hard block that depended
/// on connectivity would strand someone mid-workout.
///
/// Modelled on RunKit's `RecordingOwner`, which solves the identical problem.
@Observable
final class WorkoutOwner {
    static let shared = WorkoutOwner()
    private init() {}

    /// Set when the counterpart device says it started, cleared when it says it
    /// stopped. Never set from this device's own state.
    private(set) var otherDeviceIsActive = false
    /// What the other device says it's running, for the banner text.
    private(set) var otherDeviceLabel = ""

    /// Apply an incoming `sendMessage` payload. Ignores anything that isn't ours, so
    /// an unrelated message can't clear the flag.
    func handle(message: [String: Any]) {
        guard let active = message[WatchLink.activeKey] as? Bool else { return }
        otherDeviceIsActive = active
        otherDeviceLabel = (message[WatchLink.activeLabelKey] as? String) ?? ""
    }

    /// The payload announcing this device's state to the other one.
    static func message(active: Bool, label: String) -> [String: Any] {
        [WatchLink.activeKey: active, WatchLink.activeLabelKey: label]
    }

    /// Clears the flag locally — used when this device takes ownership anyway, so a
    /// stale "the watch is running" banner doesn't linger over a workout the user
    /// deliberately started here.
    func clear() {
        otherDeviceIsActive = false
        otherDeviceLabel = ""
    }
}

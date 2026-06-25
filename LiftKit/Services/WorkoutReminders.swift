import Foundation
import UserNotifications

/// Local reminders for scheduled workouts. Everything stays on-device — no data
/// leaves the phone. Each `WorkoutSchedule` maps to one calendar-triggered
/// notification keyed by the schedule's id, so it can be cancelled when the
/// workout is cleared or completed.
enum WorkoutReminders {
    private static let idPrefix = "workout-schedule-"

    /// User toggle (default on) and fire hour (default 8 AM). Shared with the
    /// @AppStorage-backed controls in Settings via the same UserDefaults keys.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "workoutRemindersEnabled") as? Bool ?? true
    }

    static var reminderHour: Int {
        let h = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 8
        return (0...23).contains(h) ? h : 8
    }

    /// Schedules a single reminder, skipping past fire times and disabled state.
    static func schedule(_ schedule: WorkoutSchedule) {
        guard isEnabled, !schedule.isCompleted else { return }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: schedule.date)
        comps.hour = reminderHour
        comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Workout Today"
        content.body = "\(schedule.displayName) is on your plan."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id(for: schedule), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Removes the reminder for one schedule (on swipe-clear or start).
    static func cancel(_ schedule: WorkoutSchedule) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(for: schedule)])
    }

    /// Re-applies reminders for the given schedules, removing each first so a
    /// changed reminder time takes effect without duplicating. Used by Settings.
    static func reschedule(_ schedules: [WorkoutSchedule]) {
        let ids = schedules.map(id(for:))
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        guard isEnabled else { return }
        for s in schedules { schedule(s) }
    }

    /// Removes every pending workout reminder (when the feature is turned off).
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func id(for schedule: WorkoutSchedule) -> String {
        idPrefix + schedule.id.uuidString
    }
}

import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var notes: String?
    var workoutType: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.session)
    var entries: [WorkoutEntry]

    init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        notes: String? = nil,
        workoutType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.workoutType = workoutType
        self.entries = []
    }

    var duration: TimeInterval {
        guard let end = completedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return end.timeIntervalSince(startedAt)
    }

    var isActive: Bool { completedAt == nil }

    var totalVolume: Double {
        entries.flatMap { $0.sets }.compactMap { set -> Double? in
            guard let w = set.weight, let r = set.reps else { return nil }
            let lbs = set.weightUnit == WeightUnit.kg.rawValue ? w * 2.20462 : w
            return lbs * Double(r)
        }.reduce(0, +)
    }

    var timerType: TimerType? {
        guard let t = workoutType else { return nil }
        return TimerType(rawValue: t)
    }

    var sortedEntries: [WorkoutEntry] {
        entries.sorted { $0.sortOrder < $1.sortOrder }
    }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        if mins >= 60 {
            let hrs = mins / 60
            let m = mins % 60
            return "\(hrs)h \(m)m"
        }
        return secs > 0 && mins == 0 ? "\(secs)s" : "\(mins)m"
    }
}

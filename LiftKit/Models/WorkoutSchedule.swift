import Foundation
import SwiftData

@Model
final class WorkoutSchedule {
    var id: UUID = UUID()
    var date: Date = Date()
    var customName: String?
    var notes: String?
    var isCompleted: Bool = false
    /// Links the occurrences created together by one recurring schedule so the
    /// whole series can be managed (e.g. cancelled) as a unit. nil for one-off
    /// schedules. Optional with a nil default keeps this a lightweight,
    /// CloudKit-compatible migration.
    var seriesID: UUID?

    var template: WorkoutTemplate?

    init(
        id: UUID = UUID(),
        date: Date,
        template: WorkoutTemplate? = nil,
        customName: String? = nil,
        notes: String? = nil,
        isCompleted: Bool = false,
        seriesID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.template = template
        self.customName = customName
        self.notes = notes
        self.isCompleted = isCompleted
        self.seriesID = seriesID
    }

    var displayName: String {
        template?.name ?? customName ?? "Workout"
    }
}

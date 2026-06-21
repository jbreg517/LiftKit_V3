import Foundation
import SwiftData

@Model
final class WorkoutSchedule {
    var id: UUID = UUID()
    var date: Date = Date()
    var customName: String?
    var notes: String?
    var isCompleted: Bool = false

    var template: WorkoutTemplate?

    init(
        id: UUID = UUID(),
        date: Date,
        template: WorkoutTemplate? = nil,
        customName: String? = nil,
        notes: String? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.date = date
        self.template = template
        self.customName = customName
        self.notes = notes
        self.isCompleted = isCompleted
    }

    var displayName: String {
        template?.name ?? customName ?? "Workout"
    }
}

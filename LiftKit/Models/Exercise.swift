import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID
    var name: String
    var category: String
    var equipment: String?
    var notes: String?
    var isCustom: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntry.exercise)
    var entries: [WorkoutEntry]

    @Relationship(deleteRule: .nullify, inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord]

    init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory = .custom,
        equipment: Equipment? = nil,
        notes: String? = nil,
        isCustom: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category.rawValue
        self.equipment = equipment?.rawValue
        self.notes = notes
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.entries = []
        self.personalRecords = []
    }

    var categoryEnum: ExerciseCategory {
        ExerciseCategory(rawValue: category) ?? .custom
    }

    var equipmentEnum: Equipment? {
        guard let e = equipment else { return nil }
        return Equipment(rawValue: e)
    }
}

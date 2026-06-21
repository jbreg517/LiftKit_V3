import Foundation
import SwiftData

@Model
final class Exercise {
    // All non-optional attributes carry defaults and relationships are optional
    // so the schema is CloudKit-compatible (private-database sync, opt-in).
    var id: UUID = UUID()
    var name: String = ""
    var category: String = ExerciseCategory.custom.rawValue
    var equipment: String?
    var notes: String?
    var isCustom: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntry.exercise)
    var entries: [WorkoutEntry] = []

    @Relationship(deleteRule: .nullify, inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord] = []

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

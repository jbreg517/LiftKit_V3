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
    /// Primary muscle group for volume analytics (nil = untagged).
    var primaryMuscleRaw: String?
    /// Additional muscles this exercise also works (e.g. bench → shoulders, triceps).
    var secondaryMusclesRaw: [String] = []

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

    var primaryMuscle: MuscleGroup? {
        get { primaryMuscleRaw.flatMap { MuscleGroup(rawValue: $0) } }
        set { primaryMuscleRaw = newValue?.rawValue }
    }

    var secondaryMuscles: [MuscleGroup] {
        get { secondaryMusclesRaw.compactMap { MuscleGroup(rawValue: $0) } }
        set { secondaryMusclesRaw = newValue.map { $0.rawValue } }
    }

    /// Primary + secondary muscles for display (primary first, no duplicates).
    var allMuscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        return ([primaryMuscle].compactMap { $0 } + secondaryMuscles).filter { seen.insert($0).inserted }
    }

    /// Per-muscle set credit: the primary muscle gets a full set, each secondary
    /// muscle counts as half. Used by the muscle-balance analytics.
    var muscleContributions: [(muscle: MuscleGroup, weight: Double)] {
        var result: [(muscle: MuscleGroup, weight: Double)] = []
        if let p = primaryMuscle { result.append((muscle: p, weight: 1.0)) }
        for s in secondaryMuscles where s != primaryMuscle { result.append((muscle: s, weight: 0.5)) }
        return result
    }
}

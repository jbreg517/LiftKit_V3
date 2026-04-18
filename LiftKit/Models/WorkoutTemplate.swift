import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastUsedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise]

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSchedule.template)
    var schedules: [WorkoutSchedule]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.exercises = []
        self.schedules = []
    }

    var sortedExercises: [TemplateExercise] {
        exercises.sorted { $0.sortOrder < $1.sortOrder }
    }
}

@Model
final class TemplateExercise {
    var id: UUID
    var timerTypeRaw: String
    var timerConfigData: Data?
    var targetSets: Int
    var targetReps: Int
    var sortOrder: Int
    var exerciseName: String
    var equipmentRaw: String?
    var targetWeight: Double
    var weightUnitRaw: String

    var template: WorkoutTemplate?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        timerType: TimerType = .reps,
        targetSets: Int = 3,
        targetReps: Int = 10,
        sortOrder: Int = 0,
        equipment: Equipment? = nil,
        targetWeight: Double = 0,
        weightUnit: WeightUnit = .lb
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.timerTypeRaw = timerType.rawValue
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.sortOrder = sortOrder
        self.equipmentRaw = equipment?.rawValue
        self.targetWeight = targetWeight
        self.weightUnitRaw = weightUnit.rawValue
    }

    var timerType: TimerType {
        TimerType(rawValue: timerTypeRaw) ?? .reps
    }

    var equipment: Equipment? {
        guard let e = equipmentRaw else { return nil }
        return Equipment(rawValue: e)
    }

    var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }
}

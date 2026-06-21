import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSchedule.template)
    var schedules: [WorkoutSchedule] = []

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
    var id: UUID = UUID()
    var timerTypeRaw: String = TimerType.reps.rawValue
    var timerConfigData: Data?
    var targetSets: Int = 3
    var targetReps: Int = 10
    /// Hold time in seconds for timed exercises (e.g. planks). 0 = rep-based.
    var targetDuration: Int = 0
    var sortOrder: Int = 0
    var exerciseName: String = ""
    var equipmentRaw: String?
    var targetWeight: Double = 0
    var weightUnitRaw: String = WeightUnit.lb.rawValue

    var template: WorkoutTemplate?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        timerType: TimerType = .reps,
        targetSets: Int = 3,
        targetReps: Int = 10,
        targetDuration: Int = 0,
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
        self.targetDuration = targetDuration
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

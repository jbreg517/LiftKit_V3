import Foundation
import SwiftData

final class PRDetectionService {
    static let shared = PRDetectionService()
    private init() {}

    /// Checks a newly logged set against existing PRs.
    /// Returns a list of new PRType values that were beaten.
    @discardableResult
    func checkAndRecord(
        set: SetRecord,
        exercise: Exercise,
        context: ModelContext
    ) -> [PRType] {
        var newPRs: [PRType] = []
        let existingPRs = exercise.personalRecords

        // Max Weight
        if let weight = set.weight {
            let lbs = set.weightUnitEnum == .kg ? weight * 2.20462 : weight
            let current = existingPRs.filter { $0.prType == .maxWeight }.map(\.value).max() ?? 0
            if lbs > current {
                let pr = PersonalRecord(type: .maxWeight, value: lbs, achievedAt: set.completedAt, setRecordId: set.id)
                pr.exercise = exercise
                context.insert(pr)
                newPRs.append(.maxWeight)
            }
        }

        // Max Reps
        if let reps = set.reps {
            let current = existingPRs.filter { $0.prType == .maxReps }.map(\.value).max() ?? 0
            if Double(reps) > current {
                let pr = PersonalRecord(type: .maxReps, value: Double(reps), achievedAt: set.completedAt, setRecordId: set.id)
                pr.exercise = exercise
                context.insert(pr)
                newPRs.append(.maxReps)
            }
        }

        // Max Volume
        let vol = set.volume
        if vol > 0 {
            let current = existingPRs.filter { $0.prType == .maxVolume }.map(\.value).max() ?? 0
            if vol > current {
                let pr = PersonalRecord(type: .maxVolume, value: vol, achievedAt: set.completedAt, setRecordId: set.id)
                pr.exercise = exercise
                context.insert(pr)
                newPRs.append(.maxVolume)
            }
        }

        try? context.save()
        return newPRs
    }
}

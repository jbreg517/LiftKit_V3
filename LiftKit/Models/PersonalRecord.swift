import Foundation
import SwiftData

@Model
final class PersonalRecord {
    var id: UUID = UUID()
    var type: String = PRType.maxWeight.rawValue
    var value: Double = 0
    var achievedAt: Date = Date()
    var setRecordId: UUID?

    var exercise: Exercise?

    init(
        id: UUID = UUID(),
        type: PRType,
        value: Double,
        achievedAt: Date = Date(),
        setRecordId: UUID? = nil
    ) {
        self.id = id
        self.type = type.rawValue
        self.value = value
        self.achievedAt = achievedAt
        self.setRecordId = setRecordId
    }

    var prType: PRType {
        PRType(rawValue: type) ?? .maxWeight
    }
}

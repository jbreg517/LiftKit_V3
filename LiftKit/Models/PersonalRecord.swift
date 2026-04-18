import Foundation
import SwiftData

@Model
final class PersonalRecord {
    var id: UUID
    var type: String
    var value: Double
    var achievedAt: Date
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

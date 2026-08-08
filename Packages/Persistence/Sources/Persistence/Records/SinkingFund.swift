import Foundation
import GRDB

// MARK: - SinkingFund (ERD Section 5)
// Money set aside gradually toward a known future expense (car service,
// annual insurance). `currentAmount` is incremented manually or via a
// linked category's contributions (Phase 4). The optional categoryId is the
// link the ERD models as "CATEGORY saves toward SINKING_FUND".
public struct SinkingFund: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "sinkingFund"

    public var id: Int64?
    public var name: String
    public var targetAmount: Decimal
    public var targetDate: Date
    public var currentAmount: Decimal
    public var categoryId: Int64?

    public init(
        id: Int64? = nil,
        name: String,
        targetAmount: Decimal,
        targetDate: Date,
        currentAmount: Decimal,
        categoryId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.currentAmount = currentAmount
        self.categoryId = categoryId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

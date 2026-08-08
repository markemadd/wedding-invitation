import Foundation
import GRDB

// MARK: - Income (ERD Section 5)
// Deliberately a singleton row (id fixed at 1): the blueprint's decision is
// a single current salary with no history. Updating income overwrites the
// row; there is no income timeline table to keep in sync.
public struct Income: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "income"

    public var id: Int64 = 1
    public var amount: Decimal
    public var currency: String
    public var updatedAt: Date

    public init(amount: Decimal, currency: String, updatedAt: Date) {
        self.amount = amount
        self.currency = currency
        self.updatedAt = updatedAt
    }
}

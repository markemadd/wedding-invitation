import Foundation
import GRDB

// MARK: - CategoryAllocation (ERD Section 5)
// One row per category in the salary-allocation budget. `percentage` is a
// fraction (0.30 = 30%), and the set of all rows must sum to exactly 1 —
// enforced by SalaryAllocationService.validateAllocations (Phase 3) BEFORE
// any write, never by the database itself, so the error can carry a helpful
// "you have 13% left to allocate" message.
public struct CategoryAllocation: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "categoryAllocation"

    public var id: Int64?
    public var categoryId: Int64
    public var percentage: Decimal

    public init(id: Int64? = nil, categoryId: Int64, percentage: Decimal) {
        self.id = id
        self.categoryId = categoryId
        self.percentage = percentage
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

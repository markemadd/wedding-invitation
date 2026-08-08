import Foundation
import GRDB

// MARK: - Category (ERD Section 5)
// Spending classification. `bucket` (fixed / nonMonthlyRecurring / flexible)
// is chosen at creation time — Phase 4's goal-planner cut suggestions depend
// on it. `parentCategoryId` allows an optional hierarchy (e.g. "Groceries"
// under "Food"); it is nullable and self-referencing.
public struct Category: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "category"

    public var id: Int64?
    public var name: String
    public var bucket: CategoryBucket
    public var parentCategoryId: Int64?

    public init(id: Int64? = nil, name: String, bucket: CategoryBucket, parentCategoryId: Int64? = nil) {
        self.id = id
        self.name = name
        self.bucket = bucket
        self.parentCategoryId = parentCategoryId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

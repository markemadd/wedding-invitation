import Foundation
import GRDB

// MARK: - RecurringSeries (ERD Section 5)
// A confirmed recurring pattern (subscription, bill, salary transfer).
// Rows are only created after the user confirms a detection candidate from
// Phase 4's RecurringDetectionService — never auto-created silently, since
// false positives with only 3 data points are inevitable.
public struct RecurringSeries: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "recurringSeries"

    public var id: Int64?
    public var merchantPattern: String
    public var categoryId: Int64
    public var intervalDays: Int
    public var expectedAmount: Decimal
    /// 0...1 heuristic confidence from the detector — kept so the UI can
    /// sort "most certain" candidates first.
    public var confidence: Decimal

    public init(
        id: Int64? = nil,
        merchantPattern: String,
        categoryId: Int64,
        intervalDays: Int,
        expectedAmount: Decimal,
        confidence: Decimal
    ) {
        self.id = id
        self.merchantPattern = merchantPattern
        self.categoryId = categoryId
        self.intervalDays = intervalDays
        self.expectedAmount = expectedAmount
        self.confidence = confidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

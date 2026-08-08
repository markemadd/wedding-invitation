import Foundation
import GRDB

// MARK: - ReceiptItem (migration v5, post-blueprint)
// One line item from a scanned receipt, linked to its transaction
// (cascade-deleted with it). The point is price history: the same item
// name across receipts/merchants over time.
public struct ReceiptItem: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "receiptItem"

    public var id: Int64?
    public var transactionId: Int64
    public var name: String
    public var price: Decimal

    public init(id: Int64? = nil, transactionId: Int64, name: String, price: Decimal) {
        self.id = id
        self.transactionId = transactionId
        self.name = name
        self.price = price
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

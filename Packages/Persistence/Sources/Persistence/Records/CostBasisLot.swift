import Foundation
import GRDB

// MARK: - CostBasisLot (ERD Section 5)
// One purchase of a holding: quantity at a price on a date. Gains/losses
// math (Phase 5) sums over lots; the accounting method for partial sales
// (FIFO vs. specific-lot) is decided in Phase 5 before that code is written.
public struct CostBasisLot: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "costBasisLot"

    public var id: Int64?
    public var holdingId: Int64
    public var quantity: Decimal
    public var purchasePrice: Decimal
    public var purchaseDate: Date

    public init(
        id: Int64? = nil,
        holdingId: Int64,
        quantity: Decimal,
        purchasePrice: Decimal,
        purchaseDate: Date
    ) {
        self.id = id
        self.holdingId = holdingId
        self.quantity = quantity
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

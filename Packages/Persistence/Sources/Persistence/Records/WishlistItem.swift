import Foundation
import GRDB

// MARK: - WishlistItem (ERD Section 5)
// A thing you want. Like Goal, deliberately unlinked from other tables —
// time-to-save is computed live from the current average savings rate and
// income (Phase 4), never cached on the row where it would go stale.
public struct WishlistItem: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "wishlistItem"

    public var id: Int64?
    public var name: String
    public var price: Decimal
    public var createdAt: Date

    public init(id: Int64? = nil, name: String, price: Decimal, createdAt: Date) {
        self.id = id
        self.name = name
        self.price = price
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

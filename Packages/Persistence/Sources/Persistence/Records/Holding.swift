import Foundation
import GRDB

// MARK: - Holding (ERD Section 5)
// One investment position (a ticker). `assetClass` is manually maintained
// per ticker (e.g. "US equity", "bond", "crypto") — the self-built
// approximation of a fund-analysis breakdown from blueprint 5.3. Purchase
// history lives in CostBasisLot rows, one per buy.
public struct Holding: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "holding"

    public var id: Int64?
    public var ticker: String
    public var assetClass: String
    public var currency: String

    public init(id: Int64? = nil, ticker: String, assetClass: String, currency: String) {
        self.id = id
        self.ticker = ticker
        self.assetClass = assetClass
        self.currency = currency
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

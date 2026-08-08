import Foundation
import GRDB

// MARK: - NetWorthSnapshot (ERD Section 5)
// A dated record of total assets/liabilities/net worth, captured
// periodically so the dashboard can chart a trend without recomputing
// history (which would change retroactively as old transactions are
// edited — a snapshot freezes what the number actually was that day).
public struct NetWorthSnapshot: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "netWorthSnapshot"

    public var id: Int64?
    public var date: Date
    public var totalAssets: Decimal
    public var totalLiabilities: Decimal
    public var netWorth: Decimal

    public init(
        id: Int64? = nil,
        date: Date,
        totalAssets: Decimal,
        totalLiabilities: Decimal,
        netWorth: Decimal
    ) {
        self.id = id
        self.date = date
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
        self.netWorth = netWorth
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

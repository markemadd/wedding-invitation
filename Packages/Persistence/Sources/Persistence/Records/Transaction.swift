import Foundation
import GRDB

// MARK: - Transaction (ERD Section 5)
// The central table everything else aggregates over. Note the type is named
// `Transaction` per the blueprint; at call sites that also import SwiftUI
// (which has its own `Transaction`), qualify as `Persistence.Transaction`.
public struct Transaction: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "transaction"

    public var id: Int64?
    public var accountId: Int64
    public var categoryId: Int64
    /// Set once Phase 4's recurring detection links this transaction to a
    /// confirmed series; nil for one-off spending.
    public var recurringSeriesId: Int64?
    public var amount: Decimal
    public var currency: String
    public var date: Date
    public var merchant: String?
    public var source: TransactionSource
    /// Money out (expense) or in (income). Defaults to expense — the only
    /// direction that existed before InstaPay support (migration v4).
    public var direction: TransactionDirection

    public init(
        id: Int64? = nil,
        accountId: Int64,
        categoryId: Int64,
        recurringSeriesId: Int64? = nil,
        amount: Decimal,
        currency: String,
        date: Date,
        merchant: String? = nil,
        source: TransactionSource,
        direction: TransactionDirection = .expense
    ) {
        self.id = id
        self.accountId = accountId
        self.categoryId = categoryId
        self.recurringSeriesId = recurringSeriesId
        self.amount = amount
        self.currency = currency
        self.date = date
        self.merchant = merchant
        self.source = source
        self.direction = direction
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

import Foundation
import GRDB

// MARK: - Account (ERD Section 5)
// A place money lives: bank account, cash wallet, etc. `balance` is a
// Decimal — GRDB stores Decimal as exact TEXT in SQLite (POSIX-locale
// string via NSDecimalNumber), never as binary floating point, which is
// the blueprint's non-negotiable money rule.
public struct Account: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "account"

    public var id: Int64?
    public var name: String
    public var type: String
    public var currency: String
    public var balance: Decimal
    /// The last 4 digits of the card/account (privacy: never the full
    /// number). Used to auto-route an incoming bank SMS to the right
    /// account when the message prints "…****1234". nil = unset.
    public var last4: String?

    public init(id: Int64? = nil, name: String, type: String, currency: String,
                balance: Decimal, last4: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.balance = balance
        self.last4 = last4
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

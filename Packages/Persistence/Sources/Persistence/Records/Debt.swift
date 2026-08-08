import Foundation
import GRDB

// MARK: - Debt (ERD Section 5)
// A fixed-term loan tracked with the standard amortization formula
// (Phase 4's AmortizationCalculator). Standalone by design; can optionally
// reference an Account in a later schema version if payments should flow
// through a tracked account.
public struct Debt: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "debt"

    public var id: Int64?
    public var name: String
    public var principal: Decimal
    /// Annual interest rate in percent (e.g. 21.5 for 21.5% APR).
    public var interestRate: Decimal
    public var termMonths: Int
    public var startDate: Date

    public init(
        id: Int64? = nil,
        name: String,
        principal: Decimal,
        interestRate: Decimal,
        termMonths: Int,
        startDate: Date
    ) {
        self.id = id
        self.name = name
        self.principal = principal
        self.interestRate = interestRate
        self.termMonths = termMonths
        self.startDate = startDate
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

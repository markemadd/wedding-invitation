import Foundation
import GRDB

// MARK: - InstallmentPlan (ENHANCEMENTS Wave B1)
// A "buy now, pay later" / financed-purchase plan (ValU, Halan, contact,
// etc.) — a fixed monthly amount over a known number of installments. Kept
// separate from RecurringSeries because an installment plan is finite and
// tracks progress (paidCount of totalInstallments), whereas a series is an
// open-ended subscription. Money fields are exact Decimal-as-TEXT, per the
// no-binary-float money rule.
public struct InstallmentPlan: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "installmentPlan"

    public var id: Int64?
    public var name: String
    /// e.g. "ValU", "Halan" — the financing provider, nil for informal plans.
    public var providerName: String?
    public var monthlyAmount: Decimal
    public var totalInstallments: Int
    public var paidCount: Int
    public var startDate: Date
    public var currency: String

    public init(
        id: Int64? = nil,
        name: String,
        providerName: String? = nil,
        monthlyAmount: Decimal,
        totalInstallments: Int,
        paidCount: Int = 0,
        startDate: Date,
        currency: String = "EGP"
    ) {
        self.id = id
        self.name = name
        self.providerName = providerName
        self.monthlyAmount = monthlyAmount
        self.totalInstallments = totalInstallments
        self.paidCount = paidCount
        self.startDate = startDate
        self.currency = currency
    }

    /// Remaining balance = per-installment × installments left. Exact
    /// Decimal arithmetic, no floats.
    public var remainingAmount: Decimal {
        monthlyAmount * Decimal(max(0, totalInstallments - paidCount))
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

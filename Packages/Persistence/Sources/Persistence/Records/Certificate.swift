import Foundation
import GRDB

// MARK: - Certificate (شهادة) — recurring bank-interest deposit
// A bank certificate/deposit that pays a fixed interest amount into an
// account every month until it matures. Modeled as recurring INCOME with a
// known monthly amount and a maturity date, so Mizan can show the next
// deposit, count down to maturity, and (on the user's tap or an auto-
// detected SMS) log each month's interest to the linked account. Money is
// Decimal-as-TEXT, per the ledger rule.
public struct Certificate: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "certificate"

    public var id: Int64?
    public var name: String
    public var bankName: String?
    /// The deposited principal (informational — interest is what pays out).
    public var principal: Decimal
    /// The fixed interest paid into the account each month.
    public var monthlyInterest: Decimal
    public var startDate: Date
    public var maturityDate: Date
    /// The account the interest deposits into (nil until the user links one).
    public var accountId: Int64?
    public var currency: String
    /// First day of the last month whose interest was logged — guards
    /// against double-logging the same month. nil = nothing logged yet.
    public var lastLoggedMonth: Date?

    public init(
        id: Int64? = nil,
        name: String,
        bankName: String? = nil,
        principal: Decimal,
        monthlyInterest: Decimal,
        startDate: Date,
        maturityDate: Date,
        accountId: Int64? = nil,
        currency: String = "EGP",
        lastLoggedMonth: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.bankName = bankName
        self.principal = principal
        self.monthlyInterest = monthlyInterest
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.accountId = accountId
        self.currency = currency
        self.lastLoggedMonth = lastLoggedMonth
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Whether the certificate is still before its maturity date.
    public var isActive: Bool { maturityDate > Date() }

    /// Whole months left until maturity (0 once matured).
    public var monthsToMaturity: Int {
        max(0, Calendar.current.dateComponents([.month], from: Date(), to: maturityDate).month ?? 0)
    }

    /// This month's interest hasn't been logged yet and the certificate is
    /// active — so a "Log this month's interest" action is offered.
    public var isThisMonthUnlogged: Bool {
        guard isActive, let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start else {
            return false
        }
        guard let last = lastLoggedMonth else { return true }
        return last < monthStart
    }
}

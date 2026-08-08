import Foundation
import GRDB
import Persistence

// MARK: - CurrencyConverter
// Converts any amount to EGP through the fxRate table (Phase 3's
// conversion decision). Every aggregate in Budgeting/SavingsAndGoals/
// Forecasting converts through HERE, so the rule lives in one place.
public struct CurrencyConverter {
    /// currencyCode → EGP-per-unit, loaded once per computation pass so a
    /// summary over thousands of transactions does O(1) dictionary lookups
    /// per row, not a query per row.
    private let rates: [String: Decimal]

    public init(db: Database) throws {
        let all = try FxRate.fetchAll(db)
        self.rates = Dictionary(uniqueKeysWithValues: all.map { ($0.currencyCode, $0.rateToEGP) })
    }

    init(rates: [String: Decimal]) {
        self.rates = rates
    }

    /// Missing rate = treat as already-EGP and report it, rather than
    /// silently dropping the transaction from totals or crashing a
    /// dashboard. The UI surfaces unknown codes so the user adds a rate.
    public func toEGP(_ amount: Decimal, from currencyCode: String) -> Decimal {
        guard let rate = rates[currencyCode] else { return amount }
        return amount * rate
    }

    public func hasRate(for currencyCode: String) -> Bool {
        rates[currencyCode] != nil
    }
}

import Foundation
import GRDB
import Persistence

// MARK: - Allocation validation (blueprint Phase 3.3)

public enum AllocationError: Error, LocalizedError, Equatable {
    case doesNotSumToWhole(currentTotal: Decimal)

    public var errorDescription: String? {
        switch self {
        case .doesNotSumToWhole(let total):
            return "Your category allocations must total 100%. They currently total \(total * 100)%."
        }
    }
}

/// Percentages are fractions (0.30 = 30%) and must sum to EXACTLY 1.
/// Decimal is exact — no epsilon tolerance needed, unlike Double.
/// Time complexity O(n), n = number of categories, one linear pass.
public func validateAllocations(_ allocations: [CategoryAllocation]) throws {
    let total = allocations.reduce(Decimal(0)) { $0 + $1.percentage }
    guard total == Decimal(1) else {
        throw AllocationError.doesNotSumToWhole(currentTotal: total)
    }
}

// MARK: - SalaryAllocationService (blueprint Phase 3.3)
// Single current salary (Income singleton row), percentage allocations per
// category, and the monthly allocated/spent/remaining summary every later
// phase builds on (savings, goals, review).
public final class SalaryAllocationService {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    public func setIncome(amount: Decimal, currency: String) throws {
        try databaseManager.dbQueue().write { db in
            var income = Income(amount: amount, currency: currency, updatedAt: Date())
            try income.save(db) // Singleton row id=1: save() inserts or updates.
        }
    }

    public func currentIncome() throws -> Income? {
        try databaseManager.dbQueue().read { db in
            try Income.fetchOne(db, key: 1)
        }
    }

    /// Replaces the full allocation set atomically. Validates BEFORE
    /// writing — never leaves a half-saved, inconsistent budget.
    public func setAllocations(_ allocations: [CategoryAllocation]) throws {
        try validateAllocations(allocations)
        try databaseManager.dbQueue().write { db in
            // Full replace keeps "the set sums to 100%" true as a whole —
            // patching rows individually could pass row-level checks while
            // breaking the set invariant.
            try CategoryAllocation.deleteAll(db)
            for allocation in allocations {
                var row = CategoryAllocation(categoryId: allocation.categoryId, percentage: allocation.percentage)
                try row.insert(db)
            }
        }
    }

    public func currentAllocations() throws -> [CategoryAllocation] {
        try databaseManager.dbQueue().read { db in
            try CategoryAllocation.fetchAll(db)
        }
    }

    public struct CategoryAllocationSummary: Identifiable {
        public let category: Persistence.Category
        /// All amounts in EGP (converted through the fxRate table).
        public let allocated: Decimal
        public let spent: Decimal
        public let remaining: Decimal

        public var id: Int64? { category.id }
        public var percentUsed: Decimal { allocated == 0 ? 0 : (spent / allocated) * 100 }
    }

    /// One grouped SQL aggregate rather than looping through every
    /// transaction and summing per category by hand: O(n + k) instead of
    /// O(n × k), n = this month's transactions, k = categories. Only the
    /// current month is scanned thanks to the (categoryId, date) index
    /// from Phase 1, so this stays fast years into the app's life.
    /// Grouped by (categoryId, currency) so multi-currency months convert
    /// exactly, per-currency, through CurrencyConverter.
    public func monthlySummary(for month: Date) throws -> [CategoryAllocationSummary] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return try monthlySummary(in: interval)
    }

    /// Same per-category allocated/spent/remaining summary as
    /// `monthlySummary(for:)`, but over an arbitrary window — used by the
    /// budget rings when the user anchors budgets to a pay cycle instead of
    /// the calendar month. Allocations themselves are monthly amounts.
    public func monthlySummary(in interval: DateInterval) throws -> [CategoryAllocationSummary] {
        return try databaseManager.dbQueue().read { db in
            guard let income = try Income.fetchOne(db, key: 1) else { return [] }
            let converter = try CurrencyConverter(db: db)

            let spentRows = try Row.fetchAll(db, sql: """
                SELECT categoryId, currency, direction,
                       GROUP_CONCAT(amount, '|') AS amounts
                FROM "transaction"
                WHERE date >= ? AND date < ?
                GROUP BY categoryId, currency, direction
                """, arguments: [interval.start, interval.end])

            // SQLite's SUM over TEXT would go through binary floats, so the
            // exact per-group total is recomputed from the concatenated
            // Decimal strings. O(n) total across all groups — the SQL
            // grouping did the heavy lifting; this pass just adds exactly.
            // NET per category: income (e.g. incoming InstaPay) subtracts
            // from spending, so transfers in/out cancel toward zero.
            var spentByCategory: [Int64: Decimal] = [:]
            for row in spentRows {
                guard let categoryId: Int64 = row["categoryId"] else { continue }
                let currency: String = row["currency"] ?? "EGP"
                let direction: String = row["direction"] ?? "expense"
                let amounts: String = row["amounts"] ?? ""
                let exactSum = amounts.split(separator: "|")
                    .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                    .reduce(Decimal(0), +)
                let egp = converter.toEGP(exactSum, from: currency)
                spentByCategory[categoryId, default: 0] += (direction == "income" ? -egp : egp)
            }

            let allocations = try CategoryAllocation.fetchAll(db)
            let categories = try Persistence.Category.fetchAll(db)
            let categoryById = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                category.id.map { ($0, category) }
            })

            return allocations.compactMap { allocation -> CategoryAllocationSummary? in
                guard let category = categoryById[allocation.categoryId] else { return nil }
                let allocated = income.amount * allocation.percentage
                let spent = spentByCategory[allocation.categoryId] ?? Decimal(0)
                return CategoryAllocationSummary(
                    category: category,
                    allocated: allocated,
                    spent: spent,
                    remaining: allocated - spent
                )
            }
        }
    }

    /// Each category's share of total spending over the trailing window —
    /// the "observation month" feature: spend freely first, then let the
    /// app PROPOSE allocations from how money actually behaved, instead
    /// of guessing percentages up front. Deliberately plain arithmetic,
    /// not a learned model: with one user's data, historical share IS the
    /// best estimator, and it's explainable at a glance (same philosophy
    /// as the Phase 4 heuristics). Returns fractions summing to ~1.
    /// O(n) over the window's transactions, grouped in SQL.
    public func categorySpendShares(trailingMonths: Int) throws -> [Int64: Decimal] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .month, value: -trailingMonths, to: Date()) else { return [:] }
        return try databaseManager.dbQueue().read { db in
            let converter = try CurrencyConverter(db: db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT categoryId, currency, direction, GROUP_CONCAT(amount, '|') AS amounts
                FROM "transaction"
                WHERE date >= ?
                GROUP BY categoryId, currency, direction
                """, arguments: [start])
            var totals: [Int64: Decimal] = [:]
            for row in rows {
                guard let categoryId: Int64 = row["categoryId"] else { continue }
                let currency: String = row["currency"] ?? "EGP"
                let direction: String = row["direction"] ?? "expense"
                let amounts: String = row["amounts"] ?? ""
                let exactSum = amounts.split(separator: "|")
                    .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                    .reduce(Decimal(0), +)
                let egp = converter.toEGP(exactSum, from: currency)
                totals[categoryId, default: 0] += (direction == "income" ? -egp : egp)
            }
            // A net-negative category (received more than sent) is not
            // "spending" — clamp it out of the allocation proposal.
            let clamped = totals.mapValues { max(0, $0) }
            let grandTotal = clamped.values.reduce(Decimal(0), +)
            guard grandTotal > 0 else { return [:] }
            return clamped.mapValues { $0 / grandTotal }
        }
    }

    /// Total spent this month in EGP across ALL categories (allocated or
    /// not) — the honest "money out" figure for the dashboard and savings
    /// math; unallocated categories still cost real money.
    public func totalSpent(for month: Date) throws -> Decimal {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        return try databaseManager.dbQueue().read { db in
            let converter = try CurrencyConverter(db: db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT currency, direction, GROUP_CONCAT(amount, '|') AS amounts
                FROM "transaction"
                WHERE date >= ? AND date < ?
                GROUP BY currency, direction
                """, arguments: [interval.start, interval.end])
            // NET spending: incoming money (InstaPay receives) reduces the
            // month's total outflow — "increases the allowance".
            var total = Decimal(0)
            for row in rows {
                let currency: String = row["currency"] ?? "EGP"
                let direction: String = row["direction"] ?? "expense"
                let amounts: String = row["amounts"] ?? ""
                let exactSum = amounts.split(separator: "|")
                    .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                    .reduce(Decimal(0), +)
                let egp = converter.toEGP(exactSum, from: currency)
                total += (direction == "income" ? -egp : egp)
            }
            return total
        }
    }

    /// Gross discretionary spend for the monthly-budget cap (Home card +
    /// safe-to-spend widget). Unlike `totalSpent` — which nets ALL income and
    /// feeds savings/story/cuts — this counts expenses and lets ONLY
    /// transfer-style money-in reduce the total: internal 'Transfer' legs are
    /// ignored entirely (moving your own money isn't spending), and 'instapay'
    /// receives add back to the allowance. Salary and other income do NOT
    /// reduce it, so the budget reflects what was actually spent.
    public func budgetConsumed(for month: Date) throws -> Decimal {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        return try budgetConsumed(in: interval)
    }

    /// Same discretionary-spend total as `budgetConsumed(for:)`, over an
    /// arbitrary window — used by the Home budget card and safe-to-spend
    /// widget when budgets are anchored to a pay cycle, not the calendar month.
    public func budgetConsumed(in interval: DateInterval) throws -> Decimal {
        return try databaseManager.dbQueue().read { db in
            let converter = try CurrencyConverter(db: db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.name AS category, t.direction AS direction, t.currency AS currency,
                       GROUP_CONCAT(t.amount, '|') AS amounts
                FROM "transaction" t
                LEFT JOIN category c ON c.id = t.categoryId
                WHERE t.date >= ? AND t.date < ?
                GROUP BY c.name, t.direction, t.currency
                """, arguments: [interval.start, interval.end])
            var total = Decimal(0)
            for row in rows {
                let category: String = row["category"] ?? ""
                let direction: String = row["direction"] ?? "expense"
                let currency: String = row["currency"] ?? "EGP"
                let amounts: String = row["amounts"] ?? ""
                // Internal account transfers aren't spending — skip either leg.
                if category == "Transfer" { continue }
                let exactSum = amounts.split(separator: "|")
                    .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                    .reduce(Decimal(0), +)
                let egp = converter.toEGP(exactSum, from: currency)
                if direction == "expense" {
                    total += egp
                } else if category == "instapay" {
                    // InstaPay received adds back to the allowance; salary and
                    // other income do NOT reduce the budget.
                    total -= egp
                }
            }
            return total
        }
    }
}

import Foundation
import GRDB
import Budgeting
import Persistence

// MARK: - SavingsAndGoalsService (blueprint Phase 4.4)
// Savings = income − total spent (via Budgeting's converted totals, never
// recomputed here). Goal evaluation produces PROACTIVE cut suggestions —
// a specific number per category, not just a red bar. Methodology note:
// showing concrete progress and a specific next step drives follow-through
// more than a static indicator (goal-gradient effect; Kivetz, Urminsky &
// Zheng, 2006).
public final class SavingsAndGoalsService {
    private let databaseManager: DatabaseManager
    private let allocationService: SalaryAllocationService
    /// "Life-energy cost" basis: working days per month (Robin &
    /// Dominguez, "Your Money or Your Life", 1992/rev. 2018).
    private let workingDaysPerMonth = Decimal(22)
    /// Trailing window smooths one-off spikes without going stale.
    private let trailingWindowMonths = 3

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
        self.allocationService = SalaryAllocationService(databaseManager: databaseManager)
    }

    /// Income minus ALL spending that month (allocated or not), in EGP.
    public func savings(for month: Date) throws -> Decimal {
        guard let income = try allocationService.currentIncome() else { return 0 }
        return income.amount - (try allocationService.totalSpent(for: month))
    }

    /// O(trailingWindowMonths) month queries, each index-bounded.
    public func averageMonthlySavings() throws -> Decimal {
        let calendar = Calendar.current
        var total = Decimal(0)
        var months = 0
        for offset in 0..<trailingWindowMonths {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: Date()) else { continue }
            total += try savings(for: date)
            months += 1
        }
        return months > 0 ? total / Decimal(months) : 0
    }

    // MARK: - Goals

    public struct GoalPlan {
        public let goal: Goal
        public let monthsRemaining: Int
        public let requiredMonthlySavings: Decimal
        public let currentAverageSavings: Decimal
        public let monthlyGap: Decimal
        public let suggestedCuts: [CategoryCutSuggestion]
    }

    public struct CategoryCutSuggestion: Identifiable {
        public let category: Persistence.Category
        public let currentMonthlySpend: Decimal
        public let suggestedReduction: Decimal
        public var id: Int64? { category.id }
    }

    /// Months remaining rounds PARTIAL months up: a goal due in 11 months
    /// and 29 days has 12 contribution months, not 11 — counting only
    /// complete months would overstate the required monthly saving.
    static func monthsRemaining(until target: Date, from now: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.month, .day], from: now, to: target)
        let whole = parts.month ?? 0
        let extraDays = parts.day ?? 0
        return max(1, whole + (extraDays > 0 ? 1 : 0))
    }

    public func evaluateGoal(_ goal: Goal) throws -> GoalPlan {
        let monthsRemaining = Self.monthsRemaining(until: goal.targetDate)
        let required = goal.targetAmount / Decimal(monthsRemaining)
        let currentAverage = try averageMonthlySavings()
        let gap = required - currentAverage
        let suggestions = gap > 0 ? try suggestCuts(toClose: gap, scope: goal.cutScope) : []
        return GoalPlan(
            goal: goal,
            monthsRemaining: monthsRemaining,
            requiredMonthlySavings: required,
            currentAverageSavings: currentAverage,
            monthlyGap: gap,
            suggestedCuts: suggestions
        )
    }

    /// Proportional-by-spend cuts across eligible categories. Deliberately
    /// simple: a suggestion you can sanity-check at a glance, not a black-
    /// box optimizer (blueprint watch-out says resist "clever" upgrades).
    /// Suggestions sum to exactly the gap.
    ///
    /// Spending is computed per category over ALL of this month's
    /// transactions — not via the allocation summary, which only covers
    /// categories that have budget rows; money spent outside the budget is
    /// exactly the money a goal most wants cut. O(n + k), grouped in SQL.
    private func suggestCuts(toClose gap: Decimal, scope: GoalCutScope) throws -> [CategoryCutSuggestion] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: Date()) else { return [] }

        let spendByCategory: [(category: Persistence.Category, spent: Decimal)] =
            try databaseManager.dbQueue().read { db in
                let converter = try CurrencyConverter(db: db)
                let categories = try Persistence.Category.fetchAll(db)
                let categoryById = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                    category.id.map { ($0, category) }
                })
                let rows = try Row.fetchAll(db, sql: """
                    SELECT categoryId, currency, direction, GROUP_CONCAT(amount, '|') AS amounts
                    FROM "transaction"
                    WHERE date >= ? AND date < ?
                    GROUP BY categoryId, currency, direction
                    """, arguments: [interval.start, interval.end])
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
                return totals.compactMap { categoryId, spent in
                    categoryById[categoryId].map { ($0, spent) }
                }
            }

        let eligible = spendByCategory.filter { entry in
            switch scope {
            case .anyCategory: return entry.spent > 0
            case .flexibleOnly: return entry.category.bucket == .flexible && entry.spent > 0
            }
        }
        let eligibleTotal = eligible.reduce(Decimal(0)) { $0 + $1.spent }
        guard eligibleTotal > 0 else { return [] }

        var suggestions = eligible
            .map { entry in
                let share = entry.spent / eligibleTotal
                return CategoryCutSuggestion(
                    category: entry.category,
                    currentMonthlySpend: entry.spent,
                    suggestedReduction: gap * share
                )
            }
            .sorted { $0.suggestedReduction > $1.suggestedReduction }

        // Proportional shares can be repeating fractions (2000/3000 =
        // 0.666…), so the parts may sum a hair under the gap. The largest
        // spender absorbs the remainder, making the total EXACTLY the gap
        // by construction — the checkpoint's requirement, and the honest
        // presentation ("these cuts close the gap", not "almost").
        let allButFirst = suggestions.dropFirst().reduce(Decimal(0)) { $0 + $1.suggestedReduction }
        if let first = suggestions.first {
            suggestions[0] = CategoryCutSuggestion(
                category: first.category,
                currentMonthlySpend: first.currentMonthlySpend,
                suggestedReduction: gap - allButFirst
            )
        }
        return suggestions
    }

    // MARK: - Wishlist

    public struct WishlistTimeToSave {
        public let item: WishlistItem
        /// Months at the current average savings rate; nil when not saving.
        public let monthsBySavingsRate: Int?
        /// The price expressed as working days of income — the dual
        /// "life-energy" framing (Robin & Dominguez).
        public let daysOfLifeEnergy: Decimal
    }

    public func timeToSave(for item: WishlistItem) throws -> WishlistTimeToSave {
        let avgSavings = try averageMonthlySavings()
        let months: Int? = avgSavings > 0
            ? Int(truncating: NSDecimalNumber(decimal: (item.price / avgSavings)).rounding(accordingToBehavior:
                NSDecimalNumberHandler(roundingMode: .up, scale: 0, raiseOnExactness: false,
                                       raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)))
            : nil
        guard let income = try allocationService.currentIncome(), income.amount > 0 else {
            return WishlistTimeToSave(item: item, monthsBySavingsRate: months, daysOfLifeEnergy: 0)
        }
        let dailyIncome = income.amount / workingDaysPerMonth
        return WishlistTimeToSave(
            item: item,
            monthsBySavingsRate: months,
            daysOfLifeEnergy: dailyIncome > 0 ? item.price / dailyIncome : 0
        )
    }
}

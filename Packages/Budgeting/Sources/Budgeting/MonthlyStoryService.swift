import Foundation
import GRDB
import Persistence

// MARK: - MonthlyStoryService
// The month-end story: a few plain sentences explaining WHERE the month
// went, computed deterministically from data the app already has — no
// model, no guessing, every number checkable against the Transactions
// tab. (If the LLM lands later it can restyle this text; the arithmetic
// stays here.)
public struct MonthlyStoryService {
    private let databaseManager: DatabaseManager
    /// Norm = trailing window BEFORE the story month.
    private let normWindowMonths = 3

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// Net EGP spend per category for one month. O(month's transactions).
    private func netSpend(in month: Date, db: Database, converter: CurrencyConverter) throws -> [Int64: Decimal] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [:] }
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
            let sum = amounts.split(separator: "|")
                .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                .reduce(Decimal(0), +)
            let egp = converter.toEGP(sum, from: currency)
            totals[categoryId, default: 0] += (direction == "income" ? -egp : egp)
        }
        return totals
    }

    /// Whole-percent, sign included, for readable sentences.
    private func percentChange(_ current: Decimal, vs baseline: Decimal) -> Int? {
        guard baseline > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - baseline) / baseline * 100).intValue
    }

    /// "3,000" / "2,500.5" — grouped, at most 2 decimals. Raw Decimal
    /// interpolation prints unbounded digits, which made story amounts
    /// unreadable.
    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private func money(_ value: Decimal) -> String {
        Self.moneyFormatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// The story lines for a month. O(window × month-size) — four bounded
    /// month scans. Empty history degrades to fewer lines, never wrong ones.
    public func story(for month: Date = Date()) throws -> [String] {
        try databaseManager.dbQueue().read { db in
            let converter = try CurrencyConverter(db: db)
            let calendar = Calendar.current
            let categories = Dictionary(uniqueKeysWithValues: try Persistence.Category.fetchAll(db)
                .compactMap { category in category.id.map { ($0, category.name) } })

            let current = try netSpend(in: month, db: db, converter: converter)
            let currentTotal = current.values.reduce(Decimal(0), +)
            guard currentTotal != 0 else { return [] }

            // The norm: average of the trailing months that HAVE data.
            var normTotals: [Int64: Decimal] = [:]
            var activeNormMonths = 0
            for offset in 1...normWindowMonths {
                guard let past = calendar.date(byAdding: .month, value: -offset, to: month) else { continue }
                let spend = try netSpend(in: past, db: db, converter: converter)
                guard !spend.isEmpty else { continue }
                activeNormMonths += 1
                for (categoryId, value) in spend { normTotals[categoryId, default: 0] += value }
            }
            let normAverage = activeNormMonths > 0
                ? normTotals.mapValues { $0 / Decimal(activeNormMonths) }
                : [:]
            let normTotal = normAverage.values.reduce(Decimal(0), +)

            var lines: [String] = []

            // 1. The headline. A negative net month (money in exceeded
            // spending) reads as a win, not "you spent -500".
            if currentTotal < 0 {
                lines.append("Money in exceeded spending by \(money(-currentTotal)) EGP this month — you came out ahead.")
            } else if let change = percentChange(currentTotal, vs: normTotal) {
                let direction = change >= 0 ? "above" : "below"
                lines.append("You spent \(money(currentTotal)) EGP net this month — \(abs(change))% \(direction) your \(activeNormMonths)-month average of \(money(normTotal)).")
            } else {
                lines.append("You spent \(money(currentTotal)) EGP net this month — first full month, so no average to compare yet.")
            }

            // 2. The driver: biggest absolute increase vs the norm.
            if !normAverage.isEmpty {
                let driver = current
                    .map { (id: $0.key, delta: $0.value - (normAverage[$0.key] ?? 0), now: $0.value) }
                    .filter { $0.delta > 0 }
                    .max { $0.delta < $1.delta }
                if let driver, let name = categories[driver.id],
                   let interval = calendar.dateInterval(of: .month, for: month) {
                    let usual = normAverage[driver.id] ?? 0
                    // Bounded to the story month on BOTH ends — the old
                    // start-only filter counted every transaction from the
                    // story month to today when reading a past month.
                    let count = try Persistence.Transaction
                        .filter(GRDB.Column("categoryId") == driver.id)
                        .filter(GRDB.Column("date") >= interval.start && GRDB.Column("date") < interval.end)
                        .fetchCount(db)
                    lines.append("Biggest driver: \(name) at \(money(driver.now)) EGP vs your usual \(money(usual)), across \(count) transaction(s).")
                }
            }

            // 3. Biggest single expense.
            if let interval = calendar.dateInterval(of: .month, for: month) {
                let expenses = try Persistence.Transaction
                    .filter(GRDB.Column("direction") == "expense")
                    .filter(GRDB.Column("date") >= interval.start && GRDB.Column("date") < interval.end)
                    .fetchAll(db)
                if let biggest = expenses.max(by: {
                    converter.toEGP($0.amount, from: $0.currency) < converter.toEGP($1.amount, from: $1.currency)
                }) {
                    let category = categories[biggest.categoryId] ?? "?"
                    lines.append("Biggest single expense: \(money(biggest.amount)) \(biggest.currency) at \(biggest.merchant ?? "—") (\(category)).")
                }

                // 4. Subscriptions (transactions linked to confirmed series).
                let subsTotal = expenses
                    .filter { $0.recurringSeriesId != nil }
                    .reduce(Decimal(0)) { $0 + converter.toEGP($1.amount, from: $1.currency) }
                if subsTotal > 0 {
                    lines.append("Subscriptions and recurring bills totalled \(money(subsTotal)) EGP.")
                }
            }

            // 5. Savings vs income.
            if let income = try Income.fetchOne(db, key: 1), income.amount > 0 {
                let saved = income.amount - currentTotal
                let rate = NSDecimalNumber(decimal: saved / income.amount * 100).intValue
                lines.append(saved >= 0
                    ? "You kept \(money(saved)) EGP of your \(money(income.amount)) income (\(rate)%)."
                    : "You overspent your income by \(money(-saved)) EGP this month.")
            }

            return lines
        }
    }
}

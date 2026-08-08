import Foundation
import SwiftUI
import GRDB
import Budgeting
import SavingsAndGoals
import Forecasting
import Persistence
import UI

// MARK: - InsightsViewModel — "everything Mizan knows"
// Backs the redesigned Insights tab (Claude Design "Data Overview"): one
// scroll of net worth, savings rate, trends, budget split, category
// performance, debts, goals, sinking funds, and the data footprint —
// switchable across Month / Quarter / Year. All money stays Decimal;
// Doubles exist only as chart geometry. Income/spending figures use the
// same transfer-excluding query as Home (HomeViewModel.sumFlow), so the
// two screens can never disagree.
@MainActor
final class InsightsViewModel: ObservableObject {

    enum Period: String, CaseIterable, Identifiable {
        case month = "Month", quarter = "Quarter", year = "Year"
        var id: String { rawValue }
    }

    // MARK: Display structures

    struct FlowBar: Identifiable {
        let id = UUID()
        let label: String
        let series: String // "Income" / "Spent"
        let value: Double  // chart geometry
    }
    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let value: Double  // chart geometry
    }
    struct AllocSlice: Identifiable {
        let id = UUID()
        let name: String
        let pct: Int
        let amountText: String
        let color: Color
        let fraction: Double
    }
    struct CategoryRow: Identifiable {
        let id = UUID()
        let name: String
        let amountsText: String   // "6,240 / 7,200"
        let overBudget: Bool
        let barFraction: Double   // clamped 0...1
        let barTint: Color        // status: mint / cream / red
        let chipColor: Color
        let share: Double         // of total spending, for the stacked bar
    }
    struct DebtRow: Identifiable {
        let id = UUID()
        let name: String
        let paidFraction: Double
        let pctLabel: String
        let remainingText: String
        let aprText: String
        let payoffText: String
    }
    struct GoalRing: Identifiable {
        let id = UUID()
        let name: String
        let fraction: Double
        let pctLabel: String
        let caption: String
    }
    struct FundBar: Identifiable {
        let id = UUID()
        let name: String
        let fraction: Double
        let progressText: String
    }
    struct SourceSlice: Identifiable {
        let id = UUID()
        let name: String
        let pct: Int
        let fraction: Double
        let color: Color
    }
    struct FootprintStat: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }
    struct DailyPoint: Identifiable {
        let id = UUID()
        let day: Int
        let total: Decimal
        var amount: Double { NSDecimalNumber(decimal: total).doubleValue }
    }
    struct WeekdayPoint: Identifiable {
        let id = UUID()
        let index: Int
        let label: String
        let total: Decimal
        var amount: Double { NSDecimalNumber(decimal: total).doubleValue }
    }
    struct CumulativePoint: Identifiable {
        let id = UUID()
        let day: Int
        let spentTotal: Decimal   // exact — the tap-to-read readout uses this
        let spent: Double         // chart geometry
        let pace: Double?         // chart geometry
    }

    // MARK: Published state

    @Published var period: Period = .month
    @Published var periodLabel = ""
    @Published var periodShort = ""

    /// Any transactions in the ledger at all. Defaults true so a locked/
    /// mid-load screen never flashes the empty state; `load()` flips it to
    /// false on a genuinely empty database (fresh install) so Insights shows
    /// a friendly prompt instead of a wall of zero-value cards.
    @Published var hasData = true

    // Hero
    @Published var netWorthText = "—"
    @Published var deltaText: String?
    @Published var deltaPositive = true
    @Published var spendableText = "—"
    @Published var debtText = "—"
    @Published var savingsRate = 0          // % of income kept this period
    @Published var gaugeFraction = 0.0

    // KPI strip
    @Published var incomeText = "—"
    @Published var spentText = "—"
    @Published var savedText = "—"

    // Charts
    @Published var nwTrend: [TrendPoint] = []
    @Published var flowBars: [FlowBar] = []
    @Published var allocSlices: [AllocSlice] = []
    @Published var allocTotalText = ""
    @Published var categoryRows: [CategoryRow] = []
    @Published var debts: [DebtRow] = []
    @Published var debtRemainingText = ""
    @Published var goalRings: [GoalRing] = []
    @Published var fundBars: [FundBar] = []
    @Published var footprint: [FootprintStat] = []
    @Published var sources: [SourceSlice] = []

    // Forecast (Monte Carlo net worth from historical savings)
    @Published var forecastMonths = 24
    @Published var forecastP10: Decimal?
    @Published var forecastP50: Decimal?
    @Published var forecastP90: Decimal?
    @Published var forecastAssumption = ""
    @Published var forecastBands: [ForecastBand] = []
    struct ForecastBand: Identifiable {
        let id = UUID()
        let month: Int
        let p10: Double
        let p50: Double
        let p90: Double
    }

    // Month-only cards
    @Published var storyLines: [String] = []
    @Published var cumulative: [CumulativePoint] = []
    @Published var hasBudgetPace = false
    @Published var paceDeltaText = ""
    @Published var aheadOfPace = true
    @Published var weekdayTotals: [WeekdayPoint] = []

    private let allocation = SalaryAllocationService()
    private let goalsService = SavingsAndGoalsService()
    private let storyService = MonthlyStoryService()
    private static let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "You spend N% more per day on weekdays/weekends" — normalized per-day.
    var weekdayInsight: String {
        let weekdays = weekdayTotals.filter { (1...5).contains($0.index) }.reduce(Decimal(0)) { $0 + $1.total }
        let weekends = weekdayTotals.filter { $0.index == 0 || $0.index == 6 }.reduce(Decimal(0)) { $0 + $1.total }
        let weekdayPerDay = weekdays / 5
        let weekendPerDay = weekends / 2
        guard weekdayPerDay > 0, weekendPerDay > 0 else {
            return "Not enough spread yet to compare weekdays and weekends."
        }
        if weekdayPerDay >= weekendPerDay {
            let pct = NSDecimalNumber(decimal: (weekdayPerDay - weekendPerDay) / weekendPerDay * 100).intValue
            return "You spend \(pct)% more per day on weekdays."
        }
        let pct = NSDecimalNumber(decimal: (weekendPerDay - weekdayPerDay) / weekdayPerDay * 100).intValue
        return "You spend \(pct)% more per day on weekends."
    }

    func setPeriod(_ newPeriod: Period) {
        period = newPeriod
        load()
    }

    // MARK: Period math

    /// The current period's date interval and the number of months in it —
    /// allocations are monthly, so quarter/year budgets scale by months.
    private func periodInterval() -> (interval: DateInterval, months: Int) {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .month:
            // Follows the budget cycle (calendar month by default, or the
            // user's pay-day window) so the Month view matches the Home budget.
            return (BudgetCycle.currentWindow(now: now, calendar: calendar), 1)
        case .quarter:
            let month = calendar.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = quarterStartMonth
            comps.day = 1
            let start = calendar.date(from: comps) ?? now
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? now
            return (DateInterval(start: start, end: end), 3)
        case .year:
            return (calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 0), 12)
        }
    }

    private func periodTitle() -> (label: String, short: String) {
        let now = Date()
        switch period {
        case .month:
            guard BudgetCycle.startDay != 1 else {
                return (now.formatted(.dateTime.month(.abbreviated).year()), "this mo.")
            }
            let window = BudgetCycle.currentWindow(now: now)
            let start = window.start.formatted(.dateTime.day().month(.abbreviated))
            let end = window.end.formatted(.dateTime.day().month(.abbreviated))
            return ("\(start) – \(end)", "this cycle")
        case .quarter:
            let quarter = (Calendar.current.component(.month, from: now) - 1) / 3 + 1
            return ("Q\(quarter) \(Calendar.current.component(.year, from: now))", "this qtr")
        case .year:
            return ("\(Calendar.current.component(.year, from: now)) YTD", "this yr")
        }
    }

    // MARK: Load

    func load() {
        let (interval, monthsInPeriod) = periodInterval()
        let title = periodTitle()
        periodLabel = title.label
        periodShort = title.short

        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try dbQueue.read { db in
                hasData = try Transaction.fetchCount(db) > 0
                let converter = try CurrencyConverter(db: db)
                try loadHero(db: db, converter: converter, interval: interval)
                try loadFlowBars(db: db, converter: converter)
                try loadFootprint(db: db)
                try loadNetWorthTrend(db: db)
            }
            try loadAllocationSplit()
            try loadCategoryRows(interval: interval, monthsInPeriod: monthsInPeriod)
            try loadDebts()
            try loadGoalsAndFunds()
            loadForecast()
            if period == .month {
                // The month story is a calendar-month narrative; hide it under
                // a custom pay cycle so its figures can't disagree with the
                // cycle-based KPIs above it.
                storyLines = BudgetCycle.startDay == 1 ? ((try? storyService.story(for: Date())) ?? []) : []
                try loadPaceAndWeekdays(interval: interval)
            } else {
                storyLines = []
                cumulative = []
                weekdayTotals = []
            }
        } catch {
            // Locked / unreadable — leave whatever was on screen.
        }
    }

    // MARK: Hero (net worth, spendable/debt, savings gauge, KPIs)

    private func loadHero(db: Database, converter: CurrencyConverter, interval: DateInterval) throws {
        // Live net worth + the spendable/debt split by account type.
        let accounts = try Account.fetchAll(db)
        var total: Decimal = 0
        var spendable: Decimal = 0
        var debtOwed: Decimal = 0
        for account in accounts {
            let egp = converter.toEGP(account.balance, from: account.currency)
            total += egp
            if AccountType(rawValue: account.type) == .creditCard {
                // A negative card balance is money owed.
                if egp < 0 { debtOwed += -egp } else { spendable += egp }
            } else {
                spendable += egp
            }
        }
        netWorthText = Money.egp(total)
        spendableText = Money.egp(spendable)
        debtText = Money.egp(debtOwed)

        // Delta vs the earliest frozen snapshot inside the period.
        let baseline = try NetWorthSnapshot
            .filter(GRDB.Column("date") >= interval.start)
            .order(GRDB.Column("date"))
            .fetchOne(db)
        if let baseline, baseline.netWorth != 0 {
            let delta = total - baseline.netWorth
            let pct = NSDecimalNumber(decimal: delta / abs(baseline.netWorth) * 100).doubleValue
            deltaPositive = delta >= 0
            deltaText = "\(delta >= 0 ? "+" : "−")\(Money.amount(abs(delta))) · \(String(format: "%.1f", abs(pct)))%"
        } else {
            deltaText = nil
        }

        // Period income / spent / saved (transfers excluded, same query as
        // Home) + the savings-rate gauge.
        let (income, spent) = try HomeViewModel.sumFlow(
            start: interval.start, end: min(interval.end, Date().addingTimeInterval(1)),
            db: db, converter: converter)
        let saved = max(0, income - spent)
        incomeText = Money.amount(income)
        spentText = Money.amount(spent)
        savedText = Money.amount(saved)
        if income > 0 {
            // Derive both from one Double fraction. NSDecimalNumber.intValue
            // mis-evaluates a high-precision Decimal like 79.5355… to 0, which
            // used to make the gauge read 0% while its arc filled correctly.
            let fraction = min(1, NSDecimalNumber(decimal: saved / income).doubleValue)
            gaugeFraction = fraction
            savingsRate = Int((fraction * 100).rounded())
        } else {
            savingsRate = 0
            gaugeFraction = 0
        }
    }

    // MARK: Income vs spending bars

    private func loadFlowBars(db: Database, converter: CurrencyConverter) throws {
        let calendar = Calendar.current
        let now = Date()
        var ranges: [(label: String, start: Date, end: Date)] = []
        switch period {
        case .month:
            for offset in stride(from: 5, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .month, value: -offset, to: now),
                      let interval = calendar.dateInterval(of: .month, for: day) else { continue }
                ranges.append((day.formatted(.dateTime.month(.abbreviated)), interval.start, interval.end))
            }
        case .quarter:
            for offset in stride(from: 3, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .month, value: -offset * 3, to: now) else { continue }
                let month = calendar.component(.month, from: day)
                let quarter = (month - 1) / 3 + 1
                var comps = calendar.dateComponents([.year], from: day)
                comps.month = ((month - 1) / 3) * 3 + 1
                comps.day = 1
                guard let start = calendar.date(from: comps),
                      let end = calendar.date(byAdding: .month, value: 3, to: start) else { continue }
                ranges.append(("Q\(quarter)", start, end))
            }
        case .year:
            for offset in stride(from: 2, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .year, value: -offset, to: now),
                      let interval = calendar.dateInterval(of: .year, for: day) else { continue }
                ranges.append((day.formatted(.dateTime.year()), interval.start, interval.end))
            }
        }
        flowBars = try ranges.flatMap { range -> [FlowBar] in
            let (income, expense) = try HomeViewModel.sumFlow(
                start: range.start, end: range.end, db: db, converter: converter)
            return [
                FlowBar(label: range.label, series: "Income",
                        value: NSDecimalNumber(decimal: income).doubleValue),
                FlowBar(label: range.label, series: "Spent",
                        value: NSDecimalNumber(decimal: expense).doubleValue)
            ]
        }
    }

    // MARK: Net worth trend (frozen daily snapshots, last per month)

    private func loadNetWorthTrend(db: Database) throws {
        let calendar = Calendar.current
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -5, to: Date()),
              let windowStart = calendar.dateInterval(of: .month, for: sixMonthsAgo)?.start else { return }
        let snapshots = try NetWorthSnapshot
            .filter(GRDB.Column("date") >= windowStart)
            .order(GRDB.Column("date"))
            .fetchAll(db)
        // Last snapshot of each month = that month's closing net worth.
        var byMonth: [Date: NetWorthSnapshot] = [:]
        for snapshot in snapshots {
            guard let monthStart = calendar.dateInterval(of: .month, for: snapshot.date)?.start else { continue }
            byMonth[monthStart] = snapshot // ordered ascending → last write wins
        }
        nwTrend = byMonth.keys.sorted().map { monthStart in
            TrendPoint(
                date: monthStart,
                label: monthStart.formatted(.dateTime.month(.abbreviated)),
                value: NSDecimalNumber(decimal: byMonth[monthStart]!.netWorth).doubleValue
            )
        }
    }

    // MARK: Budget split (allocation percentages grouped by bucket)

    private func loadAllocationSplit() throws {
        guard let income = try allocation.currentIncome(), income.amount > 0 else {
            allocSlices = []
            return
        }
        let allocations = try allocation.currentAllocations()
        let dbQueue = try DatabaseManager.shared.dbQueue()
        let bucketById: [Int64: CategoryBucket] = try dbQueue.read { db in
            Dictionary(uniqueKeysWithValues: try Persistence.Category.fetchAll(db)
                .compactMap { category in category.id.map { ($0, category.bucket) } })
        }
        var byBucket: [CategoryBucket: Decimal] = [:]
        for entry in allocations {
            byBucket[bucketById[entry.categoryId] ?? .flexible, default: 0] += entry.percentage
        }
        let display: [(CategoryBucket, String, Color)] = [
            (.fixed, "Fixed", KitTheme.primary),
            (.nonMonthlyRecurring, "Non-monthly", Color(hexValue: 0x7FB0A0)),
            (.flexible, "Flexible", AppTheme.accentCream)
        ]
        allocTotalText = Money.amount(income.amount)
        allocSlices = display.compactMap { bucket, name, color in
            guard let share = byBucket[bucket], share > 0 else { return nil }
            return AllocSlice(
                name: name,
                pct: NSDecimalNumber(decimal: share * 100).intValue,
                amountText: Money.amount(income.amount * share),
                color: color,
                fraction: NSDecimalNumber(decimal: share).doubleValue
            )
        }
    }

    // MARK: Spending by category (spent vs allocated, status-tinted)

    private func loadCategoryRows(interval: DateInterval, monthsInPeriod: Int) throws {
        let calendar = Calendar.current
        // Sum each month's summary across the period; allocations are
        // monthly, so a quarter's budget for a category = 3 × its monthly.
        var spentByName: [String: Decimal] = [:]
        var allocatedByName: [String: Decimal] = [:]
        if monthsInPeriod <= 1 {
            // One period (calendar month or pay cycle): use the exact window so
            // the category rows match the Spent/KPI figures above them.
            for summary in (try? allocation.monthlySummary(in: interval)) ?? [] {
                spentByName[summary.category.name, default: 0] += max(0, summary.spent)
                allocatedByName[summary.category.name, default: 0] += summary.allocated
            }
        } else {
            for offset in 0..<monthsInPeriod {
                guard let month = calendar.date(byAdding: .month, value: offset, to: interval.start),
                      month < Date() || offset == 0 else { continue }
                for summary in (try? allocation.monthlySummary(for: month)) ?? [] {
                    spentByName[summary.category.name, default: 0] += max(0, summary.spent)
                    allocatedByName[summary.category.name, default: 0] += summary.allocated
                }
            }
        }
        let totalSpent = spentByName.values.reduce(Decimal(0), +)
        categoryRows = spentByName
            .filter { $0.value > 0 || (allocatedByName[$0.key] ?? 0) > 0 }
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { name, spent in
                let allocated = allocatedByName[name] ?? 0
                let fraction = allocated > 0 ? NSDecimalNumber(decimal: spent / allocated).doubleValue : 0
                let tint: Color = fraction >= 1 ? Color(hexValue: 0xFF5D5D)
                    : fraction >= 0.8 ? AppTheme.accentCream
                    : KitTheme.primary
                return CategoryRow(
                    name: name,
                    amountsText: "\(Money.amount(spent)) / \(Money.amount(allocated))",
                    overBudget: fraction >= 1,
                    barFraction: min(1, max(0, fraction)),
                    barTint: allocated > 0 ? tint : KitTheme.primary,
                    chipColor: KitTheme.categoryColor(name),
                    share: totalSpent > 0 ? NSDecimalNumber(decimal: spent / totalSpent).doubleValue : 0
                )
            }
    }

    // MARK: Debts

    private func loadDebts() throws {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        let rows = try dbQueue.read { db in try Debt.fetchAll(db) }
        let calendar = Calendar.current
        var totalRemaining: Decimal = 0
        debts = rows.map { debt in
            let schedule = AmortizationCalculator().fullSchedule(
                principal: debt.principal, annualRate: debt.interestRate, termMonths: debt.termMonths)
            let elapsed = max(0, min(debt.termMonths,
                calendar.dateComponents([.month], from: debt.startDate, to: Date()).month ?? 0))
            let remaining = elapsed == 0 ? debt.principal
                : (schedule.indices.contains(elapsed - 1) ? schedule[elapsed - 1].remainingBalance : 0)
            totalRemaining += remaining
            let paid = debt.principal > 0
                ? 1 - NSDecimalNumber(decimal: remaining / debt.principal).doubleValue
                : 0
            let payoff = calendar.date(byAdding: .month, value: debt.termMonths, to: debt.startDate)
            return DebtRow(
                name: debt.name,
                paidFraction: min(1, max(0, paid)),
                pctLabel: "\(Int((min(1, max(0, paid)) * 100).rounded()))%",
                remainingText: Money.amount(remaining),
                aprText: "\(debt.interestRate)% APR",
                payoffText: payoff?.formatted(.dateTime.month(.abbreviated).year()) ?? "—"
            )
        }
        debtRemainingText = Money.amount(totalRemaining)
    }

    // MARK: Goals & sinking funds

    private func loadGoalsAndFunds() throws {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        let (goals, funds) = try dbQueue.read { db in
            (try Goal.fetchAll(db), try SinkingFund.fetchAll(db))
        }
        // Honest ring: Mizan doesn't track per-goal contributions, so the
        // ring shows how much of the REQUIRED monthly saving your actual
        // savings rate covers — 100% means "on pace", not "fully funded".
        goalRings = try goals.prefix(3).map { goal in
            let plan = try goalsService.evaluateGoal(goal)
            let fraction = plan.requiredMonthlySavings > 0
                ? min(1, max(0, NSDecimalNumber(decimal: plan.currentAverageSavings / plan.requiredMonthlySavings).doubleValue))
                : 1
            return GoalRing(
                name: goal.name,
                fraction: fraction,
                pctLabel: "\(Int((fraction * 100).rounded()))%",
                caption: "of needed pace · \(plan.monthsRemaining) mo left"
            )
        }
        fundBars = funds.map { fund in
            let fraction = fund.targetAmount > 0
                ? min(1, max(0, NSDecimalNumber(decimal: fund.currentAmount / fund.targetAmount).doubleValue))
                : 0
            return FundBar(
                name: fund.name,
                fraction: fraction,
                progressText: "\(Money.amount(fund.currentAmount)) / \(Money.amount(fund.targetAmount))"
            )
        }
    }

    // MARK: Forecast (Monte Carlo net worth from real savings history)

    func setForecastHorizon(_ months: Int) {
        forecastMonths = months
        loadForecast()
    }

    /// Projects net worth forward as percentile bands, using the SAME
    /// active-months-only savings history as the Plan forecast (a month
    /// with zero transactions is missing data, not a saved salary). Needs
    /// ≥2 active months; otherwise the card shows its empty state.
    private func loadForecast() {
        forecastP10 = nil; forecastP50 = nil; forecastP90 = nil
        forecastBands = []; forecastAssumption = ""
        let calendar = Calendar.current
        guard let dbQueue = try? DatabaseManager.shared.dbQueue() else { return }

        var history: [Decimal] = []
        for offset in 0..<6 {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: Date()),
                  let interval = calendar.dateInterval(of: .month, for: month) else { continue }
            let active = ((try? dbQueue.read { db in
                try Persistence.Transaction
                    .filter(GRDB.Column("date") >= interval.start && GRDB.Column("date") < interval.end)
                    .fetchCount(db)
            }) ?? 0) > 0
            guard active, let saved = try? goalsService.savings(for: month) else { continue }
            history.append(saved)
        }
        guard history.count >= 2 else { return }

        let converter = try? dbQueue.read { db in try CurrencyConverter(db: db) }
        let netWorth = (try? dbQueue.read { db in
            try Account.fetchAll(db).reduce(Decimal(0)) {
                $0 + (converter?.toEGP($1.balance, from: $1.currency) ?? $1.balance)
            }
        }) ?? 0

        let service = ForecastingService()
        let nwDouble = NSDecimalNumber(decimal: netWorth).doubleValue
        var bands: [ForecastBand] = [ForecastBand(month: 0, p10: nwDouble, p50: nwDouble, p90: nwDouble)]
        let steps = 6
        for step in 1...steps {
            let months = max(1, forecastMonths * step / steps)
            let result = service.projectNetWorth(
                monthsAhead: months, currentNetWorth: netWorth, historicalMonthlySavings: history)
            bands.append(ForecastBand(
                month: months,
                p10: NSDecimalNumber(decimal: result.p10).doubleValue,
                p50: NSDecimalNumber(decimal: result.p50).doubleValue,
                p90: NSDecimalNumber(decimal: result.p90).doubleValue))
            if step == steps {
                forecastP10 = result.p10; forecastP50 = result.p50; forecastP90 = result.p90
            }
        }
        forecastBands = bands
        let mean = history.reduce(Decimal(0), +) / Decimal(history.count)
        forecastAssumption = "Based on \(history.count) active month(s) averaging \(Money.amount(mean)) EGP saved/month, replayed 1,000× with your real variance."
    }

    // MARK: Data footprint

    private func loadFootprint(db: Database) throws {
        let transactionCount = try Persistence.Transaction.fetchCount(db)
        let receiptCount = try Persistence.Transaction
            .filter(GRDB.Column("source") == TransactionSource.receiptOCR.rawValue)
            .fetchCount(db)
        let accountCount = try Account.fetchCount(db)
        let categoryCount = try Persistence.Category.fetchCount(db)
        footprint = [
            FootprintStat(value: "\(transactionCount)", label: "Transactions"),
            FootprintStat(value: "\(receiptCount)", label: "Receipts scanned"),
            FootprintStat(value: "\(accountCount)", label: "Accounts"),
            FootprintStat(value: "\(categoryCount)", label: "Categories")
        ]

        guard transactionCount > 0 else {
            sources = []
            return
        }
        let display: [(TransactionSource, String, Color)] = [
            (.manual, "Manual", KitTheme.primary),
            (.walletIntent, "Apple Pay", AppTheme.accentCream),
            (.receiptOCR, "Receipts", Color(hexValue: 0x54C8D6)),
            (.voice, "Voice", Color(hexValue: 0xB48AD6)),
            (.sms, "SMS", Color(hexValue: 0xE8894F))
        ]
        sources = try display.compactMap { source, name, color in
            let count = try Persistence.Transaction
                .filter(GRDB.Column("source") == source.rawValue)
                .fetchCount(db)
            guard count > 0 else { return nil }
            let fraction = Double(count) / Double(transactionCount)
            return SourceSlice(name: name, pct: Int((fraction * 100).rounded()),
                               fraction: fraction, color: color)
        }
    }

    // MARK: Month-only: spending pace + weekday spread

    private func loadPaceAndWeekdays(interval: DateInterval) throws {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        let (txns, converter) = try dbQueue.read { db -> ([Persistence.Transaction], CurrencyConverter) in
            let converter = try CurrencyConverter(db: db)
            let txns = try Persistence.Transaction
                .filter(GRDB.Column("date") >= interval.start && GRDB.Column("date") < interval.end)
                .fetchAll(db)
            return (txns, converter)
        }
        let calendar = Calendar.current
        // Index spend by day-OFFSET from the window start (not day-of-month),
        // so a pay cycle spanning two calendar months still accumulates in the
        // right order. byWeekday is absolute, so it's unaffected.
        var byOffset: [Int: Decimal] = [:]
        var byWeekday: [Int: Decimal] = [:]
        for txn in txns where txn.direction == .expense {
            let egp = converter.toEGP(txn.amount, from: txn.currency)
            let offset = calendar.dateComponents([.day], from: interval.start, to: txn.date).day ?? 0
            byOffset[offset, default: 0] += egp
            byWeekday[calendar.component(.weekday, from: txn.date) - 1, default: 0] += egp
        }
        weekdayTotals = (0...6).map { index in
            WeekdayPoint(index: index, label: Self.weekdayLabels[index], total: byWeekday[index] ?? 0)
        }

        // Cumulative spend vs an even burn of the budget over the CURRENT
        // window (calendar month or pay cycle). Money in Decimal; chart points
        // project to Double at the very end.
        let budget = UserDefaults.standard.string(forKey: HomeViewModel.budgetKey)
            .flatMap { AmountFormat.decimal($0) } ?? 0
        let totalDays = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30)
        let elapsed = (calendar.dateComponents([.day], from: interval.start, to: Date()).day ?? 0) + 1
        let daysToShow = max(1, min(totalDays, elapsed))
        var running: Decimal = 0
        var lastPace: Decimal?
        cumulative = (0..<daysToShow).map { offset in
            running += byOffset[offset] ?? 0
            let dayNumber = offset + 1
            let pace = budget > 0 ? budget * Decimal(dayNumber) / Decimal(totalDays) : nil
            lastPace = pace
            return CumulativePoint(
                day: dayNumber,
                spentTotal: running,
                spent: NSDecimalNumber(decimal: running).doubleValue,
                pace: pace.map { NSDecimalNumber(decimal: $0).doubleValue }
            )
        }
        hasBudgetPace = budget > 0
        if budget > 0, let pace = lastPace {
            let delta = pace - running
            aheadOfPace = delta >= 0
            paceDeltaText = "\(HomeViewModel.money(abs(delta))) \(delta >= 0 ? "under" : "over") pace"
        } else {
            paceDeltaText = ""
        }
    }
}

import Foundation
import GRDB
import Budgeting
import Forecasting
import SavingsAndGoals
import Persistence

// MARK: - PlanViewModel
// Backs the Plan tab. Also reschedules bill notifications on load, so
// confirming a series immediately produces its reminders.
@MainActor
final class PlanViewModel: ObservableObject {
    @Published var candidates: [RecurringSeriesCandidate] = []
    @Published var bills: [BillsCalendarService.UpcomingBill] = []
    @Published var plans: [SavingsAndGoalsService.GoalPlan] = []
    @Published var wishlist: [SavingsAndGoalsService.WishlistTimeToSave] = []
    @Published var debts: [Debt] = []
    @Published var funds: [SinkingFund] = []
    @Published var newWishName = ""
    @Published var newWishPrice = ""
    @Published var contributePrompt: SinkingFund?
    @Published var contributeAmount = ""
    @Published var forecast: ForecastingService.ForecastResult?
    @Published var forecastAssumption: String?
    @Published var creepAlerts: [PriceCreepService.CreepAlert] = []

    private let detection = RecurringDetectionService()
    private let billsService = BillsCalendarService()
    private let goals = SavingsAndGoalsService()
    private let fundsService = SinkingFundService()

    func load() {
        do {
            candidates = try detection.detectRecurringSeries()
            bills = try billsService.upcomingBills()
            let dbQueue = try DatabaseManager.shared.dbQueue()
            let (goalRows, wishRows, debtRows) = try dbQueue.read { db in
                (
                    try Goal.order(GRDB.Column("targetDate")).fetchAll(db),
                    try WishlistItem.order(GRDB.Column("createdAt").desc).fetchAll(db),
                    try Debt.order(GRDB.Column("startDate").desc).fetchAll(db)
                )
            }
            plans = try goalRows.map { try goals.evaluateGoal($0) }
            wishlist = try wishRows.map { try goals.timeToSave(for: $0) }
            debts = debtRows
            funds = try fundsService.allFunds()
            creepAlerts = (try? PriceCreepService().creepAlerts()) ?? []
            updateForecast()
            Task { try? await billsService.rescheduleNotifications() }
        } catch {
            // Locked or unreadable — the tab shows empty states.
        }
    }

    /// Monte Carlo over ACTIVE months only — a month with zero recorded
    /// transactions is missing data, not "you saved your whole salary";
    /// including such months wildly inflated the projection (the user
    /// rightly called it inaccurate). Needs ≥2 active months; the card
    /// shows exactly what the simulation assumed.
    private func updateForecast() {
        forecast = nil
        forecastAssumption = nil
        let calendar = Calendar.current
        guard let dbQueue = try? DatabaseManager.shared.dbQueue() else { return }

        var history: [Decimal] = []
        for offset in 0..<6 {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: Date()),
                  let interval = calendar.dateInterval(of: .month, for: month) else { continue }
            let hasActivity = (try? dbQueue.read { db in
                try Persistence.Transaction
                    .filter(GRDB.Column("date") >= interval.start && GRDB.Column("date") < interval.end)
                    .fetchCount(db)
            }) ?? 0 > 0
            guard hasActivity, let saved = try? goals.savings(for: month) else { continue }
            history.append(saved)
        }
        guard history.count >= 2 else { return }

        let converter = try? dbQueue.read { db in try CurrencyConverter(db: db) }
        let netWorth: Decimal = (try? dbQueue.read { db in
            try Account.fetchAll(db).reduce(Decimal(0)) {
                $0 + (converter?.toEGP($1.balance, from: $1.currency) ?? $1.balance)
            }
        }) ?? 0

        forecast = ForecastingService().projectNetWorth(
            monthsAhead: 24,
            currentNetWorth: netWorth,
            historicalMonthlySavings: history
        )
        let mean = history.reduce(Decimal(0), +) / Decimal(history.count)
        forecastAssumption = "Assumes: today's net worth \(netWorth) EGP, plus monthly savings"
            + " (salary − net spending) from \(history.count) active month(s) averaging \(mean) EGP/month,"
            + " replayed 1,000 times with your real month-to-month variance."
    }

    func acceptNewPrice(_ alert: PriceCreepService.CreepAlert) {
        guard let seriesId = alert.series.id else { return }
        try? PriceCreepService().acceptNewPrice(seriesId: seriesId, newAmount: alert.latestAmount)
        load()
    }

    func confirm(_ candidate: RecurringSeriesCandidate) {
        try? detection.confirm(candidate)
        load()
    }

    func addGoal(name: String, amount: String, date: Date, scope: GoalCutScope) {
        guard let target = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { return }
        try? DatabaseManager.shared.dbQueue().write { db in
            var goal = Goal(name: name, targetAmount: target, targetDate: date, cutScope: scope, createdAt: Date())
            try goal.insert(db)
        }
        load()
    }

    func deleteGoal(_ goal: Goal) {
        _ = try? DatabaseManager.shared.dbQueue().write { db in try goal.delete(db) }
        load()
    }

    func addWishlistItem() {
        guard let price = Decimal(string: newWishPrice, locale: Locale(identifier: "en_US_POSIX")) else { return }
        let name = newWishName
        try? DatabaseManager.shared.dbQueue().write { db in
            var item = WishlistItem(name: name, price: price, createdAt: Date())
            try item.insert(db)
        }
        newWishName = ""
        newWishPrice = ""
        load()
    }

    func deleteWishlistItem(_ item: WishlistItem) {
        _ = try? DatabaseManager.shared.dbQueue().write { db in try item.delete(db) }
        load()
    }

    func addDebt(name: String, principal: String, rate: String, months: String) {
        guard let p = Decimal(string: principal, locale: Locale(identifier: "en_US_POSIX")),
              let r = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")),
              let m = Int(months) else { return }
        try? DatabaseManager.shared.dbQueue().write { db in
            var debt = Debt(name: name, principal: p, interestRate: r, termMonths: m, startDate: Date())
            try debt.insert(db)
        }
        load()
    }

    func deleteDebt(_ debt: Debt) {
        _ = try? DatabaseManager.shared.dbQueue().write { db in try debt.delete(db) }
        load()
    }

    func addFund(name: String, amount: String, date: Date) {
        guard let target = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { return }
        try? fundsService.create(name: name, targetAmount: target, targetDate: date, categoryId: nil)
        load()
    }

    func contribute() {
        if let fund = contributePrompt, let id = fund.id,
           let amount = Decimal(string: contributeAmount, locale: Locale(identifier: "en_US_POSIX")), amount > 0 {
            try? fundsService.contribute(amount, to: id)
        }
        contributePrompt = nil
        contributeAmount = ""
        load()
    }

    func fundProgress(_ fund: SinkingFund) -> Double {
        guard fund.targetAmount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: fund.currentAmount / fund.targetAmount).doubleValue)
    }

    func fundMonthly(_ fund: SinkingFund) -> Decimal {
        fundsService.requiredMonthlyContribution(fund)
    }
}

import Foundation
import WidgetKit
import GRDB
import Budgeting
import SavingsAndGoals
import Persistence
import UI

// MARK: - WidgetSnapshotPublisher
// One place that recomputes the derived WidgetSnapshot (safe-to-spend, net
// worth, budget, next bill) and asks WidgetKit to redraw. Called from every
// point where the numbers can change — a capture/edit (via
// .mizanDataDidChange), the Wallet dashboard load, draining the background
// queue, and app-background — so the widgets no longer wait for the Wallet
// tab to happen to be alive. Reads only derived aggregates; never writes.
enum WidgetSnapshotPublisher {
    /// Recompute + persist + reload. Silent on failure (locked DB): the
    /// widgets simply keep their previous snapshot.
    static func refresh() {
        guard let snapshot = computeSnapshot() else { return }
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func computeSnapshot() -> WidgetSnapshot? {
        let now = Date()
        let calendar = Calendar.current
        let budget = UserDefaults.standard.string(forKey: HomeViewModel.budgetKey)
            .flatMap { AmountFormat.decimal($0) } ?? 0
        let hasBudget = budget > 0
        // Over the current budget cycle (calendar month by default, or the
        // user's pay-day window). budgetConsumed (not totalSpent) so salary
        // income doesn't zero out the safe-to-spend figure.
        let cycle = BudgetCycle.currentWindow(now: now, calendar: calendar)
        let netConsumed = max(0, (try? SalaryAllocationService().budgetConsumed(in: cycle)) ?? 0)
        let remaining = hasBudget ? max(0, budget - netConsumed) : 0
        let usedFraction = hasBudget
            ? NSDecimalNumber(decimal: netConsumed / budget).doubleValue
            : 0
        let monthEnd = cycle.end

        // Net worth + trend (best-effort; nil pieces just omit those widgets'
        // data). Requires the DB to be readable (post-unlock).
        var netWorthText: String?
        var netWorthTrend: [Double]?
        if let dbQueue = try? DatabaseManager.shared.dbQueue() {
            netWorthText = try? dbQueue.read { db in
                let converter = try CurrencyConverter(db: db)
                let total = try Account.fetchAll(db).reduce(Decimal(0)) {
                    $0 + converter.toEGP($1.balance, from: $1.currency)
                }
                return Money.amount(total)
            }
            netWorthTrend = try? dbQueue.read { db -> [Double] in
                guard let windowStart = calendar.date(byAdding: .month, value: -5, to: now)
                    .flatMap({ calendar.dateInterval(of: .month, for: $0)?.start }) else { return [] }
                let snaps = try NetWorthSnapshot
                    .filter(GRDB.Column("date") >= windowStart)
                    .order(GRDB.Column("date"))
                    .fetchAll(db)
                var byMonth: [Date: Decimal] = [:]
                for snap in snaps {
                    if let m = calendar.dateInterval(of: .month, for: snap.date)?.start {
                        byMonth[m] = snap.netWorth
                    }
                }
                return byMonth.keys.sorted().map { NSDecimalNumber(decimal: byMonth[$0]!).doubleValue }
            }
        }

        // Next upcoming bill (soonest).
        let nextBill = (try? BillsCalendarService().upcomingBills())?
            .min { $0.nextExpectedDate < $1.nextExpectedDate }

        return WidgetSnapshot(
            remainingText: "\(remaining)",
            usedFraction: usedFraction,
            monthEndEpoch: monthEnd.timeIntervalSince1970,
            hasBudget: hasBudget,
            updatedAt: now,
            netWorthText: netWorthText,
            netWorthTrend: (netWorthTrend?.count ?? 0) >= 2 ? netWorthTrend : nil,
            spentText: Money.amount(netConsumed),
            budgetText: hasBudget ? Money.amount(budget) : nil,
            nextBillName: nextBill?.series.merchantPattern,
            nextBillDateEpoch: nextBill?.nextExpectedDate.timeIntervalSince1970,
            nextBillAmountText: nextBill.map { Money.amount($0.series.expectedAmount) }
        )
    }
}

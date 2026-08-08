import Foundation
import GRDB
import UserNotifications
import Persistence

// MARK: - BillsCalendarService (blueprint Phase 4.2)
// Upcoming bills = confirmed RecurringSeries rows projected forward:
// nextExpectedDate = last occurrence + intervalDays. A local notification
// fires 2 days ahead (and on the day) via UNUserNotificationCenter —
// entirely on-device, nothing scheduled leaves the phone.
public final class BillsCalendarService {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    public struct UpcomingBill: Identifiable {
        public let series: RecurringSeries
        public let nextExpectedDate: Date
        public var id: Int64? { series.id }
    }

    /// O(s log n): one indexed max-date lookup per confirmed series.
    public func upcomingBills(withinDays horizon: Int = 45) throws -> [UpcomingBill] {
        try databaseManager.dbQueue().read { db in
            let calendar = Calendar.current
            let cutoff = calendar.date(byAdding: .day, value: horizon, to: Date()) ?? Date()
            var bills: [UpcomingBill] = []
            for series in try RecurringSeries.fetchAll(db) {
                guard let seriesId = series.id else { continue }
                let last = try Persistence.Transaction
                    .filter(GRDB.Column("recurringSeriesId") == seriesId)
                    .order(GRDB.Column("date").desc)
                    .fetchOne(db)?.date ?? Date()
                var next = calendar.date(byAdding: .day, value: series.intervalDays, to: last) ?? last
                // If the projection is already past (missed a cycle), roll
                // forward so the calendar shows the NEXT real due date.
                while next < Date() {
                    guard let rolled = calendar.date(byAdding: .day, value: series.intervalDays, to: next) else { break }
                    next = rolled
                }
                if next <= cutoff {
                    bills.append(UpcomingBill(series: series, nextExpectedDate: next))
                }
            }
            return bills.sorted { $0.nextExpectedDate < $1.nextExpectedDate }
        }
    }

    /// Replaces all pending bill reminders with fresh ones (idempotent —
    /// safe to call on every unlock). Notification content is deliberately
    /// generic-ish: merchant + expected amount, no balances.
    public func rescheduleNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge])
        guard granted else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("bill-") }
        )

        for bill in try upcomingBills() {
            guard let seriesId = bill.series.id else { continue }
            for daysAhead in [2, 0] {
                guard let fireDate = Calendar.current.date(
                    byAdding: .day, value: -daysAhead, to: bill.nextExpectedDate
                ), fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = daysAhead == 0 ? "Bill due today" : "Bill due in 2 days"
                content.body = "\(bill.series.merchantPattern) — expect about \(bill.series.expectedAmount) EGP"

                var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
                components.hour = 9 // Morning reminder, not midnight.
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(
                    identifier: "bill-\(seriesId)-\(daysAhead)",
                    content: content,
                    trigger: trigger
                ))
            }
        }
    }
}

// MARK: - SinkingFundService (blueprint Phase 4.6)
// Simple progress tracking toward a known future expense. Contributions
// are manual; the "on track" math compares saved-so-far against the
// straight-line pace needed to hit targetAmount by targetDate.
public struct SinkingFundService {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    public func allFunds() throws -> [SinkingFund] {
        try databaseManager.dbQueue().read { db in
            try SinkingFund.order(GRDB.Column("targetDate")).fetchAll(db)
        }
    }

    public func create(name: String, targetAmount: Decimal, targetDate: Date, categoryId: Int64?) throws {
        try databaseManager.dbQueue().write { db in
            var fund = SinkingFund(
                name: name, targetAmount: targetAmount, targetDate: targetDate,
                currentAmount: 0, categoryId: categoryId
            )
            try fund.insert(db)
        }
    }

    public func contribute(_ amount: Decimal, to fundId: Int64) throws {
        try databaseManager.dbQueue().write { db in
            guard var fund = try SinkingFund.fetchOne(db, id: fundId) else { return }
            fund.currentAmount += amount
            try fund.update(db)
        }
    }

    /// Monthly amount still needed to land on target by the target date.
    /// Partial months round up, same rule as goal evaluation.
    public func requiredMonthlyContribution(_ fund: SinkingFund) -> Decimal {
        let monthsLeft = SavingsAndGoalsService.monthsRemaining(until: fund.targetDate)
        return max(0, (fund.targetAmount - fund.currentAmount) / Decimal(monthsLeft))
    }
}

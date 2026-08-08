import Foundation
import GRDB
import Persistence

// MARK: - PriceCreepService
// Subscription price-creep alerts: each confirmed RecurringSeries carries
// the amount you AGREED to (expectedAmount). When the latest linked charge
// exceeds it by more than the same ±5% band the detector uses for "same
// amount", that's a real price change, not noise — surface it with the
// old/new numbers. Accepting updates the baseline so the alert clears and
// future creep is measured from the new price.
public struct PriceCreepService {
    private let databaseManager: DatabaseManager
    /// Matches RecurringDetectionService's amount tolerance: within ±5%
    /// is billing noise (FX, rounding); beyond it is a price change.
    private let creepThreshold = Decimal(string: "0.05")!

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    public struct CreepAlert: Identifiable {
        public let series: RecurringSeries
        public let latestAmount: Decimal
        public let latestDate: Date
        /// Whole-percent increase over the agreed price.
        public let increasePercent: Int
        public var id: Int64? { series.id }
    }

    /// O(series × log n): one indexed latest-transaction lookup per series.
    public func creepAlerts() throws -> [CreepAlert] {
        try databaseManager.dbQueue().read { db in
            var alerts: [CreepAlert] = []
            for series in try RecurringSeries.fetchAll(db) {
                guard let seriesId = series.id, series.expectedAmount > 0 else { continue }
                guard let latest = try Persistence.Transaction
                    .filter(GRDB.Column("recurringSeriesId") == seriesId)
                    .order(GRDB.Column("date").desc)
                    .fetchOne(db) else { continue }
                let increase = (latest.amount - series.expectedAmount) / series.expectedAmount
                if increase > creepThreshold {
                    let percent = NSDecimalNumber(decimal: increase * 100).intValue
                    alerts.append(CreepAlert(
                        series: series,
                        latestAmount: latest.amount,
                        latestDate: latest.date,
                        increasePercent: percent
                    ))
                }
            }
            return alerts.sorted { $0.increasePercent > $1.increasePercent }
        }
    }

    /// "Yes, that's the new price" — resets the baseline.
    public func acceptNewPrice(seriesId: Int64, newAmount: Decimal) throws {
        try databaseManager.dbQueue().write { db in
            guard var series = try RecurringSeries.fetchOne(db, id: seriesId) else { return }
            series.expectedAmount = newAmount
            try series.update(db)
        }
    }
}

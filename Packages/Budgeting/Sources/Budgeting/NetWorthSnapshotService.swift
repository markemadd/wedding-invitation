import Foundation
import GRDB
import Persistence

// MARK: - NetWorthSnapshotService
// Closes the Phase 7 ERD-audit gap: NET_WORTH_SNAPSHOT existed in the
// schema with no service writing it. One snapshot per day, captured on
// unlock — freezing what the number actually WAS that day, so the trend
// can't be rewritten by later edits to old transactions.
public struct NetWorthSnapshotService {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// Idempotent per day: O(1) existence probe, then O(accounts +
    /// holdings) to compute. Assets = account balances + holding market
    /// values (both EGP-converted). Liabilities = original debt principal —
    /// a deliberate simplification (true remaining balance needs payment
    /// tracking against the amortization schedule, which isn't modeled);
    /// documented rather than silently wrong.
    public func recordDailySnapshotIfNeeded(now: Date = Date()) throws {
        let calendar = Calendar.current
        guard let dayStart = calendar.dateInterval(of: .day, for: now)?.start else { return }

        try databaseManager.dbQueue().write { db in
            let existing = try NetWorthSnapshot
                .filter(GRDB.Column("date") >= dayStart)
                .fetchCount(db)
            guard existing == 0 else { return }

            let converter = try CurrencyConverter(db: db)
            var assets = try Account.fetchAll(db).reduce(Decimal(0)) {
                $0 + converter.toEGP($1.balance, from: $1.currency)
            }
            // Holdings at cached market price (cost basis when no price).
            let lots = try CostBasisLot.fetchAll(db)
            let lotsByHolding = Dictionary(grouping: lots, by: \.holdingId)
            for holding in try Holding.fetchAll(db) {
                guard let holdingId = holding.id else { continue }
                let myLots = lotsByHolding[holdingId] ?? []
                let quantity = myLots.reduce(Decimal(0)) { $0 + $1.quantity }
                let priceText = try String.fetchOne(
                    db, sql: "SELECT currentPrice FROM holding WHERE id = ?", arguments: [holdingId]
                )
                let price = priceText.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
                let value = price.map { $0 * quantity }
                    ?? myLots.reduce(Decimal(0)) { $0 + $1.quantity * $1.purchasePrice }
                assets += converter.toEGP(value, from: holding.currency)
            }

            let liabilities = try Debt.fetchAll(db).reduce(Decimal(0)) { $0 + $1.principal }

            var snapshot = NetWorthSnapshot(
                date: now,
                totalAssets: assets,
                totalLiabilities: liabilities,
                netWorth: assets - liabilities
            )
            try snapshot.insert(db)
        }
    }
}

import Foundation
import GRDB
import Persistence

// MARK: - InvestmentService (blueprint Phase 5.3)
// Holdings + cost-basis lots, gains/losses, and the self-built asset-class
// breakdown. ACCOUNTING METHOD DECISION (blueprint says decide before
// writing): FIFO — oldest lots are consumed first on partial sales. FIFO
// is the default under Egyptian and most tax regimes, matches broker
// statements, and is deterministic without per-sale user interaction;
// specific-lot selection can be added later without schema changes.
public final class InvestmentService {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    // MARK: CRUD

    public func addHolding(ticker: String, assetClass: String, currency: String) throws -> Holding {
        try databaseManager.dbQueue().write { db in
            var holding = Holding(ticker: ticker.uppercased(), assetClass: assetClass, currency: currency)
            try holding.insert(db)
            return holding
        }
    }

    public func addLot(holdingId: Int64, quantity: Decimal, purchasePrice: Decimal, purchaseDate: Date) throws {
        guard quantity > 0, purchasePrice >= 0 else { throw InvestmentError.invalidLot }
        try databaseManager.dbQueue().write { db in
            var lot = CostBasisLot(
                holdingId: holdingId, quantity: quantity,
                purchasePrice: purchasePrice, purchaseDate: purchaseDate
            )
            try lot.insert(db)
        }
    }

    /// FIFO sale: consumes oldest lots first, returns the realized gain.
    /// O(lots log lots) for the sort; lot counts are tiny.
    public func recordSale(holdingId: Int64, quantity: Decimal, salePrice: Decimal) throws -> Decimal {
        try databaseManager.dbQueue().write { db in
            var remaining = quantity
            var realizedGain = Decimal(0)
            let lots = try CostBasisLot
                .filter(GRDB.Column("holdingId") == holdingId)
                .order(GRDB.Column("purchaseDate")) // FIFO: oldest first.
                .fetchAll(db)
            let totalHeld = lots.reduce(Decimal(0)) { $0 + $1.quantity }
            guard quantity > 0, quantity <= totalHeld else { throw InvestmentError.oversell }

            for var lot in lots where remaining > 0 {
                let consumed = min(lot.quantity, remaining)
                realizedGain += (salePrice - lot.purchasePrice) * consumed
                remaining -= consumed
                if consumed == lot.quantity {
                    try lot.delete(db)
                } else {
                    lot.quantity -= consumed
                    try lot.update(db)
                }
            }
            return realizedGain
        }
    }

    public func updateCurrentPrice(holdingId: Int64, price: Decimal) throws {
        try databaseManager.dbQueue().write { db in
            try db.execute(
                sql: "UPDATE holding SET currentPrice = ?, priceUpdatedAt = ? WHERE id = ?",
                arguments: ["\(price)", Date(), holdingId]
            )
        }
    }

    // MARK: Positions

    public struct Position: Identifiable {
        public let holding: Holding
        public let quantity: Decimal
        public let costBasis: Decimal
        public let currentPrice: Decimal?
        /// (currentPrice − avg lot price) × quantity, summed per lot; nil
        /// until a current price exists.
        public let unrealizedGain: Decimal?
        public let marketValue: Decimal?
        public var id: Int64? { holding.id }
    }

    /// O(h + l): one pass over holdings and lots.
    public func positions() throws -> [Position] {
        try databaseManager.dbQueue().read { db in
            let holdings = try Holding.fetchAll(db)
            let lots = try CostBasisLot.fetchAll(db)
            let lotsByHolding = Dictionary(grouping: lots, by: \.holdingId)

            return holdings.compactMap { holding in
                guard let holdingId = holding.id else { return nil }
                let myLots = lotsByHolding[holdingId] ?? []
                let quantity = myLots.reduce(Decimal(0)) { $0 + $1.quantity }
                let costBasis = myLots.reduce(Decimal(0)) { $0 + $1.quantity * $1.purchasePrice }

                // Cached price columns live outside the record type (added
                // in migration v3); read via raw row to keep the ERD-shaped
                // Holding record untouched.
                let priceText = try? String.fetchOne(
                    db, sql: "SELECT currentPrice FROM holding WHERE id = ?", arguments: [holdingId]
                )
                let currentPrice = priceText.flatMap {
                    Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
                }
                let unrealized = currentPrice.map { price in
                    myLots.reduce(Decimal(0)) { $0 + ($1.quantity * (price - $1.purchasePrice)) }
                }
                return Position(
                    holding: holding,
                    quantity: quantity,
                    costBasis: costBasis,
                    currentPrice: currentPrice,
                    unrealizedGain: unrealized,
                    marketValue: currentPrice.map { $0 * quantity }
                )
            }
        }
    }

    /// Asset-class breakdown: market value (or cost basis when no price)
    /// grouped by the manually maintained assetClass field — the
    /// self-built approximation of a fund-analysis view.
    public func assetClassBreakdown() throws -> [(assetClass: String, value: Decimal)] {
        let all = try positions()
        var byClass: [String: Decimal] = [:]
        for position in all {
            byClass[position.holding.assetClass, default: 0] += position.marketValue ?? position.costBasis
        }
        return byClass.map { ($0.key, $0.value) }.sorted { $0.value > $1.value }
    }
}

public enum InvestmentError: Error, LocalizedError {
    case invalidLot
    case oversell

    public var errorDescription: String? {
        switch self {
        case .invalidLot: return "A lot needs a positive quantity and a non-negative price."
        case .oversell: return "You can't sell more than you hold."
        }
    }
}

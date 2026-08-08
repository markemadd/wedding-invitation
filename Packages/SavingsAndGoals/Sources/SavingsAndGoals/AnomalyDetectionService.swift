import Foundation
import GRDB
import Budgeting
import Persistence

// MARK: - AnomalyDetectionService (blueprint Phase 4.3)
// Two deterministic checks on a just-captured transaction:
//  1. Amount anomaly — z-score style: flag when |amount − categoryMean|
//     exceeds 2 × categoryStdDev. Plain arithmetic beats any model here:
//     explainable, cheap, and tunable (the 2σ cutoff is the classic
//     "unusual but not paranoid" threshold; ~5% flag rate on normal data).
//  2. Likely duplicate — same merchant, same amount, within a few minutes
//     (double-tap on a form, a Shortcut firing twice).
public struct AnomalyDetectionService {
    private let databaseManager: DatabaseManager
    /// Duplicates: same merchant+amount within this many seconds.
    private let duplicateWindow: TimeInterval = 10 * 60
    private let zScoreCutoff = Decimal(2)

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    public struct Findings {
        public let isAmountAnomalous: Bool
        public let categoryMean: Decimal?
        public let likelyDuplicateOf: Persistence.Transaction?
        public var isClean: Bool { !isAmountAnomalous && likelyDuplicateOf == nil }
    }

    /// O(m) over the transaction's category history (index-assisted fetch)
    /// + O(log n) duplicate probe. Amounts are compared in EGP so a EUR
    /// purchase doesn't look "anomalous" purely by currency.
    public func check(_ transaction: Persistence.Transaction) throws -> Findings {
        try databaseManager.dbQueue().read { db in
            let converter = try CurrencyConverter(db: db)
            let amountEGP = converter.toEGP(transaction.amount, from: transaction.currency)

            // History for this category, excluding the row being checked.
            let history = try Persistence.Transaction
                .filter(GRDB.Column("categoryId") == transaction.categoryId)
                .filter(GRDB.Column("direction") == "expense") // Income isn't a spending baseline.
                .filter(GRDB.Column("id") != (transaction.id ?? -1))
                .fetchAll(db)
                .map { converter.toEGP($0.amount, from: $0.currency) }

            var anomalous = false
            var mean: Decimal?
            if history.count >= 5 { // Below 5 samples σ is meaningless noise.
                let m = history.reduce(Decimal(0), +) / Decimal(history.count)
                mean = m
                let variance = history.reduce(Decimal(0)) { $0 + ($1 - m) * ($1 - m) } / Decimal(history.count)
                // One Double round-trip for the square root only — the
                // comparison threshold doesn't need Decimal exactness.
                let stdDev = Decimal(NSDecimalNumber(decimal: variance).doubleValue.squareRoot())
                if stdDev > 0 {
                    anomalous = abs(amountEGP - m) > zScoreCutoff * stdDev
                }
            }

            let windowStart = transaction.date.addingTimeInterval(-duplicateWindow)
            let windowEnd = transaction.date.addingTimeInterval(duplicateWindow)
            let duplicate = try Persistence.Transaction
                .filter(GRDB.Column("id") != (transaction.id ?? -1))
                .filter(GRDB.Column("merchant") == transaction.merchant)
                .filter(GRDB.Column("amount") == "\(transaction.amount)")
                .filter(GRDB.Column("date") >= windowStart && GRDB.Column("date") <= windowEnd)
                .fetchOne(db)

            return Findings(
                isAmountAnomalous: anomalous,
                categoryMean: mean,
                likelyDuplicateOf: duplicate
            )
        }
    }
}

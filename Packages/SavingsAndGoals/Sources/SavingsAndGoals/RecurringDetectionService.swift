import Foundation
import GRDB
import Persistence

// MARK: - RecurringDetectionService (blueprint Phase 4.1)
// Statistical periodicity detection, deliberately NOT LLM-based — this is
// a well-defined pattern-matching problem (similar to approaches described
// in Plaid's and Intuit's public engineering writeups on recurring-
// transaction detection) that a simple algorithm solves more reliably and
// far more cheaply than invoking a language model.
//
// Candidates are SURFACED FOR USER CONFIRMATION, never auto-committed:
// with only 3 data points false positives are inevitable, and a wrong
// auto-classification is more annoying than a missed one.
public final class RecurringDetectionService {
    private let databaseManager: DatabaseManager
    /// 5% tolerance band for "same" amount.
    private let amountTolerance = Decimal(string: "0.05")!
    /// Common billing cycles in days: weekly, biweekly, monthly,
    /// quarterly, yearly.
    private let candidateIntervals = [7, 14, 30, 90, 365]

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// Groups transactions by merchant, then checks whether the gaps
    /// between consecutive occurrences cluster near one of the candidate
    /// intervals. Time complexity: O(n log n) dominated by the per-merchant
    /// date sort; grouping first keeps this from ever becoming an O(n²)
    /// pass over full history as years accumulate.
    /// Excludes merchants already linked to a confirmed series.
    public func detectRecurringSeries() throws -> [RecurringSeriesCandidate] {
        try databaseManager.dbQueue().read { db in
            let confirmedPatterns = Set(
                try RecurringSeries.fetchAll(db).map { $0.merchantPattern.lowercased() }
            )
            let transactions = try Persistence.Transaction
                .filter(GRDB.Column("merchant") != nil)
                .fetchAll(db)
            let byMerchant = Dictionary(grouping: transactions) {
                ($0.merchant ?? "").lowercased()
            }

            var candidates: [RecurringSeriesCandidate] = []
            for (merchant, txns) in byMerchant
            where txns.count >= 3 && !merchant.isEmpty && !confirmedPatterns.contains(merchant) {
                // Need at least 3 occurrences to trust a pattern.
                let sorted = txns.sorted { $0.date < $1.date }
                let amounts = sorted.map(\.amount)
                guard amountsAreConsistent(amounts) else { continue }

                let gaps = zip(sorted, sorted.dropFirst()).compactMap {
                    Calendar.current.dateComponents([.day], from: $0.date, to: $1.date).day
                }
                guard !gaps.isEmpty, gaps.allSatisfy({ $0 > 0 }) else { continue }

                if let matchedInterval = bestMatchingInterval(for: gaps) {
                    let confidence = confidenceScore(gaps: gaps, matchedInterval: matchedInterval)
                    guard confidence > Decimal(string: "0.5")! else { continue } // Below coin-flip: noise, not a pattern.
                    candidates.append(RecurringSeriesCandidate(
                        merchant: sorted[0].merchant ?? merchant,
                        categoryId: sorted.last?.categoryId ?? 0,
                        intervalDays: matchedInterval,
                        expectedAmount: amounts.reduce(Decimal(0), +) / Decimal(amounts.count),
                        confidence: confidence,
                        lastOccurrence: sorted.last?.date ?? Date()
                    ))
                }
            }
            return candidates.sorted { $0.confidence > $1.confidence }
        }
    }

    /// User confirmed a candidate: create the series row and back-link the
    /// matching transactions so future summaries can distinguish
    /// subscription spend.
    public func confirm(_ candidate: RecurringSeriesCandidate) throws {
        try databaseManager.dbQueue().write { db in
            var series = RecurringSeries(
                merchantPattern: candidate.merchant,
                categoryId: candidate.categoryId,
                intervalDays: candidate.intervalDays,
                expectedAmount: candidate.expectedAmount,
                confidence: candidate.confidence
            )
            try series.insert(db)
            guard let seriesId = series.id else { return }
            try db.execute(
                sql: """
                    UPDATE "transaction" SET recurringSeriesId = ?
                    WHERE LOWER(merchant) = LOWER(?) AND recurringSeriesId IS NULL
                    """,
                arguments: [seriesId, candidate.merchant]
            )
        }
    }

    /// All amounts within ±5% of the first — subscriptions drift a little
    /// (FX, price bumps mid-window), identical-amount matching would miss
    /// real series.
    private func amountsAreConsistent(_ amounts: [Decimal]) -> Bool {
        guard let first = amounts.first, first > 0 else { return false }
        return amounts.allSatisfy { abs($0 - first) / first <= amountTolerance }
    }

    private func bestMatchingInterval(for gaps: [Int]) -> Int? {
        guard !gaps.isEmpty else { return nil }
        let averageGap = Decimal(gaps.reduce(0, +)) / Decimal(gaps.count)
        return candidateIntervals.min {
            abs(Decimal($0) - averageGap) < abs(Decimal($1) - averageGap)
        }
    }

    /// Lower variance around the matched interval = higher confidence.
    /// A simple, explainable heuristic — the goal is a number you can
    /// sanity-check at a glance, not an opaque statistical model.
    private func confidenceScore(gaps: [Int], matchedInterval: Int) -> Decimal {
        let deviations = gaps.map { abs($0 - matchedInterval) }
        let averageDeviation = Decimal(deviations.reduce(0, +)) / Decimal(deviations.count)
        return max(0, 1 - (averageDeviation / Decimal(matchedInterval)))
    }
}

public struct RecurringSeriesCandidate: Identifiable {
    public let merchant: String
    /// Category of the most recent occurrence — the best guess for the
    /// series' category, editable at confirmation time.
    public let categoryId: Int64
    public let intervalDays: Int
    public let expectedAmount: Decimal
    public let confidence: Decimal
    public let lastOccurrence: Date

    public var id: String { merchant }
    /// Blueprint 4.2: next expected = last occurrence + interval.
    public var nextExpectedDate: Date {
        Calendar.current.date(byAdding: .day, value: intervalDays, to: lastOccurrence) ?? lastOccurrence
    }
}

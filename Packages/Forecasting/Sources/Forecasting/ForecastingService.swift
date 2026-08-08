import Foundation
import SavingsAndGoals

// MARK: - ForecastingService (blueprint Phase 5.2)
// Monte Carlo net worth projection over the user's OWN historical
// cash-flow variance — not a naive straight-line. Methodology lineage:
// Bengen's 1994 "4% rule" work and the Trinity study; per the updated
// guidance in Morningstar's annually-republished State of Retirement
// Income (2025 edition: 3.9% base-case safe withdrawal, forward-looking
// assumptions, 90% success probability target), results are reported as
// PERCENTILE BANDS and a success probability, never one confident number.
public final class ForecastingService {
    /// Enough trials for stable percentile bands without excessive
    /// on-device compute.
    private let trialCount = 1_000

    public init() {}

    public struct ForecastResult {
        public let p10: Decimal // Pessimistic band.
        public let p50: Decimal // Median outcome.
        public let p90: Decimal // Optimistic band.
        /// Fraction of trials ending at or above `successThreshold`
        /// (Morningstar-style success probability), nil if no threshold.
        public let successProbability: Double?
    }

    /// O(trials × months) — 1,000 × 24 = 24,000 additions, trivial
    /// on-device. Draws monthly savings from a normal distribution fitted
    /// to the actual historical mean/variance.
    public func projectNetWorth(
        monthsAhead: Int,
        currentNetWorth: Decimal,
        historicalMonthlySavings: [Decimal],
        successThreshold: Decimal? = nil
    ) -> ForecastResult {
        let count = max(1, historicalMonthlySavings.count)
        let mean = historicalMonthlySavings.reduce(Decimal(0), +) / Decimal(count)
        let variance = historicalMonthlySavings.reduce(Decimal(0)) {
            $0 + ($1 - mean) * ($1 - mean)
        } / Decimal(count)
        // Double is acceptable HERE and only here: simulation draws are
        // statistical estimates by nature, not ledger arithmetic.
        let meanD = NSDecimalNumber(decimal: mean).doubleValue
        let stdDev = NSDecimalNumber(decimal: variance).doubleValue.squareRoot()
        let startD = NSDecimalNumber(decimal: currentNetWorth).doubleValue

        var finalOutcomes: [Double] = []
        finalOutcomes.reserveCapacity(trialCount)
        for _ in 0..<trialCount {
            var netWorth = startD
            for _ in 0..<monthsAhead {
                netWorth += sampleNormal(mean: meanD, stdDev: stdDev)
            }
            finalOutcomes.append(netWorth)
        }
        finalOutcomes.sort()

        var successProbability: Double?
        if let threshold = successThreshold {
            let thresholdD = NSDecimalNumber(decimal: threshold).doubleValue
            let successes = finalOutcomes.filter { $0 >= thresholdD }.count
            successProbability = Double(successes) / Double(trialCount)
        }

        func percentile(_ p: Double) -> Decimal {
            Decimal(finalOutcomes[Int(Double(trialCount - 1) * p)])
        }
        return ForecastResult(
            p10: percentile(0.10),
            p50: percentile(0.50),
            p90: percentile(0.90),
            successProbability: successProbability
        )
    }

    /// Box-Muller transform — the standard, well-documented method for
    /// normal samples from two uniform draws.
    private func sampleNormal(mean: Double, stdDev: Double) -> Double {
        let u1 = Double.random(in: 0.0001...0.9999)
        let u2 = Double.random(in: 0...1)
        let z0 = (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * .pi * u2)
        return mean + z0 * stdDev
    }
}

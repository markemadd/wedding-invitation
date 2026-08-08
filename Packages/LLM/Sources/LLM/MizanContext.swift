import Foundation

// MARK: - MizanContext (ENHANCEMENTS Wave C1)
// A small block of REAL numbers injected before each LLM call so the model
// answers from actual data instead of hallucinating figures. Deliberately
// compact (well under ~400 tokens) — the LLM's job is language, never
// arithmetic; every number here is computed by the deterministic
// Budgeting/Forecasting code and merely narrated by the model.
public struct MizanContext: Encodable {
    public let currentMonth: String
    public let totalSpent: String
    public let income: String
    public let topCategories: [String] // ["Food: 3,800", "Transfer: 8,300", …]
    public let budgetUsedPercent: Int
    public let netWorth: String

    public init(
        currentMonth: String,
        totalSpent: String,
        income: String,
        topCategories: [String],
        budgetUsedPercent: Int,
        netWorth: String
    ) {
        self.currentMonth = currentMonth
        self.totalSpent = totalSpent
        self.income = income
        self.topCategories = topCategories
        self.budgetUsedPercent = budgetUsedPercent
        self.netWorth = netWorth
    }

    /// Plain-text rendering handed to the prompt templates. Kept terse and
    /// label-per-line so a small on-device model parses it reliably.
    public var summary: String {
        """
        Month: \(currentMonth)
        Income this month: \(income) EGP
        Spent this month: \(totalSpent) EGP
        Budget used: \(budgetUsedPercent)%
        Net worth: \(netWorth) EGP
        Top categories: \(topCategories.isEmpty ? "none yet" : topCategories.joined(separator: ", "))
        """
    }
}

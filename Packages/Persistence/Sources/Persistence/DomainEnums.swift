import Foundation

// MARK: - Shared domain enums
// These live in Persistence (not in the feature modules) because they are
// stored in the database as raw strings and read by several modules:
// the bucket classification drives Phase 4's goal-planner cut suggestions,
// and the transaction source tag is written by every Phase 2 capture path.

/// How a spending category behaves month to month (blueprint Section 3,
/// "category-based / flexible budgeting mode"). Chosen at category creation
/// time — Phase 4's cut-suggestion logic can only propose cuts in `flexible`
/// categories when a goal's scope says so, which is why this classification
/// cannot be an afterthought.
public enum CategoryBucket: String, Codable, CaseIterable, Sendable {
    case fixed
    case nonMonthlyRecurring
    case flexible
}

/// Which categories a goal is allowed to suggest cuts from (blueprint 4.4).
public enum GoalCutScope: String, Codable, CaseIterable, Sendable {
    case flexibleOnly
    case anyCategory
}

/// Which capture path created a transaction (blueprint Phase 2). Stored as
/// text so the review UI and any future debugging can always tell where a
/// row came from.
public enum TransactionSource: String, Codable, CaseIterable, Sendable {
    case manual
    case receiptOCR
    case walletIntent
    case voice
    /// Bank notification SMS — via the Shortcuts message automation
    /// intent or the in-app paste flow (post-blueprint, user-requested).
    case sms
}

/// How an account is held/paid from. Stored in Account's existing `type`
/// text column (no schema change — the ERD already modeled type). The
/// distinction the user cares about at capture time is "which card did I
/// pay with, credit or debit" — hence cards are first-class account types,
/// not a transaction-level afterthought, which also keeps per-card
/// balances and statements possible later.
public enum AccountType: String, Codable, CaseIterable, Sendable {
    case cash
    case bank
    case debitCard
    case creditCard

    public var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .bank: return "Bank Account"
        case .debitCard: return "Debit Card"
        case .creditCard: return "Credit Card"
        }
    }
}

/// Money out vs money in (post-blueprint, user-requested for InstaPay).
/// Spending aggregates NET the two per category — an InstaPay category
/// with sends and receives cancels toward zero — while monthly savings
/// treats net income transfers as money that increases the allowance.
public enum TransactionDirection: String, Codable, CaseIterable, Sendable {
    case expense
    case income
}

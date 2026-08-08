import Foundation
import GRDB

// MARK: - StarterDataBootstrapper
// Phase 2 needs valid account/category foreign keys before Phase 3's CRUD
// screens exist, so the first unlock seeds a minimal, sensible starter set.
// Everything here is plain data the user can rename/delete in Phase 3 —
// no behavior depends on these exact names. Buckets are assigned carefully
// because Phase 4's cut suggestions depend on them.
//
// "Uncategorized" is special: it's the safe landing spot for wallet-intent
// and voice captures whose category couldn't be guessed. It must always
// exist, which is why it's seeded here rather than left to the user.
public struct StarterDataBootstrapper {
    /// Injected so tests can seed a temp database; production uses .shared.
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// The user's canonical category list (provided 2026-07-05), plus the
    /// always-present "Uncategorized" fallback. Buckets are best-guess
    /// defaults — barber is recurring-but-not-monthly; everything else in
    /// this list is discretionary/variable spending (fixed things like
    /// rent/subscriptions weren't in the user's list; they can be added
    /// through Phase 3's category CRUD with the right bucket).
    static let canonicalCategories: [(name: String, bucket: CategoryBucket)] = [
        ("Uncategorized", .flexible),
        ("food", .flexible),
        ("gas", .flexible),
        ("barber", .nonMonthlyRecurring),
        ("coffee", .flexible),
        ("cinema", .flexible),
        ("shopping", .flexible),
        ("transportation", .flexible),
        ("travel", .flexible),
        ("luxury", .flexible),
        ("supermarket", .flexible),
        ("sports", .flexible),
        ("instapay", .flexible)   // Transfers in/out — net toward zero by design.
    ]

    /// Names from the pre-user-list starter set; removed on sync if the
    /// user never attached transactions to them.
    private static let retiredStarterNames: Set<String> = [
        "Groceries", "Dining", "Transport", "Shopping", "Rent",
        "Utilities", "Subscriptions", "Health", "Education"
    ]

    /// Idempotent, called on every unlock. Accounts seed once (COUNT
    /// guard, O(1)); categories SYNC to the canonical list — inserting
    /// missing names and retiring old starter names that carry no
    /// transactions — so an already-installed device migrates itself
    /// without a destructive reset. O(k) over categories, k ≈ a dozen.
    public func seedIfNeeded() throws {
        let dbQueue = try databaseManager.dbQueue()
        try dbQueue.write { db in
            if try Account.fetchCount(db) == 0 {
                var cash = Account(name: "Cash", type: AccountType.cash.rawValue, currency: "EGP", balance: 0)
                try cash.insert(db)
                var bank = Account(name: "Bank", type: AccountType.bank.rawValue, currency: "EGP", balance: 0)
                try bank.insert(db)
            }

            let existingNames = Set(try Category.fetchAll(db).map(\.name))
            for (name, bucket) in Self.canonicalCategories where !existingNames.contains(name) {
                var category = Category(name: name, bucket: bucket)
                try category.insert(db)
            }

            // Seed FX rates once — PLACEHOLDER values the user must adjust
            // in Settings (manual by design, no network; Phase 5's narrow
            // FX fetch can update them later). EGP itself is always 1.
            if try FxRate.fetchCount(db) == 0 {
                let now = Date()
                for (code, rate) in [("EGP", "1"), ("EUR", "55"), ("USD", "50"), ("GBP", "64")] {
                    var fx = FxRate(currencyCode: code, rateToEGP: Decimal(string: rate)!, updatedAt: now)
                    try fx.insert(db)
                }
            }

            // Retire old starter categories — but never one that has
            // transactions (deleting it would orphan rows or lose data).
            for category in try Category.fetchAll(db)
            where Self.retiredStarterNames.contains(category.name) {
                guard let id = category.id else { continue }
                let inUse = try Transaction.filter(GRDB.Column("categoryId") == id).fetchCount(db) > 0
                if !inUse {
                    try category.delete(db)
                }
            }
        }
    }

    /// The account wallet-intent captures default into (blueprint 2.3's
    /// Account.defaultAccountId). Currently: the first account by id —
    /// good enough until Phase 3 adds an explicit "default account" choice.
    public static func defaultAccountId(_ db: Database) throws -> Int64 {
        guard let account = try Account.order(GRDB.Column("id")).fetchOne(db), let id = account.id else {
            throw StarterDataError.noAccountsExist
        }
        return id
    }

    /// The always-present fallback category for unattributed captures.
    public static func uncategorizedCategoryId(_ db: Database) throws -> Int64 {
        guard let category = try Category.filter(GRDB.Column("name") == "Uncategorized").fetchOne(db),
              let id = category.id else {
            throw StarterDataError.uncategorizedMissing
        }
        return id
    }
}

public enum StarterDataError: Error {
    case noAccountsExist
    case uncategorizedMissing
}

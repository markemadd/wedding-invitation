import Foundation
import GRDB
import Persistence

// MARK: - TransactionWriter (blueprint Phase 2 watch-out)
// Every capture path — manual form, OCR review, wallet App Intent, voice —
// funnels through this one type. Validation rules live in exactly one
// place, so OCR, voice, and the intent can never grow slightly-different
// insert code that drifts apart over time.
public struct TransactionWriter {
    /// Injected so tests run against a temp database; production callers
    /// use the default shared instance.
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// Validates and inserts. O(log n) per existence check (primary-key
    /// lookups), O(log n) insert — constant work per capture regardless of
    /// how large the transaction history grows.
    @discardableResult
    public func insert(_ draft: TransactionDraft) throws -> Persistence.Transaction {
        try Self.validate(draft)
        let dbQueue = try databaseManager.dbQueue()
        return try dbQueue.write { db in
            try Self.insertValidated(draft, db: db)
        }
    }

    /// Two drafts land in ONE write transaction — built for transfers, where
    /// the pair is a single logical move of money. Either both legs commit or
    /// neither does, so a failure between them can never debit the source
    /// account without crediting the destination.
    @discardableResult
    public func insertPair(
        _ first: TransactionDraft,
        _ second: TransactionDraft
    ) throws -> (Persistence.Transaction, Persistence.Transaction) {
        try Self.validate(first)
        try Self.validate(second)
        let dbQueue = try databaseManager.dbQueue()
        return try dbQueue.write { db in
            (try Self.insertValidated(first, db: db), try Self.insertValidated(second, db: db))
        }
    }

    /// Defensive validation: drafts come from OCR guesses, voice parses,
    /// and an external Shortcuts automation — none of which are trusted
    /// in-app forms. Reject bad values before they reach the database.
    private static func validate(_ draft: TransactionDraft) throws {
        guard draft.amount > 0 else {
            throw TransactionWriteError.nonPositiveAmount(draft.amount)
        }
        guard !draft.currency.isEmpty else {
            throw TransactionWriteError.missingCurrency
        }
    }

    /// The insert body shared by `insert` and `insertPair`, run inside an
    /// already-open write transaction so callers control atomicity.
    private static func insertValidated(_ draft: TransactionDraft, db: Database) throws -> Persistence.Transaction {
        guard try Account.exists(db, id: draft.accountId) else {
            throw TransactionWriteError.unknownAccount(draft.accountId)
        }
        guard try Persistence.Category.exists(db, id: draft.categoryId) else {
            throw TransactionWriteError.unknownCategory(draft.categoryId)
        }
        var transaction = Persistence.Transaction(
            accountId: draft.accountId,
            categoryId: draft.categoryId,
            amount: draft.amount,
            currency: draft.currency,
            date: draft.date,
            merchant: draft.merchant?.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source,
            direction: draft.direction
        )
        try transaction.insert(db)
        // Auto-link to a confirmed recurring series by merchant, so
        // later charges keep feeding the bills calendar and the
        // price-creep alerts. O(1) indexed lookup.
        if transaction.recurringSeriesId == nil, let merchant = transaction.merchant {
            if let seriesId = try Int64.fetchOne(db, sql: """
                SELECT id FROM recurringSeries WHERE LOWER(merchantPattern) = ? LIMIT 1
                """, arguments: [merchant.lowercased()]) {
                transaction.recurringSeriesId = seriesId
                try transaction.update(db)
            }
        }
        try Self.applyBalanceEffect(of: transaction, db: db, sign: +1)
        return transaction
    }

    // MARK: - Account balance maintenance
    // Balances start from the figure the user sets in Settings and then
    // track activity automatically: expenses subtract, income adds — the
    // fix for "net worth is always 0" (balances previously never moved).
    // Every mutation reverts/applies inside the same write transaction as
    // the row change, so balances can never drift out of sync.

    /// sign +1 applies the transaction's effect, -1 reverts it (for
    /// updates and deletes). Cross-currency: the amount converts through
    /// the fxRate table into the account's currency. O(1) lookups.
    static func applyBalanceEffect(of transaction: Persistence.Transaction, db: Database, sign: Int) throws {
        guard var account = try Account.fetchOne(db, id: transaction.accountId) else { return }

        var delta = transaction.amount
        if transaction.currency != account.currency {
            let rates = Dictionary(
                uniqueKeysWithValues: try FxRate.fetchAll(db).map { ($0.currencyCode, $0.rateToEGP) }
            )
            let toEGP = rates[transaction.currency] ?? 1
            let accountRate = rates[account.currency] ?? 1
            // txn currency → EGP → account currency.
            delta = accountRate > 0 ? (transaction.amount * toEGP) / accountRate : transaction.amount
        }
        let directed = transaction.direction == .income ? delta : -delta
        account.balance += Decimal(sign) * directed
        try account.update(db)
    }

    /// Swipe-to-edit (Phase 3.5) goes through the SAME validation as
    /// inserts — an edit can introduce exactly the same bad data a new
    /// entry can. Source is preserved: editing a receipt capture doesn't
    /// make it "manual".
    public func update(transactionId: Int64, with draft: TransactionDraft) throws {
        guard draft.amount > 0 else {
            throw TransactionWriteError.nonPositiveAmount(draft.amount)
        }
        guard !draft.currency.isEmpty else {
            throw TransactionWriteError.missingCurrency
        }
        let dbQueue = try databaseManager.dbQueue()
        try dbQueue.write { db in
            guard var transaction = try Persistence.Transaction.fetchOne(db, id: transactionId) else {
                throw TransactionWriteError.unknownTransaction(transactionId)
            }
            guard try Account.exists(db, id: draft.accountId) else {
                throw TransactionWriteError.unknownAccount(draft.accountId)
            }
            guard try Persistence.Category.exists(db, id: draft.categoryId) else {
                throw TransactionWriteError.unknownCategory(draft.categoryId)
            }
            // Revert the OLD row's balance effect before mutating (the
            // edit may change amount, direction, or even the account).
            try Self.applyBalanceEffect(of: transaction, db: db, sign: -1)
            transaction.accountId = draft.accountId
            transaction.categoryId = draft.categoryId
            transaction.amount = draft.amount
            transaction.currency = draft.currency
            transaction.date = draft.date
            transaction.merchant = draft.merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.direction = draft.direction
            try transaction.update(db)
            try Self.applyBalanceEffect(of: transaction, db: db, sign: +1)
        }
    }

    public func delete(transactionId: Int64) throws {
        let dbQueue = try databaseManager.dbQueue()
        _ = try dbQueue.write { db in
            if let transaction = try Persistence.Transaction.fetchOne(db, id: transactionId) {
                try Self.applyBalanceEffect(of: transaction, db: db, sign: -1)
            }
            try Persistence.Transaction.deleteOne(db, id: transactionId)
        }
    }
}

// MARK: - TransactionDraft
// The unvalidated "maybe a transaction" every capture path produces and
// every review screen edits. Deliberately separate from the Transaction
// record: a draft may be incomplete or wrong (OCR misreads), and only
// TransactionWriter turns it into a database row.
public struct TransactionDraft {
    public var accountId: Int64
    public var categoryId: Int64
    public var amount: Decimal
    public var currency: String
    public var date: Date
    public var merchant: String?
    public var source: TransactionSource
    public var direction: TransactionDirection

    public init(
        accountId: Int64,
        categoryId: Int64,
        amount: Decimal,
        currency: String = "EGP",
        date: Date = Date(),
        merchant: String? = nil,
        source: TransactionSource,
        direction: TransactionDirection = .expense
    ) {
        self.accountId = accountId
        self.categoryId = categoryId
        self.amount = amount
        self.currency = currency
        self.date = date
        self.merchant = merchant
        self.source = source
        self.direction = direction
    }
}

public enum TransactionWriteError: Error, LocalizedError, Equatable {
    case nonPositiveAmount(Decimal)
    case missingCurrency
    case unknownAccount(Int64)
    case unknownCategory(Int64)
    case unknownTransaction(Int64)

    public var errorDescription: String? {
        switch self {
        case .nonPositiveAmount(let amount):
            return "Amount must be greater than zero (got \(amount))."
        case .missingCurrency:
            return "A currency is required."
        case .unknownAccount(let id):
            return "No account with id \(id) exists."
        case .unknownCategory(let id):
            return "No category with id \(id) exists."
        case .unknownTransaction(let id):
            return "No transaction with id \(id) exists."
        }
    }
}

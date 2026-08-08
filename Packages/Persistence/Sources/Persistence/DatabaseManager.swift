import Foundation
import GRDB

// MARK: - DatabaseManager (blueprint Phase 1.2)
// Single source of truth for the encrypted connection. Every service in
// every later phase (Budgeting, SavingsAndGoals, Capture, etc.) reads
// through this, never opens SQLite directly. That rule is what makes the
// encryption and lock behavior enforceable in one place.
public final class DatabaseManager {
    /// The app-wide instance. Call `configure(keyProvider:)` once at launch
    /// before anything touches the database.
    public static let shared = DatabaseManager()

    private var _dbQueue: DatabaseQueue?
    private var keyProvider: DatabaseKeyProviding?
    private let databaseURL: URL
    /// Guards _dbQueue and keyProvider: dbQueue() can be called from the
    /// main actor (UI) and from an App Intent's background context at the
    /// same time, and a torn read during logout would defeat the lock.
    private let stateLock = NSLock()

    /// Production singleton: database lives in Application Support.
    private init() {
        // Application Support is the sandbox location Apple designates for
        // exactly this kind of non-user-visible data file. It is NOT backed
        // up in plaintext anywhere by us; iCloud/iTunes device backups see
        // only the SQLCipher-encrypted bytes.
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.databaseURL = supportDir.appendingPathComponent("finance.sqlite")
    }

    /// Test/preview initializer: explicit key source and file location, so
    /// tests never touch the real Keychain or the real database file.
    public init(keyProvider: DatabaseKeyProviding, databaseURL: URL) {
        self.keyProvider = keyProvider
        self.databaseURL = databaseURL
    }

    /// One-time wiring at app launch (MizanApp.init). Kept separate from
    /// init because the production key provider lives in MizanSecurity,
    /// which Persistence deliberately does not import.
    public func configure(keyProvider: DatabaseKeyProviding) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.keyProvider = keyProvider
    }

    /// Throws if the app is locked or unconfigured — this is the enforcement
    /// point. Every service function should start with
    /// `try DatabaseManager.shared.dbQueue()` rather than caching a
    /// reference, so a stale unlocked connection can never survive past a
    /// logout.
    public func dbQueue() throws -> DatabaseQueue {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let queue = _dbQueue { return queue }
        return try openConnection()
    }

    /// Called by lock/logout (Phase 1.3/1.4). This is what makes logout
    /// meaningfully stronger than a UI-only lock: the decrypted connection
    /// is torn down, not just hidden behind a lock screen.
    public func invalidateSession() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _dbQueue = nil
    }

    /// Used by BackupService to read the (SQLCipher-encrypted) file bytes.
    public func currentDatabaseFileURL() -> URL {
        databaseURL
    }

    /// Deletes every row from every user table, keeping the schema and the
    /// migration history intact (so the app stays on the current version and
    /// the caller can immediately re-seed the starter set). Powers the
    /// Settings "Erase all data" control. Foreign keys are deferred to commit,
    /// where — with every table emptied — there are no references left to
    /// violate, so delete order doesn't matter. One write transaction: it's
    /// all-or-nothing.
    public func eraseAllData() throws {
        let queue = try dbQueue()
        try queue.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name != 'grdb_migrations'
                """)
            for table in tables {
                try db.execute(sql: "DELETE FROM \"\(table)\"")
            }
        }
    }

    /// A consistent copy of the database file for backup. Reading happens
    /// while holding the (serialized) writer connection, so no write can
    /// land mid-copy and produce a torn file. Requires the app to be
    /// unlocked — which is correct, since exporting a backup is a
    /// deliberate user action behind the biometric gate anyway.
    public func readDatabaseFileSnapshot() throws -> Data {
        let queue = try dbQueue()
        let url = databaseURL
        return try queue.writeWithoutTransaction { _ in
            try Data(contentsOf: url)
        }
    }

    // MARK: - Connection

    /// Must be called with stateLock held.
    private func openConnection() throws -> DatabaseQueue {
        guard let keyProvider else {
            throw DatabaseManagerError.notConfigured
        }
        let keyData = try keyProvider.fetchDatabaseKey() // May trigger Face ID via Keychain access control.

        var config = Configuration()
        config.prepareDatabase { db in
            // GRDB's SQLCipher integration: the passphrase IS the raw key
            // bytes, hex-encoded and passed with the x'..' raw-key syntax —
            // not a human password run through SQLCipher's own KDF. Using
            // the raw-key form skips PBKDF2 inside SQLCipher, which is
            // correct here because the key is already 256 bits of
            // SecRandomCopyBytes output; stretching adds nothing.
            let hexKey = keyData.map { String(format: "%02x", $0) }.joined()
            try db.execute(sql: "PRAGMA key = \"x'\(hexKey)'\"")
            // Defense in depth: never write plaintext page copies during
            // VACUUM or journaling outside the encrypted file.
            try db.execute(sql: "PRAGMA cipher_memory_security = ON")
        }

        // Ensure Application Support exists — it is NOT created for us on a
        // fresh install, and DatabaseQueue would fail to create the file.
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let queue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try Self.runMigrations(on: queue)
        _dbQueue = queue
        return queue
    }

    // MARK: - Schema

    /// The full ERD from blueprint Section 5, one migration. Tables are
    /// created in dependency order so foreign key references always point
    /// at a table that already exists. All money/percentage fields are
    /// TEXT columns holding exact Decimal strings (GRDB's Decimal
    /// conformance reads/writes POSIX-locale text) — never REAL, per the
    /// blueprint's no-binary-floating-point money rule.
    ///
    /// Lint exception: a schema migration is inherently one linear block
    /// per table — carving it into helpers would scatter the schema across
    /// functions and make it harder to diff against the ERD, not easier.
    // swiftlint:disable:next function_body_length
    static func runMigrations(on queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "account") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("balance", .text).notNull()
            }

            try db.create(table: "category") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("bucket", .text).notNull()
                t.column("parentCategoryId", .integer).references("category")
            }

            // Created before "transaction" because transactions reference it.
            try db.create(table: "recurringSeries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("merchantPattern", .text).notNull()
                t.column("categoryId", .integer).notNull().references("category")
                t.column("intervalDays", .integer).notNull()
                t.column("expectedAmount", .text).notNull()
                t.column("confidence", .text).notNull()
            }

            try db.create(table: "transaction") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer).notNull().references("account")
                t.column("categoryId", .integer).notNull().references("category")
                t.column("recurringSeriesId", .integer).references("recurringSeries")
                t.column("amount", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("merchant", .text)
                t.column("source", .text).notNull()
            }
            // Index on (categoryId, date): every monthly-summary aggregate
            // and every recurring-detection query filters on exactly this
            // pair, so this single index is what keeps those queries
            // O(log n) instead of a full table scan as history grows
            // across years.
            try db.create(
                index: "idx_transaction_category_date",
                on: "transaction",
                columns: ["categoryId", "date"]
            )
            // SQLite does not auto-index foreign keys; these keep account
            // deletion checks and series lookups from scanning the whole
            // transaction table.
            try db.create(index: "idx_transaction_account", on: "transaction", columns: ["accountId"])
            try db.create(index: "idx_transaction_series", on: "transaction", columns: ["recurringSeriesId"])

            try db.create(table: "categoryAllocation") { t in
                t.autoIncrementedPrimaryKey("id")
                // Unique: at most one allocation row per category — the
                // "must total exactly 100%" rule (Phase 3) is only coherent
                // if a category can't be counted twice.
                t.column("categoryId", .integer).notNull().unique().references("category")
                t.column("percentage", .text).notNull()
            }

            try db.create(table: "income") { t in
                // Singleton row, fixed id = 1 (single current salary, no
                // history — a deliberate blueprint decision).
                t.column("id", .integer).primaryKey()
                t.column("amount", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "goal") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("targetAmount", .text).notNull()
                t.column("targetDate", .datetime).notNull()
                t.column("cutScope", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "wishlistItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("price", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "debt") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("principal", .text).notNull()
                t.column("interestRate", .text).notNull()
                t.column("termMonths", .integer).notNull()
                t.column("startDate", .datetime).notNull()
            }

            try db.create(table: "sinkingFund") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("targetAmount", .text).notNull()
                t.column("targetDate", .datetime).notNull()
                t.column("currentAmount", .text).notNull()
                t.column("categoryId", .integer).references("category")
            }

            try db.create(table: "holding") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ticker", .text).notNull()
                t.column("assetClass", .text).notNull()
                t.column("currency", .text).notNull()
            }

            try db.create(table: "costBasisLot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("holdingId", .integer).notNull().references("holding")
                t.column("quantity", .text).notNull()
                t.column("purchasePrice", .text).notNull()
                t.column("purchaseDate", .datetime).notNull()
            }

            try db.create(table: "netWorthSnapshot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .datetime).notNull()
                t.column("totalAssets", .text).notNull()
                t.column("totalLiabilities", .text).notNull()
                t.column("netWorth", .text).notNull()
            }
        }

        // v2 — Phase 3's multi-currency conversion decision. Separate
        // migration: v1 already shipped to a real device; migrations are
        // append-only, never edited retroactively.
        migrator.registerMigration("v2_fx_rates") { db in
            try db.create(table: "fxRate") { t in
                t.column("currencyCode", .text).primaryKey()
                t.column("rateToEGP", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // v3 — Phase 5 investments: locally cached per-ticker price so the
        // portfolio renders offline; refreshed only by explicit user
        // action (manual entry, or the opt-in narrow price fetch).
        migrator.registerMigration("v3_holding_price_cache") { db in
            try db.alter(table: "holding") { t in
                t.add(column: "currentPrice", .text)
                t.add(column: "priceUpdatedAt", .datetime)
            }
        }

        // v4 — transaction direction (InstaPay in/out). Existing rows are
        // all spending, hence the 'expense' default.
        migrator.registerMigration("v4_transaction_direction") { db in
            try db.alter(table: "transaction") { t in
                t.add(column: "direction", .text).notNull().defaults(to: "expense")
            }
        }

        // v5 — receipt line items: per-item prices from scanned receipts,
        // enabling price-per-item history across supermarkets.
        migrator.registerMigration("v5_receipt_items") { db in
            try db.create(table: "receiptItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transactionId", .integer).notNull().references("transaction", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("price", .text).notNull()
            }
            try db.create(index: "idx_receiptItem_transaction", on: "receiptItem", columns: ["transactionId"])
        }

        // v6 — installment plans (ValU/Halan-style financed purchases).
        // Additive (new table only), so existing device data is untouched.
        migrator.registerMigration("v6_installment_plans") { db in
            try db.create(table: "installmentPlan") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("providerName", .text)
                t.column("monthlyAmount", .text).notNull()
                t.column("totalInstallments", .integer).notNull()
                t.column("paidCount", .integer).notNull().defaults(to: 0)
                t.column("startDate", .datetime).notNull()
                t.column("currency", .text).notNull().defaults(to: "EGP")
            }
        }

        // v7 — card last-4 on accounts, for SMS→account routing.
        // Additive (nullable column), so existing device data is untouched.
        migrator.registerMigration("v7_account_last4") { db in
            try db.alter(table: "account") { t in
                t.add(column: "last4", .text)
            }
        }

        // v8 — bank certificates (شهادة): recurring monthly interest income
        // with a maturity date. Additive (new table only).
        migrator.registerMigration("v8_certificates") { db in
            try db.create(table: "certificate") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("bankName", .text)
                t.column("principal", .text).notNull()
                t.column("monthlyInterest", .text).notNull()
                t.column("startDate", .datetime).notNull()
                t.column("maturityDate", .datetime).notNull()
                t.column("accountId", .integer).references("account", onDelete: .setNull)
                t.column("currency", .text).notNull().defaults(to: "EGP")
                t.column("lastLoggedMonth", .datetime)
            }
        }

        try migrator.migrate(queue)
    }
}

public enum DatabaseManagerError: Error, LocalizedError {
    /// dbQueue() was called before configure(keyProvider:) — a programmer
    /// error in wiring, surfaced loudly instead of silently opening an
    /// unencrypted database.
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "DatabaseManager was used before a key provider was configured."
        }
    }
}

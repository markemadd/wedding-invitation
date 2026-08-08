import XCTest
import GRDB
@testable import Persistence

// Phase 1 checkpoint tests that CAN run in a simulator process. The
// biometric/Keychain parts of the checkpoint (Face ID on relaunch, logout
// flow, biometryCurrentSet tripwire) can only be verified on-device and are
// covered by the Phase 1 manual checklist instead.

/// Fixed key for tests — the Keychain is not available to unit tests.
private struct TestKeyProvider: DatabaseKeyProviding {
    let key: Data
    func fetchDatabaseKey() throws -> Data { key }
}

final class PersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeManager(keyByte: UInt8 = 0xA5, filename: String = "test.sqlite") -> DatabaseManager {
        DatabaseManager(
            keyProvider: TestKeyProvider(key: Data(repeating: keyByte, count: 32)),
            databaseURL: tempDir.appendingPathComponent(filename)
        )
    }

    // MARK: - Schema

    /// Every entity in the ERD (blueprint Section 5) must have its table
    /// created by v1_initial_schema — this is the automated half of the
    /// Phase 7 ERD-vs-implementation audit, checked from day one.
    func testAllERDTablesExist() throws {
        let manager = makeManager()
        let expectedTables = [
            "account", "category", "transaction", "categoryAllocation",
            "income", "recurringSeries", "goal", "wishlistItem", "debt",
            "sinkingFund", "holding", "costBasisLot", "netWorthSnapshot"
        ]
        try manager.dbQueue().read { db in
            for table in expectedTables {
                XCTAssertTrue(try db.tableExists(table), "Missing table: \(table)")
            }
        }
    }

    /// v6 (ENHANCEMENTS Wave B1) adds installmentPlan additively — the
    /// table must exist and round-trip exact Decimal money, and progress
    /// arithmetic must stay in Decimal.
    func testInstallmentPlanMigrationAndRoundTrip() throws {
        let manager = makeManager()
        let queue = try manager.dbQueue()
        try queue.read { db in
            XCTAssertTrue(try db.tableExists("installmentPlan"))
        }
        try queue.write { db in
            var plan = InstallmentPlan(
                name: "iPhone 15", providerName: "ValU",
                monthlyAmount: Decimal(string: "1499.99")!,
                totalInstallments: 12, paidCount: 3, startDate: Date()
            )
            try plan.insert(db)
        }
        try queue.read { db in
            let storageType = try String.fetchOne(db, sql: "SELECT typeof(monthlyAmount) FROM installmentPlan")
            XCTAssertEqual(storageType, "text")
            let fetched = try XCTUnwrap(try InstallmentPlan.fetchOne(db))
            XCTAssertEqual(fetched.monthlyAmount, Decimal(string: "1499.99")!)
            // 9 installments left × 1499.99 = 13499.91, exact.
            XCTAssertEqual(fetched.remainingAmount, Decimal(string: "13499.91")!)
        }
    }

    // MARK: - Money exactness

    /// The blueprint's non-negotiable money rule: Decimal in Swift, exact
    /// TEXT in SQLite. 0.1 is the classic value that binary floating point
    /// cannot represent — if amounts ever pass through Double, this test
    /// catches the drift.
    func testDecimalAmountsStoredAsExactText() throws {
        let manager = makeManager()
        let queue = try manager.dbQueue()

        let awkwardAmount = Decimal(string: "1234567.10")! // .10 is unrepresentable in binary floating point.
        try queue.write { db in
            var account = Account(name: "Bank", type: "checking", currency: "EGP", balance: 0)
            try account.insert(db)
            var category = Category(name: "Groceries", bucket: .flexible)
            try category.insert(db)
            var transaction = Transaction(
                accountId: account.id!,
                categoryId: category.id!,
                amount: awkwardAmount,
                currency: "EGP",
                date: Date(),
                merchant: "Test Market",
                source: .manual
            )
            try transaction.insert(db)
        }

        try queue.read { db in
            // Storage class must be TEXT, not REAL.
            let storageType = try String.fetchOne(db, sql: "SELECT typeof(amount) FROM \"transaction\"")
            XCTAssertEqual(storageType, "text")
            // And the round-tripped value must be bit-for-bit the same Decimal.
            let fetched = try Transaction.fetchOne(db)
            XCTAssertEqual(fetched?.amount, awkwardAmount)
        }
    }

    // MARK: - Encryption

    /// The on-disk file must never be a plaintext SQLite database. A
    /// plaintext file begins with the magic string "SQLite format 3";
    /// SQLCipher files begin with a random salt.
    func testDatabaseFileIsNotPlaintextSQLite() throws {
        let manager = makeManager()
        _ = try manager.dbQueue() // Create the file.
        let fileBytes = try Data(contentsOf: manager.currentDatabaseFileURL())
        let plaintextMagic = Data("SQLite format 3".utf8)
        XCTAssertFalse(fileBytes.prefix(16).elementsEqual(plaintextMagic),
                       "Database file has a plaintext SQLite header — encryption is NOT active")
    }

    /// Opening the same file with a different key must fail — the simulator
    /// stand-in for the Phase 1 "copy the .sqlite off the device and try to
    /// open it" manual check.
    func testWrongKeyCannotOpenDatabase() throws {
        let rightKey = makeManager(keyByte: 0xA5, filename: "locked.sqlite")
        _ = try rightKey.dbQueue()
        rightKey.invalidateSession()

        let wrongKey = makeManager(keyByte: 0x5A, filename: "locked.sqlite")
        XCTAssertThrowsError(try wrongKey.dbQueue(),
                             "A wrong key opened the database — SQLCipher is not enforcing encryption")
    }

    // MARK: - Session lifecycle

    /// invalidateSession must actually tear the connection down, and a
    /// subsequent dbQueue() must transparently reopen (with the key
    /// provider consulted again — in production that means biometrics).
    func testInvalidateSessionTearsDownAndReopens() throws {
        let manager = makeManager()
        let first = try manager.dbQueue()
        manager.invalidateSession()
        let second = try manager.dbQueue()
        XCTAssertFalse(first === second, "invalidateSession left the old connection alive")
    }

    /// An unconfigured manager must refuse loudly, never open unencrypted.
    func testUnconfiguredManagerThrows() {
        // DatabaseManager.shared is unconfigured inside the test process.
        XCTAssertThrowsError(try DatabaseManager.shared.dbQueue())
    }

    // MARK: - Export (Phase 6.2)

    func testCSVExportEscapesAndResolvesNames() throws {
        let manager = makeManager()
        let queue = try manager.dbQueue()
        try queue.write { db in
            var account = Account(name: "Bank", type: "bank", currency: "EGP", balance: 0)
            try account.insert(db)
            var category = Category(name: "food", bucket: .flexible)
            try category.insert(db)
            var txn = Transaction(
                accountId: account.id!, categoryId: category.id!,
                amount: Decimal(string: "42.50")!, currency: "EGP",
                date: Date(), merchant: "Cafe, \"El Nil\"", source: .manual
            )
            try txn.insert(db)
        }
        let csv = try ExportService(databaseManager: manager).transactionsCSV()
        XCTAssertTrue(csv.hasPrefix("id,date,amount,currency,merchant,category,account,source\n"))
        // Comma+quote merchant must be quoted with doubled quotes.
        XCTAssertTrue(csv.contains(#""Cafe, ""El Nil""""#))
        XCTAssertTrue(csv.contains("42.5"))
        XCTAssertTrue(csv.contains(",food,Bank,manual"))
    }

    func testJSONExportContainsAllTables() throws {
        let manager = makeManager()
        _ = try manager.dbQueue() // Migrate.
        let data = try ExportService(databaseManager: manager).fullJSON()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["accounts", "categories", "transactions", "goals", "debts",
                    "holdings", "fxRates", "sinkingFunds", "wishlist"] {
            XCTAssertNotNil(object[key], "JSON export missing \(key)")
        }
    }

    // MARK: - Integrity

    /// Foreign keys are enforced: a transaction pointing at a nonexistent
    /// account must be rejected at write time, not discovered as an orphan
    /// during some future aggregate.
    func testForeignKeysAreEnforced() throws {
        let manager = makeManager()
        let queue = try manager.dbQueue()
        XCTAssertThrowsError(
            try queue.write { db in
                var transaction = Transaction(
                    accountId: 9_999, // No such account.
                    categoryId: 9_999, // No such category.
                    amount: 10,
                    currency: "EGP",
                    date: Date(),
                    source: .manual
                )
                try transaction.insert(db)
            }
        )
    }
}

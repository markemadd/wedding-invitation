import XCTest
import GRDB
import Persistence
@testable import Budgeting

private struct TestKeyProvider: DatabaseKeyProviding {
    func fetchDatabaseKey() throws -> Data { Data(repeating: 0x33, count: 32) }
}

// Phase 3 checkpoint: "manually verify the dashboard's allocated/spent/
// remaining numbers match your own calculation exactly." The hand
// calculation lives in the comments of testMonthlySummaryMatchesHandMath.
final class BudgetingTests: XCTestCase {
    private var tempDir: URL!
    private var manager: DatabaseManager!
    private var service: SalaryAllocationService!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BudgetingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = DatabaseManager(
            keyProvider: TestKeyProvider(),
            databaseURL: tempDir.appendingPathComponent("budget.sqlite")
        )
        try StarterDataBootstrapper(databaseManager: manager).seedIfNeeded()
        service = SalaryAllocationService(databaseManager: manager)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func categoryId(_ name: String) throws -> Int64 {
        try manager.dbQueue().read { db in
            try XCTUnwrap(
                Persistence.Category.filter(GRDB.Column("name") == name).fetchOne(db)?.id
            )
        }
    }

    private func insertTransaction(category: Int64, amount: String, currency: String = "EGP") throws {
        try manager.dbQueue().write { db in
            let accountId = try StarterDataBootstrapper.defaultAccountId(db)
            var transaction = Persistence.Transaction(
                accountId: accountId,
                categoryId: category,
                amount: Decimal(string: amount)!,
                currency: currency,
                date: Date(),
                merchant: "test",
                source: .manual
            )
            try transaction.insert(db)
        }
    }

    // MARK: - Validation

    func testAllocationsMustSumToExactlyOne() throws {
        let food = try categoryId("food")
        let coffee = try categoryId("coffee")

        // 90% — must be rejected with the shortfall reported.
        XCTAssertThrowsError(try validateAllocations([
            CategoryAllocation(categoryId: food, percentage: Decimal(string: "0.6")!),
            CategoryAllocation(categoryId: coffee, percentage: Decimal(string: "0.3")!)
        ])) { error in
            XCTAssertEqual(error as? AllocationError,
                           .doesNotSumToWhole(currentTotal: Decimal(string: "0.9")!))
        }

        // Exactly 100% — passes. Decimal exactness means 0.7 + 0.3 == 1
        // with no epsilon games.
        XCTAssertNoThrow(try validateAllocations([
            CategoryAllocation(categoryId: food, percentage: Decimal(string: "0.7")!),
            CategoryAllocation(categoryId: coffee, percentage: Decimal(string: "0.3")!)
        ]))
    }

    func testSetAllocationsRefusesInvalidSetBeforeWriting() throws {
        let food = try categoryId("food")
        XCTAssertThrowsError(try service.setAllocations([
            CategoryAllocation(categoryId: food, percentage: Decimal(string: "0.5")!)
        ]))
        // Nothing half-saved:
        XCTAssertTrue(try service.currentAllocations().isEmpty)
    }

    // MARK: - Monthly summary (hand-verified math)

    func testMonthlySummaryMatchesHandMath() throws {
        // Income: 10,000 EGP.
        try service.setIncome(amount: 10_000, currency: "EGP")
        let food = try categoryId("food")
        let supermarket = try categoryId("supermarket")
        let uncategorized = try categoryId("Uncategorized")

        // Allocations: food 30%, supermarket 20%, Uncategorized 50%.
        try service.setAllocations([
            CategoryAllocation(categoryId: food, percentage: Decimal(string: "0.3")!),
            CategoryAllocation(categoryId: supermarket, percentage: Decimal(string: "0.2")!),
            CategoryAllocation(categoryId: uncategorized, percentage: Decimal(string: "0.5")!)
        ])

        // Spending this month:
        //   food: 500 EGP + 10 EUR. Seeded rate: 1 EUR = 55 EGP,
        //         so food spent = 500 + 550 = 1,050 EGP.
        //   supermarket: 300.25 EGP.
        try insertTransaction(category: food, amount: "500")
        try insertTransaction(category: food, amount: "10", currency: "EUR")
        try insertTransaction(category: supermarket, amount: "300.25")

        let summary = try service.monthlySummary(for: Date())
        let byName = Dictionary(uniqueKeysWithValues: summary.map { ($0.category.name, $0) })

        // Hand math: allocated = income × percentage.
        //   food:        allocated 3,000, spent 1,050, remaining 1,950
        //   supermarket: allocated 2,000, spent 300.25, remaining 1,699.75
        //   Uncategorized: allocated 5,000, spent 0, remaining 5,000
        XCTAssertEqual(byName["food"]?.allocated, 3_000)
        XCTAssertEqual(byName["food"]?.spent, Decimal(string: "1050"))
        XCTAssertEqual(byName["food"]?.remaining, Decimal(string: "1950"))
        XCTAssertEqual(byName["supermarket"]?.allocated, 2_000)
        XCTAssertEqual(byName["supermarket"]?.spent, Decimal(string: "300.25"))
        XCTAssertEqual(byName["supermarket"]?.remaining, Decimal(string: "1699.75"))
        XCTAssertEqual(byName["Uncategorized"]?.spent, 0)

        // Total spent = 1,050 + 300.25 = 1,350.25 EGP.
        XCTAssertEqual(try service.totalSpent(for: Date()), Decimal(string: "1350.25"))
    }

    func testInstaPayInAndOutNetAgainstEachOther() throws {
        try service.setIncome(amount: 10_000, currency: "EGP")
        let instapay = try categoryId("instapay")
        try service.setAllocations([
            CategoryAllocation(categoryId: instapay, percentage: Decimal(1))
        ])
        // Send 800, receive 500 — net spending in the category is 300,
        // and monthly total spending reflects the same netting ("received
        // money increases the allowance").
        try insertTransaction(category: instapay, amount: "800")
        try manager.dbQueue().write { db in
            let accountId = try StarterDataBootstrapper.defaultAccountId(db)
            var txn = Persistence.Transaction(
                accountId: accountId, categoryId: instapay,
                amount: Decimal(500), currency: "EGP", date: Date(),
                merchant: "InstaPay: Ahmed", source: .sms, direction: .income
            )
            try txn.insert(db)
        }
        let summary = try service.monthlySummary(for: Date())
        XCTAssertEqual(summary.first { $0.category.name == "instapay" }?.spent, 300)
        XCTAssertEqual(try service.totalSpent(for: Date()), 300)
    }

    func testSpendInUnallocatedCategoryStillCountsInTotal() throws {
        try service.setIncome(amount: 10_000, currency: "EGP")
        let cinema = try categoryId("cinema") // Deliberately NOT allocated.
        try insertTransaction(category: cinema, amount: "120")
        XCTAssertEqual(try service.totalSpent(for: Date()), 120)
    }

    // MARK: - Monthly story

    func testStoryContainsHeadlineBiggestExpenseAndSavings() throws {
        try service.setIncome(amount: 10_000, currency: "EGP")
        let food = try categoryId("food")
        try insertTransaction(category: food, amount: "2500")
        try insertTransaction(category: food, amount: "500")

        let lines = try MonthlyStoryService(databaseManager: manager).story()
        XCTAssertFalse(lines.isEmpty)
        // Headline totals the month (amounts are grouped for readability).
        XCTAssertTrue(lines[0].contains("3,000"), "headline: \(lines[0])")
        // Biggest single expense line names the amount.
        XCTAssertTrue(lines.contains { $0.contains("Biggest single expense") && $0.contains("2,500") })
        // Savings line: kept 7,000 of 10,000 (70%).
        XCTAssertTrue(lines.contains { $0.contains("7,000") && $0.contains("70") })
    }

    // MARK: - Converter

    func testMissingRateFallsBackToFaceValue() {
        let converter = CurrencyConverter(rates: ["EUR": 55])
        XCTAssertEqual(converter.toEGP(10, from: "EUR"), 550)
        XCTAssertEqual(converter.toEGP(10, from: "XXX"), 10) // Unknown code: face value, surfaced by UI.
        XCTAssertFalse(converter.hasRate(for: "XXX"))
    }
}

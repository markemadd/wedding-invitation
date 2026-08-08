import XCTest
import GRDB
import Persistence
import Budgeting
@testable import SavingsAndGoals

private struct TestKeyProvider: DatabaseKeyProviding {
    func fetchDatabaseKey() throws -> Data { Data(repeating: 0x77, count: 32) }
}

// Phase 4 checkpoint tests, exactly as the blueprint specifies them:
// synthetic recurring set detected; cut suggestions sum to the gap;
// amortization's final balance is zero (within a cent of Decimal rounding).
final class SavingsAndGoalsTests: XCTestCase {
    private var tempDir: URL!
    private var manager: DatabaseManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SGTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = DatabaseManager(
            keyProvider: TestKeyProvider(),
            databaseURL: tempDir.appendingPathComponent("sg.sqlite")
        )
        try StarterDataBootstrapper(databaseManager: manager).seedIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func insert(merchant: String, amount: String, daysAgo: Int, category: String = "Subscriptions") throws {
        try manager.dbQueue().write { db in
            let accountId = try StarterDataBootstrapper.defaultAccountId(db)
            let categoryId = try Persistence.Category.filter(GRDB.Column("name") == category).fetchOne(db)?.id
                ?? StarterDataBootstrapper.uncategorizedCategoryId(db)
            var txn = Persistence.Transaction(
                accountId: accountId,
                categoryId: categoryId,
                amount: Decimal(string: amount)!,
                currency: "EGP",
                date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                merchant: merchant,
                source: .manual
            )
            try txn.insert(db)
        }
    }

    // MARK: - Recurring detection (blueprint checkpoint)

    func testMonthlyPatternIsDetected() throws {
        // Same merchant, same amount, 30-day gaps — textbook subscription.
        for daysAgo in [90, 60, 30, 0] {
            try insert(merchant: "Netflix", amount: "200", daysAgo: daysAgo, category: "Uncategorized")
        }
        // Noise that must NOT be detected: two visits, wild amounts.
        try insert(merchant: "Random Cafe", amount: "75", daysAgo: 40, category: "Uncategorized")
        try insert(merchant: "Random Cafe", amount: "310", daysAgo: 5, category: "Uncategorized")

        let candidates = try RecurringDetectionService(databaseManager: manager).detectRecurringSeries()
        XCTAssertEqual(candidates.count, 1)
        let netflix = try XCTUnwrap(candidates.first)
        XCTAssertEqual(netflix.merchant, "Netflix")
        XCTAssertEqual(netflix.intervalDays, 30)
        XCTAssertEqual(netflix.expectedAmount, 200)
        XCTAssertGreaterThan(netflix.confidence, Decimal(string: "0.9")!) // Perfect gaps → near-1 confidence.
    }

    func testConfirmLinksTransactionsAndStopsRedetection() throws {
        for daysAgo in [60, 30, 0] {
            try insert(merchant: "Gym Club", amount: "500", daysAgo: daysAgo, category: "sports")
        }
        let service = RecurringDetectionService(databaseManager: manager)
        let candidate = try XCTUnwrap(try service.detectRecurringSeries().first)
        try service.confirm(candidate)

        // Back-linked:
        let linked = try manager.dbQueue().read { db in
            try Persistence.Transaction.filter(GRDB.Column("recurringSeriesId") != nil).fetchCount(db)
        }
        XCTAssertEqual(linked, 3)
        // And no longer offered as a candidate:
        XCTAssertTrue(try service.detectRecurringSeries().isEmpty)
    }

    // MARK: - Goal cut suggestions (blueprint checkpoint)

    func testCutSuggestionsSumExactlyToGap() throws {
        let allocation = SalaryAllocationService(databaseManager: manager)
        try allocation.setIncome(amount: 10_000, currency: "EGP")
        // Spend 3,000 this month across flexible categories → savings 7,000.
        try insert(merchant: "a", amount: "2000", daysAgo: 0, category: "food")
        try insert(merchant: "b", amount: "1000", daysAgo: 0, category: "coffee")

        // Goal: 120,000 in 12 months → 10,000/month needed.
        // Average savings ≈ 7,000 (this month) but the 3-month trailing
        // window includes two empty months at 10,000 savings each:
        // (7,000 + 10,000 + 10,000) / 3 = 9,000 → gap = 1,000.
        let goal = Goal(
            name: "Car",
            targetAmount: 120_000,
            targetDate: Calendar.current.date(byAdding: .month, value: 12, to: Date())!,
            cutScope: .flexibleOnly,
            createdAt: Date()
        )
        let plan = try SavingsAndGoalsService(databaseManager: manager).evaluateGoal(goal)

        XCTAssertEqual(plan.requiredMonthlySavings, 10_000)
        XCTAssertEqual(plan.monthlyGap, 1_000)
        // The blueprint checkpoint: suggestions sum to exactly the gap.
        let suggestionTotal = plan.suggestedCuts.reduce(Decimal(0)) { $0 + $1.suggestedReduction }
        XCTAssertEqual(suggestionTotal, plan.monthlyGap)
        // Proportional by spend: food (2/3 of eligible spending) carries
        // the biggest cut. Its share is APPROXIMATELY 2/3 of the gap —
        // exactly proportional up to the remainder it deliberately absorbs
        // so that the total stays exact (2000/3000 is a repeating fraction).
        XCTAssertEqual(plan.suggestedCuts.first?.category.name, "food")
        let foodCut = try XCTUnwrap(plan.suggestedCuts.first?.suggestedReduction)
        let idealFoodCut = plan.monthlyGap * 2 / 3
        XCTAssertLessThan(abs(foodCut - idealFoodCut), Decimal(string: "0.0001")!)
    }

    // MARK: - Amortization (blueprint checkpoint)

    func testScheduleEndsAtZeroWithinACent() {
        let calc = AmortizationCalculator()
        let schedule = calc.fullSchedule(principal: 100_000, annualRate: 21.5, termMonths: 36)
        XCTAssertEqual(schedule.count, 36)
        let finalBalance = schedule.last!.remainingBalance
        XCTAssertLessThan(abs(finalBalance), Decimal(string: "0.01")!,
                          "Final balance must be zero within a cent of Decimal rounding")
        // Sanity: payment for 100k @ 21.5%/36mo is ~3,800 EGP.
        let payment = calc.monthlyPayment(principal: 100_000, annualRate: 21.5, termMonths: 36)
        XCTAssertGreaterThan(payment, 3_700)
        XCTAssertLessThan(payment, 3_900)
    }

    func testZeroInterestSplitsEvenly() {
        let payment = AmortizationCalculator().monthlyPayment(principal: 1_200, annualRate: 0, termMonths: 12)
        XCTAssertEqual(payment, 100)
    }

    // MARK: - Price creep

    func testPriceCreepDetectedAndAcceptClears() throws {
        // Agreed price 200; latest charge 230 = +15% — alert. 204 (+2%)
        // stays inside the ±5% billing-noise band — no alert.
        let categoryId = try manager.dbQueue().read { db in
            try Persistence.Category.fetchAll(db).first!.id!
        }
        let accountId = try manager.dbQueue().read { db in try StarterDataBootstrapper.defaultAccountId(db) }
        let seriesId: Int64 = try manager.dbQueue().write { db in
            var series = RecurringSeries(merchantPattern: "Netflix", categoryId: categoryId,
                                         intervalDays: 30, expectedAmount: 200, confidence: 1)
            try series.insert(db)
            return series.id!
        }
        try manager.dbQueue().write { db in
            var txn = Persistence.Transaction(
                accountId: accountId, categoryId: categoryId, recurringSeriesId: seriesId,
                amount: 230, currency: "EGP", date: Date(), merchant: "Netflix", source: .sms
            )
            try txn.insert(db)
        }
        let service = PriceCreepService(databaseManager: manager)
        let alerts = try service.creepAlerts()
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.latestAmount, 230)
        XCTAssertEqual(alerts.first?.increasePercent, 15)

        // Accept → baseline moves → alert clears.
        try service.acceptNewPrice(seriesId: seriesId, newAmount: 230)
        XCTAssertTrue(try service.creepAlerts().isEmpty)
    }

    // MARK: - Anomaly & duplicates

    func testOutlierIsFlaggedAndNormalIsNot() throws {
        for i in 1...6 {
            try insert(merchant: "coffee shop", amount: "5\(i)", daysAgo: i * 3, category: "coffee") // 51…56
        }
        let coffeeId = try manager.dbQueue().read { db in
            try Persistence.Category.filter(GRDB.Column("name") == "coffee").fetchOne(db)!.id!
        }
        let accountId = try manager.dbQueue().read { db in try StarterDataBootstrapper.defaultAccountId(db) }
        let service = AnomalyDetectionService(databaseManager: manager)

        let outlier = Persistence.Transaction(
            accountId: accountId, categoryId: coffeeId, amount: 5_000,
            currency: "EGP", date: Date(), merchant: "coffee shop", source: .manual
        )
        XCTAssertTrue(try service.check(outlier).isAmountAnomalous)

        let normal = Persistence.Transaction(
            accountId: accountId, categoryId: coffeeId, amount: 54,
            currency: "EGP", date: Date(), merchant: "coffee shop", source: .manual
        )
        XCTAssertFalse(try service.check(normal).isAmountAnomalous)
    }

    func testDuplicateWithinWindowIsFlagged() throws {
        try insert(merchant: "KFC", amount: "250", daysAgo: 0, category: "food")
        let accountId = try manager.dbQueue().read { db in try StarterDataBootstrapper.defaultAccountId(db) }
        let foodId = try manager.dbQueue().read { db in
            try Persistence.Category.filter(GRDB.Column("name") == "food").fetchOne(db)!.id!
        }
        let dupe = Persistence.Transaction(
            accountId: accountId, categoryId: foodId, amount: 250,
            currency: "EGP", date: Date(), merchant: "KFC", source: .walletIntent
        )
        XCTAssertNotNil(try AnomalyDetectionService(databaseManager: manager).check(dupe).likelyDuplicateOf)
    }

    // MARK: - Sinking funds

    func testRequiredMonthlyContribution() throws {
        let service = SinkingFundService(databaseManager: manager)
        try service.create(
            name: "Car service",
            targetAmount: 6_000,
            targetDate: Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
            categoryId: nil
        )
        var fund = try XCTUnwrap(try service.allFunds().first)
        XCTAssertEqual(service.requiredMonthlyContribution(fund), 1_000)
        try service.contribute(1_500, to: fund.id!)
        fund = try XCTUnwrap(try service.allFunds().first)
        XCTAssertEqual(fund.currentAmount, 1_500)
    }
}

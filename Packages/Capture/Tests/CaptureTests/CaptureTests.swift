import XCTest
import GRDB
import Persistence
@testable import Capture

private struct TestKeyProvider: DatabaseKeyProviding {
    func fetchDatabaseKey() throws -> Data { Data(repeating: 0x42, count: 32) }
}

final class CaptureTests: XCTestCase {
    private var tempDir: URL!
    private var manager: DatabaseManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = DatabaseManager(
            keyProvider: TestKeyProvider(),
            databaseURL: tempDir.appendingPathComponent("capture.sqlite")
        )
        try StarterDataBootstrapper(databaseManager: manager).seedIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func firstIds() throws -> (accountId: Int64, categoryId: Int64) {
        try manager.dbQueue().read { db in
            (
                try StarterDataBootstrapper.defaultAccountId(db),
                try StarterDataBootstrapper.uncategorizedCategoryId(db)
            )
        }
    }

    // MARK: - TransactionWriter (the single funnel)

    func testValidDraftLandsWithCorrectSourceAndPrecision() throws {
        let (accountId, categoryId) = try firstIds()
        let writer = TransactionWriter(databaseManager: manager)
        let amount = Decimal(string: "49.99")!

        let inserted = try writer.insert(TransactionDraft(
            accountId: accountId,
            categoryId: categoryId,
            amount: amount,
            merchant: "Test Cafe",
            source: .voice
        ))

        let fetched = try manager.dbQueue().read { db in
            try Persistence.Transaction.fetchOne(db, id: inserted.id!)
        }
        XCTAssertEqual(fetched?.amount, amount) // Exact Decimal, no Double drift.
        XCTAssertEqual(fetched?.source, .voice) // Source tag preserved — the Phase 2 checkpoint criterion.
        XCTAssertEqual(fetched?.accountId, accountId)
    }

    func testInsertPairIsAtomicWhenSecondLegFails() throws {
        let (accountId, categoryId) = try firstIds()
        let writer = TransactionWriter(databaseManager: manager)
        let (countBefore, balanceBefore) = try manager.dbQueue().read { db in
            (try Persistence.Transaction.fetchCount(db),
             try Account.fetchOne(db, id: accountId)?.balance)
        }

        // First leg is valid; second targets a nonexistent account. The
        // transfer must roll back as a unit — no orphaned debit.
        XCTAssertThrowsError(try writer.insertPair(
            TransactionDraft(accountId: accountId, categoryId: categoryId,
                             amount: Decimal(string: "100")!, merchant: "Transfer out", source: .manual,
                             direction: .expense),
            TransactionDraft(accountId: 999_999, categoryId: categoryId,
                             amount: Decimal(string: "100")!, merchant: "Transfer in", source: .manual,
                             direction: .income)
        )) { error in
            XCTAssertEqual(error as? TransactionWriteError, .unknownAccount(999_999))
        }

        let (countAfter, balanceAfter) = try manager.dbQueue().read { db in
            (try Persistence.Transaction.fetchCount(db),
             try Account.fetchOne(db, id: accountId)?.balance)
        }
        XCTAssertEqual(countAfter, countBefore)     // Neither leg persisted.
        XCTAssertEqual(balanceAfter, balanceBefore) // Source balance untouched.
    }

    func testNonPositiveAmountsAreRejected() throws {
        let (accountId, categoryId) = try firstIds()
        let writer = TransactionWriter(databaseManager: manager)
        for bad in [Decimal(0), Decimal(-10)] {
            XCTAssertThrowsError(try writer.insert(TransactionDraft(
                accountId: accountId, categoryId: categoryId, amount: bad, source: .manual
            )))
        }
    }

    func testUnknownForeignKeysAreRejected() throws {
        let (accountId, categoryId) = try firstIds()
        let writer = TransactionWriter(databaseManager: manager)
        XCTAssertThrowsError(try writer.insert(TransactionDraft(
            accountId: 99_999, categoryId: categoryId, amount: 10, source: .manual
        ))) { error in
            XCTAssertEqual(error as? TransactionWriteError, .unknownAccount(99_999))
        }
        XCTAssertThrowsError(try writer.insert(TransactionDraft(
            accountId: accountId, categoryId: 99_999, amount: 10, source: .manual
        ))) { error in
            XCTAssertEqual(error as? TransactionWriteError, .unknownCategory(99_999))
        }
    }

    // MARK: - Starter data

    func testStarterSeedIsIdempotent() throws {
        try StarterDataBootstrapper(databaseManager: manager).seedIfNeeded() // Second run.
        let accountCount = try manager.dbQueue().read { try Account.fetchCount($0) }
        XCTAssertEqual(accountCount, 2, "Seeding twice must not duplicate starter data")
    }

    // MARK: - OCR heuristics (string-level, no Vision needed)

    func testTotalKeywordBeatsCashTendered() {
        // Cash tendered (50.00) is the biggest number on the receipt but
        // NOT the total — the tender-keyword exclusion plus total-keyword
        // priority must pick 21.25. (This was a documented limitation of
        // the first-pass heuristic; fixed during tuning against the real
        // Mercadona receipt, which had exactly this shape.)
        let lines = ["Cola 12.50", "Bread 8.75", "TOTAL 21.25", "Cash 50.00"]
        let amount = ReceiptOCRService().extractCandidates(fromLines: lines).amount
        XCTAssertEqual(amount, Decimal(string: "21.25"))
    }

    func testTaxRatePercentagesAreIgnored() {
        // "10.00%" is a rate, not money — from the real Five Guys receipt
        // where it beat the 6.50 total before the % exclusion.
        let lines = ["10.00% Subtotal", "Restaurant Total 6.50"]
        let amount = ReceiptOCRService().extractCandidates(fromLines: lines).amount
        XCTAssertEqual(amount, Decimal(string: "6.50"))
    }

    func testEasternArabicDigitsAreRecognized() {
        let candidates = ReceiptOCRService().extractCandidates(fromLines: ["المجموع ١٢٣٫٤٥"])
        XCTAssertEqual(candidates.amount, Decimal(string: "123.45"))
        XCTAssertEqual(candidates.currency, "EGP", "No currency marker → home-currency default")
    }

    func testMerchantScoringPrefersProminentTopLine() {
        // Simulates real receipt geometry: big merchant name near the top,
        // preceded by a small greeting line — first-line-wins would fail here.
        let lines = [
            OCRLine(text: "Welcome!", normalizedHeight: 0.015, topOffset: 0.02),
            OCRLine(text: "Spinneys Zamalek", normalizedHeight: 0.05, topOffset: 0.08),
            OCRLine(text: "Tel: 0221234567", normalizedHeight: 0.02, topOffset: 0.15),
            OCRLine(text: "Receipt #442", normalizedHeight: 0.02, topOffset: 0.2),
            OCRLine(text: "TOTAL 21.25", normalizedHeight: 0.03, topOffset: 0.8)
        ]
        let candidates = ReceiptOCRService().extractCandidates(fromOCRLines: lines)
        XCTAssertEqual(candidates.merchant, "Spinneys Zamalek")
    }

    func testMerchantSkipsNoiseAndDigitLines() {
        let lines = [
            OCRLine(text: "فاتورة ضريبية", normalizedHeight: 0.03, topOffset: 0.02), // "tax invoice" header
            OCRLine(text: "01001234567", normalizedHeight: 0.03, topOffset: 0.06),
            OCRLine(text: "كارفور مصر", normalizedHeight: 0.03, topOffset: 0.1)
        ]
        let candidates = ReceiptOCRService().extractCandidates(fromOCRLines: lines)
        XCTAssertEqual(candidates.merchant, "كارفور مصر")
    }

    // MARK: - Receipt dates

    func testDayFirstDateIsParsed() throws {
        // A recent, plausible day-first date (Egyptian convention).
        let candidates = ReceiptOCRService().extractCandidates(fromLines: ["Carrefour", "Date: 01/06/2026", "TOTAL 99.99"])
        let parsed = try XCTUnwrap(candidates.date)
        let components = Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: parsed)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.year, 2026)
    }

    func testEasternArabicDateWithKeywordWins() throws {
        // The keyword line (التاريخ) must beat a stray other date.
        let candidates = ReceiptOCRService().extractCandidates(fromLines: [
            "كارفور",
            "رقم العضوية 11/11/2025",
            "التاريخ ٠٢/٠٦/٢٠٢٦"
        ])
        let parsed = try XCTUnwrap(candidates.date)
        let components = Calendar(identifier: .gregorian).dateComponents([.day, .month], from: parsed)
        XCTAssertEqual(components.day, 2)
        XCTAssertEqual(components.month, 6)
    }

    func testImpossibleAndFutureDatesAreRejected() {
        // 31/02 rolls over in a lenient calendar; 2035 is in the future —
        // both must yield nil rather than a wrong "parsed" date.
        let candidates = ReceiptOCRService().extractCandidates(fromLines: ["31/02/2026", "05/07/2035"])
        XCTAssertNil(candidates.date)
    }

    // MARK: - Arabic number words (informal Egyptian)

    func testSimpleTensWord() {
        let parsed = VoiceDraftParser().parse("قهوة خمسين جنيه")
        XCTAssertEqual(parsed.amount, Decimal(50))
        XCTAssertEqual(parsed.merchantHint, "قهوة")
    }

    func testCompoundHundredsWithConjunction() {
        // "مية وخمسة وسبعين" = 175
        let parsed = VoiceDraftParser().parse("سوبر ماركت مية وخمسة وسبعين")
        XCTAssertEqual(parsed.amount, Decimal(175))
    }

    func testThousandsMultiplier() {
        // "تلاتة الاف" = 3000
        let parsed = VoiceDraftParser().parse("ايجار تلاتة الاف جنيه")
        XCTAssertEqual(parsed.amount, Decimal(3_000))
        XCTAssertEqual(parsed.merchantHint, "ايجار")
    }

    func testHalfPoundSuffix() {
        // "عشرة جنيه ونص" = 10.5
        let parsed = VoiceDraftParser().parse("عشرة جنيه ونص")
        XCTAssertEqual(parsed.amount, Decimal(string: "10.5"))
    }

    // MARK: - Voice parsing

    func testVoiceParseWesternDigits() {
        let parsed = VoiceDraftParser().parse("coffee 50.25 at cafe")
        XCTAssertEqual(parsed.amount, Decimal(string: "50.25"))
        XCTAssertEqual(parsed.merchantHint, "coffee at cafe") // Whitespace collapses where the amount was removed.
    }

    func testVoiceParseEasternArabicDigits() {
        let parsed = VoiceDraftParser().parse("قهوة ٥٠ جنيه")
        XCTAssertEqual(parsed.amount, Decimal(50))
    }

    func testVoiceParseWithoutNumberYieldsHintOnly() {
        let parsed = VoiceDraftParser().parse("just some words")
        XCTAssertNil(parsed.amount)
        XCTAssertEqual(parsed.merchantHint, "just some words")
    }

    // MARK: - Bank SMS parsing (post-blueprint, user-requested)

    func testEnglishBankSMSParses() {
        let sms = "Your credit card ending 1234 was charged EGP 350.50 at AMAZON.EG on 05/07/26. Avl balance EGP 12,401.75"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(string: "350.50"))
        XCTAssertEqual(parsed.currency, "EGP")
        XCTAssertEqual(parsed.merchant, "AMAZON.EG")
        XCTAssertTrue(parsed.isDebit)
    }

    func testArabicBankSMSParsesWithEasternDigits() {
        let sms = "تم خصم ٣٥٠٫٥٠ جنيه من بطاقتك في كارفور مصر"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(string: "350.50"))
        XCTAssertEqual(parsed.currency, "EGP")
        XCTAssertTrue(parsed.isDebit)
        XCTAssertEqual(parsed.merchant, "كارفور مصر")
    }

    func testThousandsSeparatorAndForeignCurrency() {
        let parsed = BankSMSParser().parse("Card 5678 used for USD 1,250.00 at BOOKING.COM")
        XCTAssertEqual(parsed.amount, Decimal(string: "1250.00"))
        XCTAssertEqual(parsed.currency, "USD")
    }

    func testIncomingCreditIsFlaggedNotDebit() {
        let parsed = BankSMSParser().parse("Your account was credited with EGP 25,000.00 salary transfer")
        XCTAssertFalse(parsed.isDebit)
        XCTAssertEqual(parsed.amount, Decimal(25_000))
    }

    /// The user's REAL bank SMS, verbatim — the ground truth this parser
    /// is tuned against (mixed Arabic/English, Eastern-digit hotline,
    /// available-balance trap, date+time, merchant after عند).
    func testRealUserBankSMSExtractsEverything() throws {
        let sms = "تم خصم 2856.89 EGP من بطاقة الخصم المباشر رقم 5983 عند Talabat                   يوم 06/07/26 الساعه 12:31 المتاح 12670.32EGP للمزيد إتصل ب ١٩٦٢٣"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(string: "2856.89"), "Must pick the charge, not the 12670.32 balance")
        XCTAssertEqual(parsed.currency, "EGP")
        XCTAssertEqual(parsed.merchant, "Talabat")
        XCTAssertTrue(parsed.isDebit)
        let parts = Calendar(identifier: .gregorian).dateComponents([.day, .month, .year, .hour, .minute], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.day, 6)
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.hour, 12, "Time 12:31 must be read from الساعه, not defaulted")
        XCTAssertEqual(parts.minute, 31)
        XCTAssertEqual(parsed.cardLast4, "5983", "Card no. after رقم")
    }

    // MARK: - SMS time-of-day extraction (the noon-default bug)

    func testEnglishSMSTimeParsedNotDefaulted() throws {
        let parsed = BankSMSParser().parse("Card ending 1234 charged EGP 90 at CAFE on 05/07/26 at 14:05")
        let parts = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.hour, 14)
        XCTAssertEqual(parts.minute, 5)
    }

    func testTwelveHourAmPmTimeParsed() throws {
        let parsed = BankSMSParser().parse("Card ending 1234 charged EGP 90 at SHOP on 05/07/26 at 9:07 PM")
        let parts = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.hour, 21, "9:07 PM → 21:07")
        XCTAssertEqual(parts.minute, 7)
    }

    func testArabicTimeAfterAlSaaParsed() throws {
        let parsed = BankSMSParser().parse("تم خصم 50 جنيه من بطاقة رقم 4321 يوم 05/07/26 الساعة 08:45")
        let parts = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 45)
        XCTAssertEqual(parsed.cardLast4, "4321")
    }

    // MARK: - Card last-4 extraction (for account routing)

    func testCardLast4FromMaskedAndEndingForms() {
        XCTAssertEqual(BankSMSParser().parse("Purchase on card ****7788 EGP 40 at X").cardLast4, "7788")
        XCTAssertEqual(BankSMSParser().parse("Your card ending 1234 was charged EGP 5").cardLast4, "1234")
        XCTAssertEqual(BankSMSParser().parse("تم إضافة تحويل لحسابكم رقم XXXX بمبلغ 300 جم رقم مرجعي 963077936261 يوم 07-04").cardLast4,
                       nil, "A masked XXXX and a long reference number yield no last-4")
    }

    // MARK: - InstaPay transfers (in/out)

    func testInstaPayReceiveParsesAsIncomeWithCounterparty() {
        let sms = "تم استلام مبلغ 500.00 جنيه من Ahmed عبر انستاباي"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(string: "500.00"))
        XCTAssertFalse(parsed.isDebit, "Receiving money is income, not spending")
        XCTAssertTrue(parsed.isTransfer)
        XCTAssertEqual(parsed.merchant, "InstaPay: Ahmed")
    }

    func testInstaPaySendParsesAsExpenseWithCounterpartyAndDate() throws {
        let sms = "تم تحويل مبلغ 200 جنيه إلى Mohamed عبر انستاباي يوم 06/07/26"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(200))
        XCTAssertTrue(parsed.isDebit)
        XCTAssertEqual(parsed.merchant, "InstaPay: Mohamed")
        let parts = Calendar(identifier: .gregorian).dateComponents([.day, .month], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.day, 6)
        XCTAssertEqual(parts.month, 7)
    }

    /// The user's REAL InstaPay messages, verbatim.
    func testRealInstaPayReceivedSMS() throws {
        let sms = "تم إضافة تحويل لحظي لحسابكم رقم XXXX بمبلغ 300.00 جم من كريم شريف لويز كامل رقم مرجعي 911719910341 يوم 07-04\n الساعة 18:21 للمزيد اتصل بـ 19623"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(string: "300.00"))
        XCTAssertEqual(parsed.currency, "EGP") // "جم" marker.
        XCTAssertFalse(parsed.isDebit, "تم إضافة … لحسابكم = money IN")
        XCTAssertTrue(parsed.isTransfer)
        XCTAssertEqual(parsed.merchant, "InstaPay: كريم شريف لويز كامل")
        // "يوم 07-04", no year: July 4 (MM-DD) is days before "now" in this
        // conversation's timeframe; the nearest-plausible rule must not
        // pick April 7 (DD-MM reading).
        let parts = Calendar(identifier: .gregorian).dateComponents([.day, .month], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 4)
    }

    func testRealInstaPaySentSMS() throws {
        let sms = "تم تنفيذ تحويل لحظي من حسابكم رقم XXXX بمبلغ 570.00 جم إلى كريم ر**** س** ا*** رقم مرجعي 963077936261 يوم 07-02 الساعة 21:23 للمزيد اتصل بـ 19623"
        let parsed = BankSMSParser().parse(sms)
        XCTAssertEqual(parsed.amount, Decimal(string: "570.00"))
        XCTAssertTrue(parsed.isDebit, "من حسابكم = money OUT (must not trip the لحسابكم receive marker)")
        XCTAssertTrue(parsed.isTransfer)
        XCTAssertEqual(parsed.merchant, "InstaPay: كريم ر**** س** ا***")
        let parts = Calendar(identifier: .gregorian).dateComponents([.day, .month], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 2)
    }

    // MARK: - Balance auto-adjustment (fix for "net worth always 0")

    func testBalancesTrackExpensesIncomeEditsAndDeletes() throws {
        let (accountId, categoryId) = try firstIds()
        let writer = TransactionWriter(databaseManager: manager)
        // Starting balance: 1,000 (as the user would set in Settings).
        try manager.dbQueue().write { db in
            var account = try Account.fetchOne(db, id: accountId)!
            account.balance = 1_000
            try account.update(db)
        }
        func balance() throws -> Decimal {
            try manager.dbQueue().read { db in try Account.fetchOne(db, id: accountId)!.balance }
        }

        // Expense 200 → 800.
        let expense = try writer.insert(TransactionDraft(
            accountId: accountId, categoryId: categoryId, amount: 200, source: .manual
        ))
        XCTAssertEqual(try balance(), 800)
        // Income 500 (InstaPay receive) → 1,300.
        let income = try writer.insert(TransactionDraft(
            accountId: accountId, categoryId: categoryId, amount: 500,
            merchant: "InstaPay: Ahmed", source: .sms, direction: .income
        ))
        XCTAssertEqual(try balance(), 1_300)
        // Edit the expense to 300 → 1,200 (old effect reverted, new applied).
        try writer.update(transactionId: expense.id!, with: TransactionDraft(
            accountId: accountId, categoryId: categoryId, amount: 300, source: .manual
        ))
        XCTAssertEqual(try balance(), 1_200)
        // Delete the income → 700.
        try writer.delete(transactionId: income.id!)
        XCTAssertEqual(try balance(), 700)
    }

    // MARK: - Pending queue (background wallet/SMS captures)

    func testQueueRoundTripAndDrainClears() throws {
        let url = tempDir.appendingPathComponent("queue.enc")
        let fixedKey = Data(repeating: 0x11, count: 32)
        let queue = PendingCaptureQueue(fileURL: url, keyProvider: { fixedKey })

        try queue.append(.init(merchant: "Talabat", amount: Decimal(string: "2856.89")!,
                               currency: "EGP", date: Date(), sourceRaw: "sms"))
        try queue.append(.init(merchant: "Uber", amount: 120,
                               currency: "EGP", date: Date(), sourceRaw: "walletIntent"))

        // File on disk must not be readable plaintext.
        let raw = try Data(contentsOf: url)
        XCTAssertFalse(String(data: raw, encoding: .utf8)?.contains("Talabat") ?? false)

        let drained = try queue.drainAll()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained.first?.amount, Decimal(string: "2856.89"))
        XCTAssertTrue(try queue.drainAll().isEmpty, "Drain must clear the queue")
    }

    // MARK: - History-first categorization (fix for empty categories)

    func testMerchantCategoryIsRememberedFromHistory() throws {
        let (accountId, _) = try firstIds()
        // "Some Local Shop" isn't in any keyword table — but the user
        // categorized it as coffee once…
        let coffeeId = try manager.dbQueue().read { db in
            try Persistence.Category.filter(GRDB.Column("name") == "coffee").fetchOne(db)!.id!
        }
        try TransactionWriter(databaseManager: manager).insert(TransactionDraft(
            accountId: accountId, categoryId: coffeeId, amount: 60,
            merchant: "Some Local Shop", source: .manual
        ))
        // …so the next capture of the same merchant (any casing) reuses it.
        try manager.dbQueue().read { db in
            let suggested = try CategoryMatcher().suggestCategoryId(forMerchant: "SOME LOCAL SHOP", db: db)
            XCTAssertEqual(suggested, coffeeId)
        }
    }

    // MARK: - Duplicate guard (wallet vs SMS double-capture)

    func testDuplicateWithinWindowIsCaughtAndOutsideIsNot() throws {
        let (accountId, categoryId) = try firstIds()
        let writer = TransactionWriter(databaseManager: manager)
        try writer.insert(TransactionDraft(
            accountId: accountId, categoryId: categoryId,
            amount: Decimal(string: "350.50")!,
            date: Date().addingTimeInterval(-30 * 60), // Wallet captured 30 min ago.
            merchant: "Amazon", source: .walletIntent
        ))
        let guardService = DuplicateGuard(databaseManager: manager)
        // Same amount, now (SMS arriving) → duplicate.
        XCTAssertNotNil(try guardService.existingDuplicate(amount: Decimal(string: "350.50")!, around: Date()))
        // Different amount → clean.
        XCTAssertNil(try guardService.existingDuplicate(amount: Decimal(string: "350.51")!, around: Date()))
        // Same amount but 5 hours later → outside the ±3h window, clean
        // (two genuinely separate purchases of the same price).
        XCTAssertNil(try guardService.existingDuplicate(
            amount: Decimal(string: "350.50")!,
            around: Date().addingTimeInterval(5 * 60 * 60)
        ))
    }

    // MARK: - Receipt line items

    func testLineItemsExtractNamesAndPrices() {
        let rows = [
            "MERCADONA, S.A.",
            "1 MOUSSE KOKO P-4 1,20",
            "6 CREMA CATALANA 2,75",
            "TOTAL (€) 13,75",
            "LLIURAMENT EFECTIU 50,00",
            "25/05/2025 13:21",
            "A-46103834"
        ]
        let items = ReceiptOCRService.extractLineItems(fromRows: rows, total: Decimal(string: "13.75"))
        XCTAssertEqual(items.count, 2, "Totals, tender, dates, and ids must be skipped")
        XCTAssertEqual(items[0].name, "MOUSSE KOKO P-4")
        XCTAssertEqual(items[0].price, Decimal(string: "1.20"))
        XCTAssertEqual(items[1].name, "CREMA CATALANA")
        XCTAssertEqual(items[1].price, Decimal(string: "2.75"))
    }

    // MARK: - Recurring auto-link (feeds price-creep + bills)

    func testNewCaptureAutoLinksToConfirmedSeries() throws {
        for daysAgo in [60, 30] {
            try? 0 // placeholder no-op
            _ = daysAgo
        }
        let (accountId, categoryId) = try firstIds()
        // Confirm a series manually.
        let seriesId: Int64 = try manager.dbQueue().write { db in
            var series = RecurringSeries(
                merchantPattern: "Netflix", categoryId: categoryId,
                intervalDays: 30, expectedAmount: 200, confidence: 1
            )
            try series.insert(db)
            return series.id!
        }
        // A NEW charge from the same merchant links automatically.
        let txn = try TransactionWriter(databaseManager: manager).insert(TransactionDraft(
            accountId: accountId, categoryId: categoryId, amount: 230,
            merchant: "netflix", source: .sms
        ))
        let linked = try manager.dbQueue().read { db in
            try Persistence.Transaction.fetchOne(db, id: txn.id!)?.recurringSeriesId
        }
        XCTAssertEqual(linked, seriesId)
    }

    // MARK: - Category matching (stub behavior)

    func testKnownKeywordMatchesCategory() throws {
        try manager.dbQueue().read { db in
            let categoryId = try CategoryMatcher().suggestCategoryId(forMerchant: "CARREFOUR CITY CENTRE", db: db)
            let category = try Persistence.Category.fetchOne(db, id: categoryId)
            XCTAssertEqual(category?.name, "supermarket") // The user's canonical category list.
        }
    }

    func testUnknownMerchantFallsBackToUncategorized() throws {
        try manager.dbQueue().read { db in
            let categoryId = try CategoryMatcher().suggestCategoryId(forMerchant: "Some Random Shop 123", db: db)
            let category = try Persistence.Category.fetchOne(db, id: categoryId)
            XCTAssertEqual(category?.name, "Uncategorized",
                           "Unknown merchants must land in review, never a guessed category")
        }
    }
}

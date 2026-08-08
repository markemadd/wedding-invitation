#if DEBUG
import Foundation
import GRDB
import Persistence
import Capture

// MARK: - Screenshot mode (DEBUG ONLY — never in a release build)
// A deterministic, non-biometric build used solely to capture App Store
// screenshots. It is activated ONLY by launching with the `MIZAN_SCREENSHOT=1`
// environment variable (set by simctl at capture time and by nothing else), and
// the whole file is compiled out of Release via `#if DEBUG`. In this mode the
// app: swaps the Keychain/Face ID database key for a fixed one, seeds a
// realistic demo ledger, skips the intro/onboarding/lock, and opens the tab
// named by `MIZAN_SCREENSHOT_TAB` (wallet/bills/buckets/insights).
enum MizanScreenshotMode {
    static var isOn: Bool {
        ProcessInfo.processInfo.environment["MIZAN_SCREENSHOT"] == "1"
    }

    static var initialTab: String? {
        ProcessInfo.processInfo.environment["MIZAN_SCREENSHOT_TAB"]
    }

    /// "intro" → show the onboarding carousel; "profile" → show the first-run
    /// profile form; nil → the normal seeded dashboard.
    static var stage: String? {
        ProcessInfo.processInfo.environment["MIZAN_SCREENSHOT_STAGE"]
    }

    /// Pre-set the UserDefaults gates. By default the app opens straight into
    /// the dashboard; STAGE re-opens the intro carousel or the profile form so
    /// those onboarding screens can be captured too.
    static func prepareDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(stage != "intro", forKey: "didSeeIntro")
        defaults.set(stage != "intro" && stage != "profile", forKey: "didOnboard")
        // Leave the name empty on the profile stage so the onboarding form
        // renders blank; otherwise seed a friendly demo name.
        if stage != "profile", (defaults.string(forKey: "profileName") ?? "").isEmpty {
            defaults.set("Omar Hassan", forKey: "profileName")
        }
        defaults.set("Omar", forKey: "mizanUserName")
        // Monthly spending budget (a String preference) so Home + Buckets show
        // a real allowance instead of "set a budget".
        defaults.set("30000", forKey: "monthlyBudget")
        // Optional: exercise a pay-day budget cycle in screenshots.
        if let cycle = ProcessInfo.processInfo.environment["MIZAN_SCREENSHOT_CYCLE_DAY"],
           let day = Int(cycle) {
            defaults.set(day, forKey: BudgetCycle.startDayKey)
        } else {
            defaults.removeObject(forKey: BudgetCycle.startDayKey)
        }
    }
}

/// A fixed 256-bit key so the demo database opens without Face ID / Keychain.
struct ScreenshotKeyProvider: DatabaseKeyProviding {
    func fetchDatabaseKey() throws -> Data { Data(repeating: 0x5A, count: 32) }
}

// MARK: - ScreenshotSeeder
// Populates a believable few months of activity so every tab looks alive.
// Runs against the fixed-key database above (a throwaway simulator container),
// so it never touches real data.
struct ScreenshotSeeder {
    private let cal = Calendar.current
    private let now = Date()

    /// GRDB `insert` is mutating (it back-fills the row id), so a freshly
    /// constructed value must be bound to a `var` first. This wrapper does
    /// that for the many records here whose id we don't need afterward.
    private func put<T: MutablePersistableRecord>(_ record: T, _ db: Database) throws {
        var copy = record
        try copy.insert(db)
    }

    func seed() throws {
        // Categories, Cash+Bank accounts, and FX rates.
        try StarterDataBootstrapper().seedIfNeeded()
        let dbQueue = try DatabaseManager.shared.dbQueue()

        // Skip if a previous launch already seeded this container.
        let alreadySeeded = try dbQueue.read { try Transaction.fetchCount($0) > 0 }
        if alreadySeeded { return }

        var catId: [String: Int64] = [:]
        var bankId: Int64 = 0, cashId: Int64 = 0, visaId: Int64 = 0
        try dbQueue.write { db in
            try seedReferenceData(db, catId: &catId, bankId: &bankId, cashId: &cashId, visaId: &visaId)
        }
        try seedTransactions(catId: catId, bankId: bankId, cashId: cashId, visaId: visaId)

        NotificationCenter.default.post(name: Notification.Name("mizanDataDidChange"), object: nil)
    }

    /// Accounts, income, allocations, goals, subscriptions, plans, snapshots.
    private func seedReferenceData(_ db: Database, catId: inout [String: Int64],
                                   bankId: inout Int64, cashId: inout Int64,
                                   visaId: inout Int64) throws {
            for category in try Category.fetchAll(db) { catId[category.name] = category.id }

            let accounts = try Account.fetchAll(db)
            bankId = accounts.first { $0.name == "Bank" }?.id ?? 0
            cashId = accounts.first { $0.name == "Cash" }?.id ?? 0

            var visa = Account(name: "Visa", type: AccountType.creditCard.rawValue,
                               currency: "EGP", balance: 0, last4: "4218")
            try visa.insert(db)
            visaId = visa.id ?? 0

            // Monthly salary the budgets allocate from.
            try put(Income(amount: 45_000, currency: "EGP", updatedAt: now), db)

            // Percentage allocations (0–1 fractions) → budget rings + split.
            let allocations: [(String, Decimal)] = [
                ("food", Decimal(string: "0.18")!), ("supermarket", Decimal(string: "0.12")!),
                ("transportation", Decimal(string: "0.08")!), ("coffee", Decimal(string: "0.05")!),
                ("shopping", Decimal(string: "0.13")!), ("cinema", Decimal(string: "0.05")!),
                ("gas", Decimal(string: "0.07")!), ("barber", Decimal(string: "0.03")!),
                ("sports", Decimal(string: "0.05")!), ("luxury", Decimal(string: "0.05")!),
                ("travel", Decimal(string: "0.05")!), ("instapay", Decimal(string: "0.14")!)
            ]
            for (name, fraction) in allocations where catId[name] != nil {
                try put(CategoryAllocation(categoryId: catId[name]!, percentage: fraction), db)
            }

            // Goals + a sinking fund.
            try put(Goal(name: "Emergency fund", targetAmount: 120_000,
                         targetDate: date(monthsAgo: -8, day: 1), cutScope: .flexibleOnly,
                         createdAt: date(monthsAgo: 5, day: 1)), db)
            try put(Goal(name: "iPhone 17 Pro", targetAmount: 78_000,
                         targetDate: date(monthsAgo: -3, day: 1), cutScope: .anyCategory,
                         createdAt: date(monthsAgo: 2, day: 1)), db)
            try put(SinkingFund(name: "Car maintenance", targetAmount: 24_000,
                                targetDate: date(monthsAgo: -6, day: 1), currentAmount: 9_500,
                                categoryId: catId["gas"]), db)

            // Subscriptions (confirmed recurring series drive the Bills tab).
            try put(RecurringSeries(merchantPattern: "Netflix", categoryId: catId["cinema"] ?? 1,
                                    intervalDays: 30, expectedAmount: 199,
                                    confidence: Decimal(string: "0.95")!), db)
            try put(RecurringSeries(merchantPattern: "Spotify", categoryId: catId["cinema"] ?? 1,
                                    intervalDays: 30, expectedAmount: 120,
                                    confidence: Decimal(string: "0.93")!), db)
            try put(RecurringSeries(merchantPattern: "Gold's Gym", categoryId: catId["sports"] ?? 1,
                                    intervalDays: 30, expectedAmount: 850,
                                    confidence: Decimal(string: "0.9")!), db)

            // An installment plan + a bank certificate.
            try put(InstallmentPlan(name: "MacBook Air", providerName: "ValU",
                                    monthlyAmount: 3_100, totalInstallments: 12, paidCount: 4,
                                    startDate: date(monthsAgo: 4, day: 10)), db)
            try put(Certificate(name: "NBE 3-year certificate", bankName: "National Bank of Egypt",
                                principal: 200_000, monthlyInterest: 4_500,
                                startDate: date(monthsAgo: 6, day: 1),
                                maturityDate: date(monthsAgo: -30, day: 1),
                                accountId: bankId), db)

            // Six monthly net-worth snapshots so the trend line has points.
            for monthsAgo in stride(from: 5, through: 0, by: -1) {
                let net = Decimal(60_000 + (5 - monthsAgo) * 9_000)
                let snapDate = monthsAgo == 0 ? date(monthsAgo: 0, day: 15) : date(monthsAgo: monthsAgo, day: 26)
                try put(NetWorthSnapshot(date: snapDate, totalAssets: net + 8_000,
                                         totalLiabilities: 8_000, netWorth: net), db)
            }
    }

    /// A believable few months of activity, inserted through TransactionWriter
    /// so every account balance ends up correct.
    private func seedTransactions(catId: [String: Int64], bankId: Int64,
                                  cashId: Int64, visaId: Int64) throws {
        let writer = TransactionWriter()
        func acct(_ key: String) -> Int64 {
            switch key { case "cash": return cashId; case "visa": return visaId; default: return bankId }
        }
        func expense(_ monthsAgo: Int, _ day: Int, _ category: String, _ merchant: String,
                     _ amount: Decimal, _ account: String) throws {
            guard let cid = catId[category] else { return }
            let when = date(monthsAgo: monthsAgo, day: day)
            // Never seed a future-dated purchase: today's spend hasn't happened
            // past "now", and future rows made the Home donut disagree with the
            // (today-clipped) Insights spend.
            guard when <= now else { return }
            _ = try writer.insert(TransactionDraft(
                accountId: acct(account), categoryId: cid, amount: amount,
                date: when, merchant: merchant, source: .manual, direction: .expense))
        }

        for monthsAgo in 0...2 {
            // Salary in, plus an opening cash top-up in the oldest month.
            _ = try writer.insert(TransactionDraft(
                accountId: bankId, categoryId: catId["Uncategorized"] ?? 1, amount: 45_000,
                date: date(monthsAgo: monthsAgo, day: 1), merchant: "Salary",
                source: .manual, direction: .income))
            if monthsAgo == 2 {
                _ = try writer.insert(TransactionDraft(
                    accountId: cashId, categoryId: catId["Uncategorized"] ?? 1, amount: 8_000,
                    date: date(monthsAgo: 2, day: 2), merchant: "ATM withdrawal",
                    source: .manual, direction: .income))
            }
            let bump = Decimal(monthsAgo * 15) // small month-to-month variation
            try expense(monthsAgo, 3, "supermarket", "Carrefour", 1_850 + bump, "visa")
            try expense(monthsAgo, 4, "coffee", "Starbucks", 145, "cash")
            try expense(monthsAgo, 5, "cinema", "Netflix", 199, "visa")
            try expense(monthsAgo, 6, "food", "Zooba", 320 + bump, "visa")
            try expense(monthsAgo, 7, "transportation", "Uber", 210, "visa")
            try expense(monthsAgo, 8, "gas", "Wataneya", 900, "visa")
            try expense(monthsAgo, 9, "sports", "Gold's Gym", 850, "bank")
            try expense(monthsAgo, 11, "shopping", "Zara", 2_400 + bump, "visa")
            try expense(monthsAgo, 12, "coffee", "Costa", 130, "cash")
            try expense(monthsAgo, 14, "food", "Buffalo Burger", 410, "visa")
            try expense(monthsAgo, 15, "supermarket", "Seoudi Market", 1_240, "visa")
            try expense(monthsAgo, 16, "cinema", "Spotify", 120, "visa")
            try expense(monthsAgo, 18, "barber", "The Barbershop", 250, "cash")
            try expense(monthsAgo, 20, "transportation", "Uber", 185, "visa")
            try expense(monthsAgo, 22, "luxury", "Sephora", 1_600 + bump, "visa")
            if monthsAgo != 0 { // month-2/1 had a trip; current month not yet
                try expense(monthsAgo, 24, "travel", "Booking.com", 3_800, "visa")
            }
        }
    }

    private func date(monthsAgo: Int, day: Int) -> Date {
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.day = day
        let base = cal.date(from: comps) ?? now
        return cal.date(byAdding: .month, value: -monthsAgo, to: base) ?? base
    }
}
#endif

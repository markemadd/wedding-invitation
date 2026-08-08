import Foundation
import GRDB
import Budgeting
import Capture
import SavingsAndGoals
import Persistence
import UserNotifications
import UI

extension Notification.Name {
    /// Posted whenever transactions change, so passive views (dashboard
    /// gauge, plan tab) refresh without their own polling.
    static let mizanDataDidChange = Notification.Name("mizanDataDidChange")
}

// MARK: - CaptureViewModel
// Backs the capture hub and all three in-app capture flows. Fetches the
// reference data the form pickers need, keeps a short recent-transactions
// list so an insert is immediately visible (the Phase 2 checkpoint is
// "confirm all four methods land correctly"), and funnels every save
// through TransactionWriter.
@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [Persistence.Category] = []
    @Published private(set) var recentTransactions: [Persistence.Transaction] = []
    @Published private(set) var categoryNamesById: [Int64: String] = [:]
    @Published var errorMessage: String?
    /// Line items detected on the receipt being reviewed — written with
    /// the transaction on save (receipt flow sets this before saving).
    var pendingReceiptItems: [ReceiptCandidates.LineItem] = []

    private let writer = TransactionWriter()

    /// Seeds starter data on first run, then loads reference data.
    /// O(1) seed check + O(k) reference fetch + O(log n) recent query
    /// (date-ordered LIMIT scan over the primary index).
    func loadAfterUnlock() {
        do {
            try StarterDataBootstrapper().seedIfNeeded()
            // Daily net-worth snapshot (ERD's NET_WORTH_SNAPSHOT):
            // idempotent, freezes today's number for the history trend.
            try NetWorthSnapshotService().recordDailySnapshotIfNeeded()
            try importPendingCaptures()
            try reload()
        } catch {
            errorMessage = "Could not load data: \(error.localizedDescription)"
        }
    }

    /// Imports what the background intents queued while the app was
    /// locked: duplicate-checked (wallet trigger + bank SMS often report
    /// the SAME purchase) and categorized (history first, then brands).
    /// O(queue × log n) — queues are tiny.
    private func importPendingCaptures() throws {
        let pending = try PendingCaptureQueue().drainAll()
        guard !pending.isEmpty else { return }

        let dedup = DuplicateGuard()
        let matcher = CategoryMatcher()
        var imported = 0
        var duplicatesSkipped = 0

        for item in pending {
            guard let amount = item.amount, amount > 0 else { continue }
            if try dedup.existingDuplicate(amount: amount, around: item.date) != nil {
                duplicatesSkipped += 1
                continue
            }
            let dbQueue = try DatabaseManager.shared.dbQueue()
            let (accountId, categoryId) = try dbQueue.read { db -> (Int64, Int64) in
                // 1) A card last-4 from the SMS routes straight to that
                //    account. 2) else the user's chosen default (Settings).
                //    3) else the starter default.
                let account: Int64
                if let last4 = item.cardLast4,
                   let matched = try Account.filter(GRDB.Column("last4") == last4).fetchOne(db)?.id {
                    account = matched
                } else if let chosen = AppPreferences.defaultAccountId(), try Account.exists(db, id: chosen) {
                    account = chosen
                } else {
                    account = try StarterDataBootstrapper.defaultAccountId(db)
                }
                return (account, try matcher.suggestCategoryId(forMerchant: item.merchant, db: db))
            }
            try writer.insert(TransactionDraft(
                accountId: accountId,
                categoryId: categoryId,
                amount: amount,
                currency: item.currency,
                date: item.date,
                merchant: item.merchant,
                source: TransactionSource(rawValue: item.sourceRaw) ?? .sms,
                direction: TransactionDirection(rawValue: item.directionRaw ?? "expense") ?? .expense
            ))
            imported += 1
        }
        if imported > 0 || duplicatesSkipped > 0 {
            errorMessage = "Imported \(imported) captured transaction(s)"
                + (duplicatesSkipped > 0 ? " · skipped \(duplicatesSkipped) duplicate(s)" : "")
                + ". Review any in Uncategorized."
        }
    }

    /// Fire a local notification when a category crosses its allocation
    /// (asks permission the first time). Delivered even in-app via the app's
    /// notification delegate. Reusing one id per category avoids spamming.
    static func notifyCategoryLimit(category: String, spent: Decimal, allocated: Decimal) {
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Over budget: \(category)"
            content.body = "You've spent \(Money.egp(spent)) of your \(Money.egp(allocated)) \(category) budget this month."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "limit-\(category)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    func reload() throws {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        let (accounts, categories, recent) = try dbQueue.read { db in
            (
                try Account.order(GRDB.Column("name")).fetchAll(db),
                try Persistence.Category.order(GRDB.Column("name")).fetchAll(db),
                try Persistence.Transaction
                    .order(GRDB.Column("date").desc)
                    .limit(20)
                    .fetchAll(db)
            )
        }
        self.accounts = accounts
        self.categories = categories
        self.recentTransactions = recent
        self.categoryNamesById = Dictionary(
            uniqueKeysWithValues: categories.compactMap { category in
                category.id.map { ($0, category.name) }
            }
        )
        NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
        // Keep the Home/Lock Screen widgets current after any capture,
        // edit, or background-queue drain — not only when the Wallet tab
        // happens to be on screen.
        WidgetSnapshotPublisher.refresh()
    }

    /// Every capture flow ends here. Returns true on success so sheets know
    /// to dismiss.
    func save(form: TransactionFormData, source: TransactionSource) -> Bool {
        guard let amount = form.amount, let accountId = form.accountId, let categoryId = form.categoryId else {
            errorMessage = "The form is incomplete."
            return false
        }
        do {
            let draft = TransactionDraft(
                accountId: accountId,
                categoryId: categoryId,
                amount: amount,
                // From the form's currency picker (pre-filled by receipt
                // detection). How multi-currency rolls up into net worth
                // is the Phase 3 conversion decision the blueprint flags;
                // capture just records the truth.
                currency: form.currency,
                date: form.date,
                merchant: form.merchant.isEmpty ? nil : form.merchant,
                source: source,
                direction: form.direction
            )
            let saved = try writer.insert(draft)
            // Attach detected line items (receipt captures only) — cascade
            // deletes with the transaction.
            if source == .receiptOCR, !pendingReceiptItems.isEmpty, let transactionId = saved.id {
                let items = pendingReceiptItems
                try DatabaseManager.shared.dbQueue().write { db in
                    for item in items {
                        var row = ReceiptItem(transactionId: transactionId, name: item.name, price: item.price)
                        try row.insert(db)
                    }
                }
            }
            pendingReceiptItems = []
            try reload()
            // Post-save integrity nudge (Phase 4.3 wired in the Phase 6
            // integration pass): flag suspected duplicates and unusual
            // amounts. The save is NOT blocked — the user already
            // confirmed it; this is a heads-up they can act on from the
            // Transactions tab (swipe-delete).
            // Category-limit alert (user-requested): crossing 100% of the
            // allocation shouts, crossing 80% warns — same thresholds as
            // the dashboard's mint/cream/red color language.
            if let summary = try? SalaryAllocationService().monthlySummary(for: Date())
                .first(where: { $0.category.id == categoryId }),
               summary.allocated > 0 {
                if summary.spent > summary.allocated {
                    errorMessage = "Saved — you've passed your \(summary.category.name) limit: \(summary.spent) of \(summary.allocated) EGP this month."
                    Self.notifyCategoryLimit(category: summary.category.name, spent: summary.spent, allocated: summary.allocated)
                } else if summary.spent >= summary.allocated * Decimal(string: "0.8")! {
                    errorMessage = "Saved — heads up: \(summary.category.name) is at \(summary.spent) of \(summary.allocated) EGP (over 80%)."
                }
            }
            if let findings = try? AnomalyDetectionService().check(saved), !findings.isClean {
                if findings.likelyDuplicateOf != nil {
                    errorMessage = "Saved — but this looks like a duplicate of a transaction minutes ago. Swipe it away in Transactions if so."
                } else if let mean = findings.categoryMean {
                    errorMessage = "Saved — heads up: this is far from your usual \(mean) EGP for this category."
                }
            }
            return true
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
            return false
        }
    }

    /// Pre-fills a form from OCR candidates. A nil OCR date becomes "now" —
    /// the date-parsing stub is pending real receipt samples, and today is
    /// the most likely correct value for a just-photographed receipt.
    func makeForm(fromReceipt candidates: ReceiptCandidates) -> TransactionFormData {
        var form = TransactionFormData()
        if let amount = candidates.amount {
            form.amountText = "\(amount)"
        }
        form.date = candidates.date ?? Date()
        form.merchant = candidates.merchant ?? ""
        form.currency = candidates.currency
        form.accountId = AppPreferences.resolvedDefaultAccountId(in: accounts)
        form.categoryId = suggestedCategoryId(forMerchant: candidates.merchant ?? "")
        return form
    }

    /// Pre-fills a form from a parsed voice utterance.
    func makeForm(fromVoice parsed: VoiceDraftParser.ParsedUtterance) -> TransactionFormData {
        var form = TransactionFormData()
        if let amount = parsed.amount {
            form.amountText = "\(amount)"
        }
        form.merchant = parsed.merchantHint
        form.accountId = AppPreferences.resolvedDefaultAccountId(in: accounts)
        form.categoryId = suggestedCategoryId(forMerchant: parsed.merchantHint)
        return form
    }

    /// Also used live by the manual form as the merchant field changes —
    /// hence internal, not private. Returns nil for an empty merchant.
    func suggestedCategoryId(forMerchant merchant: String) -> Int64? {
        guard !merchant.isEmpty else { return nil }
        return try? DatabaseManager.shared.dbQueue().read { db in
            try CategoryMatcher().suggestCategoryId(forMerchant: merchant, db: db)
        }
    }

    /// The id of the "Uncategorized" fallback — used to decide whether an
    /// auto-suggestion should overwrite the current category (it never
    /// overwrites a real choice the user made by hand).
    var uncategorizedId: Int64? {
        try? DatabaseManager.shared.dbQueue().read { db in
            try StarterDataBootstrapper.uncategorizedCategoryId(db)
        }
    }

    /// Quick account/card creation from the capture form ("CIB Credit"
    /// etc.) — a slice of Phase 3.1's account CRUD pulled forward because
    /// picking the right card at capture time needs the card to exist.
    /// Returns the new account's id so the form can select it immediately.
    func createAccount(name: String, type: AccountType, last4: String? = nil) -> Int64? {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            let account = try dbQueue.write { db in
                var account = Account(name: name, type: type.rawValue, currency: "EGP",
                                      balance: 0, last4: last4)
                try account.insert(db)
                return account
            }
            try reload()
            return account.id
        } catch {
            errorMessage = "Could not create the account: \(error.localizedDescription)"
            return nil
        }
    }
}

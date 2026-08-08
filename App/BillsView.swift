import SwiftUI
import GRDB
import Capture
import SavingsAndGoals
import Persistence
import UI

// MARK: - BillsView (ENHANCEMENTS Wave B1)
// Promotes bills/subscriptions from a buried PlanView section to a
// first-class tab with three sub-tabs: recurring Subscriptions, finite
// Installment plans, and Smart Suggestions (detector candidates the user
// confirms or dismisses). Header card summarizes the recurring load.
struct BillsView: View {
    @StateObject private var model = BillsViewModel()
    @State private var tab: Tab = .subscriptions
    @State private var showNewInstallment = false
    @State private var showNewCertificate = false

    enum Tab: String, CaseIterable, Identifiable {
        case subscriptions = "Subs"
        case installments = "Installments"
        case certificates = "Certificates"
        case suggestions = "Suggestions"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KitTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        Picker("View", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch tab {
                        case .subscriptions: subscriptionsTab
                        case .installments: installmentsTab
                        case .certificates: certificatesTab
                        case .suggestions: suggestionsTab
                        }
                    }
                    .padding(20)
                    .padding(.bottom, TabBarLayout.clearance)
                }
            }
            .navigationTitle("Bills")
            .toolbar {
                if tab == .installments {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewInstallment = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                if tab == .certificates {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewCertificate = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewInstallment) {
                NewInstallmentView(model: model)
            }
            .sheet(isPresented: $showNewCertificate) {
                NewCertificateView(model: model)
            }
            .task { model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .mizanDataDidChange)) { _ in
                model.load()
            }
            .alert("Bills", isPresented: .constant(model.errorMessage != nil)) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }

    // Green summary hero (kit primary), dark text for contrast on bright green.
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly spending")
                .font(.caption).foregroundStyle(.black.opacity(0.6))
            Text(model.monthlyTotalText)
                .font(.largeTitle.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
            HStack(spacing: 10) {
                statPill("Active", "\(model.activeCount)")
                statPill("Per year", "\(model.perYearText)")
                statPill("This week", "\(model.thisWeekCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(KitTheme.primary)
        .cornerRadius(24)
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.black.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: Subscriptions

    private var subscriptionsTab: some View {
        VStack(spacing: 12) {
            if model.subscriptions.isEmpty {
                emptyState("No subscriptions yet", "Confirm a suggestion, or they'll appear as recurring charges are detected.")
            } else {
                ForEach(model.subscriptions) { series in
                    KitCard {
                        HStack {
                            CategoryChip(name: model.categoryName(series.categoryId))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(series.merchantPattern).font(.subheadline.weight(.medium))
                                Text("every \(series.intervalDays) days · \(model.categoryName(series.categoryId))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.egp(series.expectedAmount))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    // MARK: Installments

    private var installmentsTab: some View {
        VStack(spacing: 12) {
            if model.installments.isEmpty {
                emptyState("No installment plans", "Tap + to add a ValU / Halan-style financed purchase and track its progress.")
            } else {
                ForEach(model.installments) { plan in
                    InstallmentCard(plan: plan) { model.markPayment(plan) }
                        .swipeActions {
                            Button(role: .destructive) { model.deleteInstallment(plan) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: Certificates (شهادة — recurring bank interest)

    private var certificatesTab: some View {
        VStack(spacing: 12) {
            if model.certificates.isEmpty {
                emptyState("No certificates",
                           "Tap + to add a bank certificate (شهادة). Mizan tracks the monthly interest it deposits and counts down to maturity.")
            } else {
                ForEach(model.certificates) { certificate in
                    CertificateCard(
                        certificate: certificate,
                        accountName: model.accountName(certificate.accountId),
                        onLogInterest: { model.logCertificateInterest(certificate) }
                    )
                    .swipeActions {
                        Button(role: .destructive) { model.deleteCertificate(certificate) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Smart Suggestions

    private var suggestionsTab: some View {
        VStack(spacing: 12) {
            if model.candidates.isEmpty {
                emptyState("Nothing to suggest", "As repeating charges build up, likely subscriptions show up here to confirm.")
            } else {
                ForEach(model.candidates) { candidate in
                    KitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                CategoryChip(name: candidate.merchant)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.merchant).font(.subheadline.weight(.medium))
                                    Text(model.candidateDetail(candidate))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button {
                                    model.dismiss(candidate)
                                } label: {
                                    Label("Dismiss", systemImage: "xmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered).tint(.red)
                                Button {
                                    model.confirm(candidate)
                                } label: {
                                    Label("Confirm", systemImage: "checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent).tint(AppTheme.accentMint)
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        KitCard {
            VStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - InstallmentCard
// Progress card matching the inspiration's "3 of 12 paid". Tapping "Pay"
// increments paidCount via the view model.
struct InstallmentCard: View {
    let plan: InstallmentPlan
    let onPay: () -> Void

    private var fraction: Double {
        guard plan.totalInstallments > 0 else { return 0 }
        return Double(plan.paidCount) / Double(plan.totalInstallments)
    }

    var body: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CategoryChip(name: plan.providerName ?? plan.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name).font(.subheadline.weight(.medium))
                        Text("\(plan.paidCount) of \(plan.totalInstallments) paid")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.egp(plan.monthlyAmount) + " / mo")
                        .font(.subheadline.monospacedDigit())
                }
                SegmentedProgressBar(fraction: fraction)
                HStack {
                    Text(Money.egp(plan.remainingAmount) + " left")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if plan.paidCount < plan.totalInstallments {
                        Button("Mark paid", action: onPay)
                            .buttonStyle(.bordered).tint(AppTheme.accentMint).font(.caption)
                    } else {
                        Text("Paid off")
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accentMint)
                    }
                }
            }
        }
    }
}

// MARK: - CertificateCard
// A bank certificate: monthly interest it pays, the account it deposits to,
// and a maturity countdown. "Log interest" records this month's deposit as
// income (once per month).
struct CertificateCard: View {
    let certificate: Certificate
    let accountName: String?
    let onLogInterest: () -> Void

    var body: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CategoryChip(name: certificate.bankName ?? certificate.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(certificate.name).font(.subheadline.weight(.medium))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Money.egp(certificate.monthlyInterest) + " / mo")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppTheme.accentMint)
                        Text("interest").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label(maturityText, systemImage: certificate.isActive ? "calendar" : "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(certificate.isActive ? .secondary : AppTheme.accentMint)
                    Spacer()
                    if certificate.isActive {
                        if certificate.isThisMonthUnlogged {
                            Button("Log interest", action: onLogInterest)
                                .buttonStyle(.bordered).tint(AppTheme.accentMint).font(.caption)
                        } else {
                            Text("This month logged")
                                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accentMint)
                        }
                    } else {
                        Text("Matured").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let bank = certificate.bankName { parts.append(bank) }
        parts.append("principal \(Money.egp(certificate.principal))")
        if let accountName { parts.append("→ \(accountName)") }
        return parts.joined(separator: " · ")
    }

    private var maturityText: String {
        certificate.isActive
            ? "Matures \(certificate.maturityDate.formatted(date: .abbreviated, time: .omitted)) · \(certificate.monthsToMaturity) mo left"
            : "Matured \(certificate.maturityDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

@MainActor
final class BillsViewModel: ObservableObject {
    @Published var subscriptions: [RecurringSeries] = []
    @Published var installments: [InstallmentPlan] = []
    @Published var certificates: [Certificate] = []
    @Published var candidates: [RecurringSeriesCandidate] = []
    /// A failed write must never look like success — shown in an alert.
    @Published var errorMessage: String?
    private var accountNames: [Int64: String] = [:]

    private let detection = RecurringDetectionService()
    private let billsService = BillsCalendarService()
    private var categoryNames: [Int64: String] = [:]
    /// Candidates the user dismissed this session. The detector recomputes
    /// from raw transactions each load, so without this a dismissed
    /// suggestion would immediately reappear.
    private var dismissedMerchants: Set<String> = []
    private var upcoming: [BillsCalendarService.UpcomingBill] = []

    func categoryName(_ id: Int64) -> String { categoryNames[id] ?? "?" }

    func candidateDetail(_ candidate: RecurringSeriesCandidate) -> String {
        let sure = Int(truncating: (candidate.confidence * 100) as NSNumber)
        return "every \(candidate.intervalDays) days · ~\(Money.egp(candidate.expectedAmount)) · \(sure)% sure"
    }

    // MARK: Header stats

    /// Monthly-equivalent recurring load: each subscription normalized to a
    /// 30-day month, plus each still-active installment's monthly amount.
    var monthlyTotal: Decimal {
        let subs = subscriptions.reduce(Decimal(0)) { sum, series in
            guard series.intervalDays > 0 else { return sum }
            return sum + series.expectedAmount * Decimal(30) / Decimal(series.intervalDays)
        }
        let plans = installments
            .filter { $0.paidCount < $0.totalInstallments }
            .reduce(Decimal(0)) { $0 + $1.monthlyAmount }
        return subs + plans
    }
    var monthlyTotalText: String { Money.egp(monthlyTotal) }
    var perYearText: String { Money.egp(monthlyTotal * 12) }
    var activeCount: Int {
        subscriptions.count + installments.filter { $0.paidCount < $0.totalInstallments }.count
    }
    var thisWeekCount: Int {
        let weekAhead = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return upcoming.filter { $0.nextExpectedDate <= weekAhead }.count
    }

    private func formatted(_ value: Decimal) -> String {
        // Whole EGP for the header — cents add noise to a summary number.
        NSDecimalNumber(decimal: value).rounding(accordingToBehavior:
            NSDecimalNumberHandler(roundingMode: .plain, scale: 0,
                                   raiseOnExactness: false, raiseOnOverflow: false,
                                   raiseOnUnderflow: false, raiseOnDivideByZero: false)).stringValue
    }

    func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            let (series, plans, categories) = try dbQueue.read { db in
                (
                    try RecurringSeries.order(GRDB.Column("merchantPattern")).fetchAll(db),
                    try InstallmentPlan.order(GRDB.Column("startDate").desc).fetchAll(db),
                    try Persistence.Category.fetchAll(db)
                )
            }
            categoryNames = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                category.id.map { ($0, category.name) }
            })
            // Subscriptions = short-cycle series (≤ 31 days). Longer cycles
            // (quarterly/annual) read as bills, not subscriptions.
            subscriptions = series.filter { $0.intervalDays <= 31 }
            installments = plans
            let (certs, accounts) = try dbQueue.read { db in
                (try Certificate.order(GRDB.Column("maturityDate")).fetchAll(db),
                 try Account.fetchAll(db))
            }
            certificates = certs
            accountNames = Dictionary(uniqueKeysWithValues: accounts.compactMap { account in
                account.id.map { ($0, account.name) }
            })
            candidates = (try? detection.detectRecurringSeries())?
                .filter { !dismissedMerchants.contains($0.merchant.lowercased()) } ?? []
            upcoming = (try? billsService.upcomingBills()) ?? []
        } catch {
            subscriptions = []
            installments = []
            certificates = []
            candidates = []
        }
    }

    func accountName(_ id: Int64?) -> String? { id.flatMap { accountNames[$0] } }

    // MARK: Certificates

    func addCertificate(_ draft: CertificateDraft) {
        guard let principal = Decimal(string: draft.principal, locale: Locale(identifier: "en_US_POSIX")),
              let monthlyInterest = Decimal(string: draft.monthlyInterest, locale: Locale(identifier: "en_US_POSIX")),
              monthlyInterest > 0 else {
            errorMessage = "Enter a valid interest amount."
            return
        }
        do {
            try DatabaseManager.shared.dbQueue().write { db in
                var certificate = Certificate(
                    name: draft.name,
                    bankName: draft.bankName.isEmpty ? nil : draft.bankName,
                    principal: principal,
                    monthlyInterest: monthlyInterest,
                    startDate: draft.startDate,
                    maturityDate: draft.maturityDate,
                    accountId: draft.accountId)
                try certificate.insert(db)
            }
        } catch { errorMessage = error.localizedDescription }
        load()
    }

    /// Records this month's interest as INCOME to the linked account (via
    /// TransactionWriter, so the balance moves), then stamps the month so it
    /// can't be logged twice.
    func logCertificateInterest(_ certificate: Certificate) {
        guard let id = certificate.id else { return }
        guard let accountId = certificate.accountId else {
            errorMessage = "Link an account to this certificate first (delete and re-add with an account)."
            return
        }
        guard let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start else { return }
        do {
            let categoryId = try ensureInterestCategory()
            _ = try TransactionWriter().insert(TransactionDraft(
                accountId: accountId,
                categoryId: categoryId,
                amount: certificate.monthlyInterest,
                currency: certificate.currency,
                date: Date(),
                merchant: "\(certificate.bankName ?? certificate.name) interest",
                source: .manual,
                direction: .income))
            try DatabaseManager.shared.dbQueue().write { db in
                guard var row = try Certificate.fetchOne(db, id: id) else { return }
                row.lastLoggedMonth = monthStart
                try row.update(db)
            }
            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
        } catch { errorMessage = error.localizedDescription }
        load()
    }

    func deleteCertificate(_ certificate: Certificate) {
        guard let id = certificate.id else { return }
        do {
            _ = try DatabaseManager.shared.dbQueue().write { db in
                try Certificate.deleteOne(db, id: id)
            }
        } catch { errorMessage = error.localizedDescription }
        load()
    }

    /// Shared "Interest" income category, created once if missing.
    private func ensureInterestCategory() throws -> Int64 {
        try DatabaseManager.shared.dbQueue().write { db in
            if let existing = try Persistence.Category
                .filter(GRDB.Column("name") == "Interest").fetchOne(db), let id = existing.id {
                return id
            }
            var category = Persistence.Category(name: "Interest", bucket: .flexible)
            try category.insert(db)
            guard let id = category.id else { throw CertificateError.categoryCreationFailed }
            return id
        }
    }

    enum CertificateError: Error { case categoryCreationFailed }

    func confirm(_ candidate: RecurringSeriesCandidate) {
        do {
            try detection.confirm(candidate)
            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
        } catch { errorMessage = error.localizedDescription }
        load()
    }

    func dismiss(_ candidate: RecurringSeriesCandidate) {
        dismissedMerchants.insert(candidate.merchant.lowercased())
        candidates.removeAll { $0.id == candidate.id }
    }

    func addInstallment(_ draft: InstallmentDraft) {
        guard let monthlyAmount = Decimal(string: draft.monthly, locale: Locale(identifier: "en_US_POSIX")),
              let totalCount = Int(draft.total), totalCount > 0 else { return }
        let paidCount = min(max(0, Int(draft.paid) ?? 0), totalCount)
        do {
            try DatabaseManager.shared.dbQueue().write { db in
                var plan = InstallmentPlan(
                    name: draft.name,
                    providerName: draft.provider.isEmpty ? nil : draft.provider,
                    monthlyAmount: monthlyAmount,
                    totalInstallments: totalCount,
                    paidCount: paidCount,
                    startDate: draft.startDate
                )
                try plan.insert(db)
            }
        } catch { errorMessage = error.localizedDescription }
        load()
    }

    func markPayment(_ plan: InstallmentPlan) {
        guard let id = plan.id, plan.paidCount < plan.totalInstallments else { return }
        do {
            try DatabaseManager.shared.dbQueue().write { db in
                guard var row = try InstallmentPlan.fetchOne(db, id: id) else { return }
                row.paidCount += 1
                try row.update(db)
            }
        } catch { errorMessage = error.localizedDescription }
        load()
    }

    func deleteInstallment(_ plan: InstallmentPlan) {
        guard let id = plan.id else { return }
        do {
            _ = try DatabaseManager.shared.dbQueue().write { db in
                try InstallmentPlan.deleteOne(db, id: id)
            }
        } catch { errorMessage = error.localizedDescription }
        load()
    }
}

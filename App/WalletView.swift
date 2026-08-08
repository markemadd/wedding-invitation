import SwiftUI
import Charts
import GRDB
import WidgetKit
import Budgeting
import Persistence
import MizanSecurity
import UI

// MARK: - WalletView (Home) — kit re-skin
// The home tab, rebuilt in the Figma kit's language (flat dark canvas, #121418
// cards, donut, pill chips, record rows) with Mizan green as the primary
// accent. Layout borrows from the "Money management" community design: an
// avatar + total-balance header, a this-month budget card with a daily
// allowance and days-left, a Wallets carousel of accounts, the spending
// donut, quick-capture, an Investments link, and recent records. Data comes
// from HomeViewModel + CaptureViewModel — no arithmetic in the view.
struct WalletView: View {
    @EnvironmentObject private var lockViewModel: AppLockViewModel
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var viewModel = CaptureViewModel()
    @StateObject private var home = HomeViewModel()
    @State private var activeSheet: CaptureSheet?
    @State private var showProfileEdit = false
    @State private var showBalanceEdit = false
    @State private var showArrange = false
    @State private var showTransfer = false
    @State private var showAllTransactions = false

    /// Drag-to-arrange (restored): the order of the movable dashboard widgets
    /// persists as a CSV of raw values, reordered in the Arrange sheet.
    /// (Unknown values from older builds — e.g. the removed "chart" — are
    /// dropped by the compactMap in `widgetOrder`.)
    @AppStorage("homeWidgetOrder") private var widgetOrderRaw = "monthBudget,wellDone,wallets,categories"
    @State private var showSettings = false
    /// Categories donut: tap to expand into the full per-category breakdown.
    @State private var donutExpanded = false

    enum CaptureSheet: Identifiable {
        case manual, receipt, voice, sms, split
        var id: Self { self }
    }

    /// The reorderable Home widgets (the fixed header / AI / capture / recent
    /// sections stay put; these are user-arrangeable). The income-vs-expense
    /// chart moved to the Insights tab — Home stays a glanceable dashboard.
    enum HomeWidget: String, CaseIterable, Identifiable {
        case monthBudget, wellDone, wallets, categories
        var id: String { rawValue }
        var title: String {
            switch self {
            case .monthBudget: return "Monthly budget"
            case .wellDone: return "Well done"
            case .wallets: return "Wallets"
            case .categories: return "Spending categories"
            }
        }
    }

    private var widgetOrder: [HomeWidget] {
        var seen = widgetOrderRaw.split(separator: ",").compactMap { HomeWidget(rawValue: String($0)) }
        for widget in HomeWidget.allCases where !seen.contains(widget) { seen.append(widget) }
        return seen
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    header
                    if aiEntryAvailable { aiEntry }
                    // Reorderable dashboard widgets.
                    ForEach(widgetOrder) { widget in
                        widgetView(widget)
                            .contextMenu {
                                Button { showArrange = true } label: {
                                    Label("Arrange widgets…", systemImage: "arrow.up.arrow.down")
                                }
                            }
                    }
                    captureCard
                    recentCard
                    arrangeButton
                }
                .padding(.horizontal, 15)
                .padding(.top, 4)
                .padding(.bottom, TabBarLayout.clearance)
            }
            .kitBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .manual:  ManualEntryView(viewModel: viewModel)
                case .receipt: ReceiptCaptureView(viewModel: viewModel)
                case .voice:   VoiceCaptureView(viewModel: viewModel)
                case .sms:     SMSCaptureView(viewModel: viewModel)
                case .split:   BillSplitView(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showProfileEdit) { ProfileFormView(isOnboarding: false) }
            .sheet(isPresented: $showSettings, onDismiss: { reload() }) { SettingsView() }
            .sheet(isPresented: $showBalanceEdit, onDismiss: { home.load() }) {
                AccountBalancesEditorView()
            }
            .sheet(isPresented: $showTransfer, onDismiss: { home.load() }) { TransferView() }
            .sheet(isPresented: $showAllTransactions) { TransactionsView() }
            .sheet(isPresented: $showArrange) {
                HomeArrangeSheet(orderRaw: $widgetOrderRaw).presentationDetents([.medium])
            }
            .task { reload() }
            #if DEBUG
            .task { if MizanScreenshotMode.initialTab == "split" { activeSheet = .split } }
            #endif
            .refreshable { reload() }
            // Only refresh the dashboard numbers here — NOT the full reload().
            // CaptureViewModel.reload() posts .mizanDataDidChange itself, so
            // reacting to that notification by calling it again would loop
            // forever and freeze the main thread. home.load() posts nothing.
            .onReceive(NotificationCenter.default.publisher(for: .mizanDataDidChange)) { _ in
                home.load()
            }
        }
    }

    private func reload() {
        viewModel.loadAfterUnlock()
        home.load()
    }

    // MARK: Header — "Home" title, avatar, total balance, add

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("Home")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(KitTheme.textPrimary)
                Spacer()
                // Settings lives here now (gear), not on the tab bar — the
                // bar's center slot went to the "+" quick-add.
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KitTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(KitTheme.card, in: Circle())
                }
                .buttonStyle(.plain)
                Button { showProfileEdit = true } label: { ProfileAvatar(size: 44) }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button { showBalanceEdit = true } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text("Total Balance")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(KitTheme.textSecondary)
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(KitTheme.textSecondary)
                        }
                        Text(home.totalBalanceText)
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(KitTheme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private var arrangeButton: some View {
        Button { showArrange = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Arrange widgets")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KitTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    /// Renders one reorderable dashboard widget.
    @ViewBuilder
    private func widgetView(_ widget: HomeWidget) -> some View {
        switch widget {
        case .monthBudget: monthBudgetCard
        case .wellDone: if home.showWellDone { wellDoneCard }
        case .wallets: walletsSection
        case .categories: if !home.donut.isEmpty { categoriesCard }
        }
    }

    // MARK: Well done insight

    private var wellDoneCard: some View {
        let tint = home.wellDonePositive ? KitTheme.primary : Color(hexValue: 0xFF7A45)
        return KitCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(home.wellDoneTitle)
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(KitTheme.textPrimary)
                    Text(home.wellDoneText)
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 8)
                    Circle().trim(from: 0, to: home.wellDoneFraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(home.savedText)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(KitTheme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(home.wellDoneRingLabel).font(.system(size: 10)).foregroundStyle(KitTheme.textSecondary)
                    }
                    .frame(width: 60)
                }
                .frame(width: 82, height: 82)
            }
        }
    }

    // MARK: AI entry

    /// The AI entry only appears when a backend actually exists — Apple's
    /// on-device model (A17 Pro+/iOS 26) or the user's own opt-in server.
    /// On every other device it stays hidden, so nobody sees a feature that
    /// can't answer (App Store Guideline 2.1 — no non-functional surfaces).
    private var aiEntryAvailable: Bool { MizanAISettings.makeBackend() != nil }

    private var aiEntry: some View {
        NavigationLink { MizanAIView() } label: {
            KitCard(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(KitTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask Mizan AI")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                        Text("Questions about your money, answered")
                            .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: This-month budget (daily allowance + days left)

    private var monthBudgetCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(home.budgetTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KitTheme.textPrimary)
                if home.hasMonthBudget {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(home.budgetConsumedText)
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(KitTheme.primary)
                        Text("/ \(home.monthlyBudgetText)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KitTheme.textSecondary)
                        Spacer()
                        Text("\(home.budgetPercent)%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KitTheme.textSecondary)
                    }
                    KitProgressBar(fraction: Double(home.budgetPercent) / 100)
                    HStack {
                        Text("Daily allowance · \(home.dailyBudgetText)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KitTheme.textSecondary)
                        Spacer()
                        Text(home.daysLeftText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KitTheme.textSecondary)
                    }
                } else {
                    Text(home.budgetConsumedText)
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(KitTheme.textPrimary)
                    Text("spent so far. Set a monthly budget in the Buckets tab to track it here with a daily allowance.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KitTheme.textTertiary)
                }
            }
        }
    }

    // MARK: Wallets carousel

    private var walletsSection: some View {
        VStack(spacing: 12) {
            KitSectionHeader("Wallets")
            if home.wallets.isEmpty {
                KitCard {
                    Text("Add an account or card in Settings to see your wallets here.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KitTheme.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(home.wallets) { wallet in
                            walletCard(wallet)
                        }
                    }
                }
            }
        }
    }

    private func walletCard(_ wallet: HomeViewModel.Wallet) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(wallet.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KitTheme.textSecondary)
                    Text(wallet.balanceText)
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundStyle(KitTheme.textPrimary)
                }
                Spacer()
                Image(systemName: wallet.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(wallet.color, in: Circle())
            }
            Text(wallet.typeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KitTheme.textTertiary)
        }
        .padding(16)
        .frame(width: 190, alignment: .leading)
        .background(wallet.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(wallet.color.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: Categories donut (tap to expand into the full breakdown)

    private var categoriesCard: some View {
        KitCard(padding: 20) {
            VStack(spacing: donutExpanded ? 24 : 35) {
                KitSectionHeader("Categories", action: donutExpanded ? "Collapse" : "Expand") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        donutExpanded.toggle()
                    }
                }
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        donutExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        DonutRing(segments: home.donut)
                            .frame(width: donutExpanded ? 232 : 197, height: donutExpanded ? 232 : 197)
                        VStack(spacing: 5) {
                            Text("Expense")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                            Text(home.expenseTotalText)
                                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                                .foregroundStyle(KitTheme.textPrimary)
                            if !donutExpanded {
                                Text("tap to expand")
                                    .font(.system(size: 10)).foregroundStyle(KitTheme.textTertiary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                if donutExpanded {
                    // Full breakdown: each category with its share of the
                    // month's spending and a share bar.
                    VStack(spacing: 14) {
                        ForEach(home.categoryPills) { pill in
                            VStack(spacing: 7) {
                                HStack(spacing: 10) {
                                    Circle().fill(pill.color).frame(width: 10, height: 10)
                                    Text(pill.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(KitTheme.textPrimary)
                                    Spacer()
                                    Text("\(Int((pill.share * 100).rounded()))%")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(KitTheme.textSecondary)
                                    Text(pill.amountText)
                                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(KitTheme.textPrimary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(KitTheme.ink.opacity(0.1))
                                        Capsule().fill(pill.color)
                                            .frame(width: max(3, geo.size.width * pill.share))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(home.categoryPills) { pill in
                                AmountPill(color: pill.color, title: pill.name,
                                           amount: pill.amountText, iconSize: 14, fillOpacity: 0.05)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Quick capture

    private var captureCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                KitSectionHeader("Add a transaction")
                HStack(spacing: 12) {
                    captureButton("Manual", "square.and.pencil") { activeSheet = .manual }
                    captureButton("Receipt", "doc.text.viewfinder") { activeSheet = .receipt }
                    captureButton("Voice", "mic.fill") { activeSheet = .voice }
                    captureButton("SMS", "message.fill") { activeSheet = .sms }
                    captureButton("Split", "person.2.fill") { activeSheet = .split }
                }
                Button { showTransfer = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Transfer between accounts")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KitTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button { activeSheet = .split } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                        Text("Split a bill")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KitTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func captureButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(KitTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent records

    private var recentCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 20) {
                KitSectionHeader("Transactions", action: "See All") { showAllTransactions = true }
                if viewModel.recentTransactions.isEmpty {
                    Text("No transactions yet — capture your first one above.")
                        .font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                } else {
                    ForEach(viewModel.recentTransactions.prefix(5)) { transaction in
                        let income = transaction.direction == .income
                        let category = viewModel.categoryNamesById[transaction.categoryId] ?? "?"
                        KitListRow(
                            icon: Self.icon(for: category),
                            tint: KitTheme.categoryColor(category),
                            title: transaction.merchant ?? category,
                            subtitle: "\(category) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))",
                            value: "\(income ? "+" : "−")\(Money.amount(transaction.amount)) \(transaction.currency)",
                            valueColor: income ? KitTheme.income : KitTheme.expense
                        )
                    }
                }
            }
        }
    }

    /// Rough category → SF Symbol mapping for record tiles.
    static func icon(for category: String) -> String {
        let key = category.lowercased()
        switch true {
        case key.contains("food"), key.contains("grocery"), key.contains("market"): return "cart.fill"
        case key.contains("restaurant"), key.contains("cafe"), key.contains("coffee"): return "cup.and.saucer.fill"
        case key.contains("transport"), key.contains("car"), key.contains("fuel"): return "car.fill"
        case key.contains("shop"): return "bag.fill"
        case key.contains("health"), key.contains("pharm"), key.contains("doctor"): return "cross.case.fill"
        case key.contains("salary"), key.contains("income"): return "banknote.fill"
        case key.contains("home"), key.contains("rent"), key.contains("house"): return "house.fill"
        case key.contains("bill"), key.contains("utilit"): return "bolt.fill"
        case key.contains("travel"), key.contains("vacation"): return "airplane"
        default: return "doc.text.fill"
        }
    }
}

// MARK: - HomeArrangeSheet
// Drag-to-reorder editor for the Home widgets; order persists via the bound
// CSV string (same mechanism the old dashboard used).
struct HomeArrangeSheet: View {
    @Binding var orderRaw: String
    @Environment(\.dismiss) private var dismiss

    private var widgets: [WalletView.HomeWidget] {
        var seen = orderRaw.split(separator: ",").compactMap { WalletView.HomeWidget(rawValue: String($0)) }
        for widget in WalletView.HomeWidget.allCases where !seen.contains(widget) { seen.append(widget) }
        return seen
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(widgets) { widget in
                    Label(widget.title, systemImage: "line.3.horizontal")
                }
                .onMove { from, to in
                    var current = widgets
                    current.move(fromOffsets: from, toOffset: to)
                    orderRaw = current.map(\.rawValue).joined(separator: ",")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - HomeViewModel
// Dashboard numbers for the Home cards: net worth, this-month budget (spent /
// total, percent, honest daily allowance = remaining ÷ days left), per-account
// wallets, and the spending donut + pills. Reuses the same services as
// DashboardSection so numbers agree across screens.
@MainActor
final class HomeViewModel: ObservableObject {
    struct CategoryPill: Identifiable {
        let id = UUID()
        let name: String
        /// This category's fraction of the month's gross spending (0...1) —
        /// drives the expanded-donut share bars. Display geometry only.
        var share: Double = 0
        let amountText: String
        let color: Color
    }
    struct Wallet: Identifiable {
        let id: Int64
        let name: String
        let typeLabel: String
        let balanceText: String
        let color: Color
        let icon: String
    }

    /// The manually-set monthly budget, stored as a grouped string.
    static let budgetKey = "monthlyBudget"

    /// "July budget" on a calendar cycle, or "Budget · resets 25 Jul" once the
    /// user anchors the cycle to a pay day.
    static func budgetTitle(for cycle: DateInterval) -> String {
        guard BudgetCycle.startDay != 1 else {
            return "\(Date().formatted(.dateTime.month(.wide))) budget"
        }
        return "Budget · resets \(cycle.end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    @Published var totalBalanceText = "—"
    @Published var monthName = ""
    @Published var budgetTitle = "Budget"
    @Published var hasMonthBudget = false
    @Published var budgetConsumedText = "—"   // net spending (expenses − money in)
    @Published var monthlyBudgetText = "—"     // the manual budget cap
    @Published var budgetPercent = 0
    @Published var dailyBudgetText = "—"
    @Published var daysLeftText = ""
    @Published var wallets: [Wallet] = []
    @Published var expenseTotalText = "—"      // GROSS total spent this month
    @Published var donut: [DonutRing.Segment] = []
    @Published var categoryPills: [CategoryPill] = []

    // Month-over-month spending insight (celebrates a drop, flags a rise).
    @Published var showWellDone = false
    @Published var wellDoneTitle = ""
    @Published var wellDoneText = ""
    @Published var savedText = "—"
    @Published var wellDoneRingLabel = "saved"
    @Published var wellDonePositive = true
    @Published var wellDoneFraction = 0.0

    private let allocation = SalaryAllocationService()

    func load() {
        monthName = Date().formatted(.dateTime.month(.wide))
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()

            // Net worth + per-account wallets.
            let (total, accounts) = try dbQueue.read { db -> (Decimal, [Account]) in
                let converter = try CurrencyConverter(db: db)
                let accounts = try Account.order(GRDB.Column("name")).fetchAll(db)
                let sum = accounts.reduce(Decimal(0)) { $0 + converter.toEGP($1.balance, from: $1.currency) }
                return (sum, accounts)
            }
            totalBalanceText = Self.money(total)
            wallets = accounts.compactMap { account in
                guard let id = account.id else { return nil }
                let type = AccountType(rawValue: account.type)
                return Wallet(
                    id: id,
                    name: account.name,
                    typeLabel: type?.displayName ?? account.type,
                    balanceText: account.currency == "EGP"
                        ? Money.egp(account.balance)
                        : Money.amount(account.balance) + " \(account.currency)",
                    color: Self.walletColor(type),
                    icon: Self.walletIcon(type)
                )
            }

            // Donut + pills + centre: GROSS spending this month (where money
            // actually went — no income netting), so the centre reads as
            // "total spent", not "what's left".
            // Donut follows the budget cycle so its centre "Expense" total
            // lines up with the budget card on the same screen.
            let gross = try grossExpensesByCategory(in: BudgetCycle.currentWindow())
            expenseTotalText = Self.money(gross.total)
            categoryPills = gross.byCategory.map {
                CategoryPill(name: $0.name,
                             share: gross.total > 0
                                 ? NSDecimalNumber(decimal: $0.amount / gross.total).doubleValue
                                 : 0,
                             amountText: Self.money($0.amount),
                             color: KitTheme.categoryColor($0.name))
            }
            donut = gross.byCategory.prefix(6).map {
                DonutRing.Segment(value: NSDecimalNumber(decimal: $0.amount).doubleValue,
                                  color: KitTheme.categoryColor($0.name))
            }

            // Budget bar: discretionary spend against the manual cap, over the
            // current budget CYCLE (calendar month by default, or the user's
            // pay-day-anchored window). budgetConsumed (not totalSpent) so
            // salary income doesn't zero out the bar.
            let cycle = BudgetCycle.currentWindow()
            budgetTitle = Self.budgetTitle(for: cycle)
            let netConsumed = max(0, try allocation.budgetConsumed(in: cycle))
            budgetConsumedText = Self.money(netConsumed)
            let budget = UserDefaults.standard.string(forKey: Self.budgetKey).flatMap { AmountFormat.decimal($0) } ?? 0
            if budget > 0 {
                hasMonthBudget = true
                monthlyBudgetText = Self.money(budget)
                let fraction = NSDecimalNumber(decimal: netConsumed / budget).doubleValue
                budgetPercent = max(0, min(999, Int((fraction * 100).rounded())))

                let daysLeft = BudgetCycle.daysLeft()
                let remaining = max(0, budget - netConsumed)
                dailyBudgetText = Self.money(remaining / Decimal(daysLeft)) + "/day"
                daysLeftText = "\(daysLeft) days left"
                publishWidgetSnapshot(remaining: remaining, usedFraction: fraction)
            } else {
                hasMonthBudget = false
                publishWidgetSnapshot(remaining: 0, usedFraction: 0)
            }

            // Month-over-month spending insight — shown ONLY when it means
            // something: a real move (≥10%) against a comparable last month.
            // A flat month or a first month with no baseline shows nothing.
            // Calendar month-over-month (not the cycle) so the trend compares
            // two equal, complete periods rather than a partial cycle.
            let thisMonthTotal = try grossExpensesByCategory(for: Date()).total
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let lastGross = try grossExpensesByCategory(for: lastMonth).total
            if lastGross > 0 {
                if thisMonthTotal <= lastGross {
                    let saved = lastGross - thisMonthTotal
                    let ratio = NSDecimalNumber(decimal: saved / lastGross).doubleValue
                    showWellDone = ratio >= 0.1
                    wellDoneTitle = "Well done!"
                    wellDonePositive = true
                    wellDoneText = "Your spending is down \(Int((ratio * 100).rounded()))% from last month."
                    savedText = Self.money(saved)
                    wellDoneRingLabel = "saved"
                    wellDoneFraction = min(1, max(0, ratio))
                } else {
                    let over = thisMonthTotal - lastGross
                    let ratio = NSDecimalNumber(decimal: over / lastGross).doubleValue
                    showWellDone = ratio >= 0.1
                    wellDoneTitle = "Spending up"
                    wellDonePositive = false
                    wellDoneText = "Your spending is up \(Int((ratio * 100).rounded()))% from last month."
                    savedText = Self.money(over)
                    wellDoneRingLabel = "more"
                    wellDoneFraction = min(1, max(0, ratio))
                }
            } else {
                showWellDone = false
            }
        } catch {
            totalBalanceText = "—"
        }
    }

    /// Gross income and expense (EGP) in a date range, transfers excluded.
    /// Static + public within the app so InsightsViewModel uses the SAME
    /// definition — the income/spending numbers can never disagree between
    /// Home and Insights.
    static func sumFlow(start: Date, end: Date, db: GRDB.Database, converter: CurrencyConverter) throws -> (income: Decimal, expense: Decimal) {
        let rows = try Row.fetchAll(db, sql: """
            SELECT direction, currency, GROUP_CONCAT(t.amount, '|') AS amounts
            FROM "transaction" t
            LEFT JOIN category c ON c.id = t.categoryId
            WHERE t.date >= ? AND t.date < ? AND (c.name IS NULL OR c.name <> 'Transfer')
            GROUP BY direction, currency
            """, arguments: [start, end])
        var income = Decimal(0), expense = Decimal(0)
        for row in rows {
            let direction: String = row["direction"] ?? "expense"
            let currency: String = row["currency"] ?? "EGP"
            let amounts: String = row["amounts"] ?? ""
            let sum = amounts.split(separator: "|")
                .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                .reduce(Decimal(0), +)
            let egp = converter.toEGP(sum, from: currency)
            if direction == "income" { income += egp } else { expense += egp }
        }
        return (income, expense)
    }

    /// Gross expenses (no income netting) grouped by category for the month,
    /// plus the grand total — the "where money went" figures for the donut.
    private func grossExpensesByCategory(for month: Date) throws -> (total: Decimal, byCategory: [(name: String, amount: Decimal)]) {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return (0, []) }
        return try grossExpensesByCategory(in: interval)
    }

    /// Same gross-by-category breakdown over an arbitrary window — the Home
    /// donut uses the budget cycle so its "Expense" total matches the budget
    /// card; the month-over-month card keeps calendar months for a fair trend.
    private func grossExpensesByCategory(in interval: DateInterval) throws -> (total: Decimal, byCategory: [(name: String, amount: Decimal)]) {
        let dbQueue = try DatabaseManager.shared.dbQueue()
        return try dbQueue.read { db in
            let converter = try CurrencyConverter(db: db)
            let names = Dictionary(uniqueKeysWithValues: try Persistence.Category.fetchAll(db)
                .compactMap { category in category.id.map { ($0, category.name) } })
            let rows = try Row.fetchAll(db, sql: """
                SELECT categoryId, currency, GROUP_CONCAT(amount, '|') AS amounts
                FROM "transaction"
                WHERE date >= ? AND date < ? AND direction = 'expense'
                GROUP BY categoryId, currency
                """, arguments: [interval.start, interval.end])
            var byId: [Int64: Decimal] = [:]
            for row in rows {
                guard let categoryId: Int64 = row["categoryId"] else { continue }
                let currency: String = row["currency"] ?? "EGP"
                let amounts: String = row["amounts"] ?? ""
                let sum = amounts.split(separator: "|")
                    .compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
                    .reduce(Decimal(0), +)
                byId[categoryId, default: 0] += converter.toEGP(sum, from: currency)
            }
            // Exclude transfers — moving money between your own accounts is
            // not spending, so it must not appear in the "where money went"
            // donut or its centre total.
            let list = byId
                .compactMap { id, amount -> (name: String, amount: Decimal)? in
                    guard amount > 0, let name = names[id],
                          name.lowercased() != "transfer" else { return nil }
                    return (name, amount)
                }
                .sorted { $0.amount > $1.amount }
            let total = list.reduce(Decimal(0)) { $0 + $1.amount }
            return (total, list)
        }
    }

    static func walletColor(_ type: AccountType?) -> Color {
        switch type {
        case .cash: return Color(hexValue: 0x66FFA3)
        case .bank: return Color(hexValue: 0x3DB9FF)
        case .debitCard: return KitTheme.primary
        case .creditCard: return Color(hexValue: 0xB388FF)
        case .none: return Color(hexValue: 0x3DB9FF)
        }
    }

    static func walletIcon(_ type: AccountType?) -> String {
        switch type {
        case .cash: return "banknote.fill"
        case .bank: return "building.columns.fill"
        case .debitCard, .creditCard: return "creditcard.fill"
        case .none: return "wallet.pass.fill"
        }
    }

    /// Grouped EGP display string (2 decimals) via the shared formatter.
    static func money(_ value: Decimal) -> String { Money.egp(value) }

    /// Refreshes the Home/Lock Screen widgets. Delegates to the shared
    /// publisher (which recomputes from the DB) so the same snapshot logic
    /// runs from every trigger — dashboard load, any capture, background.
    private func publishWidgetSnapshot(remaining: Decimal, usedFraction: Double) {
        WidgetSnapshotPublisher.refresh()
    }
}

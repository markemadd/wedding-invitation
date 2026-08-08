import SwiftUI
import GRDB
import Budgeting
import Persistence
import UI

// MARK: - BucketsView (ENHANCEMENTS Wave B3, formerly BudgetView)
// Income + percentage allocation editor (the Save button stays disabled
// until the running total hits EXACTLY 100%, with a live "N% left to
// allocate" indicator — the blueprint's rule), now also the entry point to
// the planning screen (goals, wishlist, debts, sinking funds) that used to
// be its own Plan tab.
struct BucketsView: View {
    @StateObject private var model = BudgetViewModel()
    /// Budgets list shows the 3 most at-risk rings; the rest fold behind
    /// "See all".
    @State private var showAllBudgets = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    planLink
                    incomeCard
                    budgetCard
                    budgetsSection
                    allocationsCard
                    suggestButton
                    saveButton
                }
                .padding(15)
                .padding(.bottom, TabBarLayout.clearance)
            }
            .kitBackground()
            .dismissableKeyboard()
            .navigationTitle("Buckets")
            .task { model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .mizanDataDidChange)) { _ in
                model.loadBudgetItems()
            }
            .alert("Budget", isPresented: .constant(model.message != nil)) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }
    }

    // MARK: Budget graphs (per-category state donuts)

    @ViewBuilder
    private var budgetsSection: some View {
        if !model.budgetItems.isEmpty {
            // Worst first (over-budget → at-risk → within), so the three
            // visible rings are always the ones that need attention.
            let sorted = model.budgetItems.sorted { $0.rawFraction > $1.rawFraction }
            let visible = showAllBudgets ? sorted : Array(sorted.prefix(3))
            VStack(spacing: 12) {
                KitSectionHeader("Budgets")
                ForEach(visible) { item in budgetItemCard(item) }
                if sorted.count > 3 {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showAllBudgets.toggle()
                        }
                    } label: {
                        Text(showAllBudgets ? "Show less" : "See all (\(sorted.count))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KitTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func budgetItemCard(_ item: BudgetViewModel.BudgetItem) -> some View {
        KitCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                        Text("Monthly spending limit")
                            .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                        Text("Spend: \(item.spentText) / \(item.limitText)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack {
                        Circle().stroke(item.color.opacity(0.15), lineWidth: 12)
                        Circle().trim(from: 0, to: item.fraction)
                            .stroke(item.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 92, height: 92)
                }
                HStack(spacing: 18) {
                    budgetLegend(KitTheme.primary, "Within")
                    budgetLegend(Color(hexValue: 0xFF9466), "Risk")
                    budgetLegend(Color(hexValue: 0x3DB9FF), "Overspending")
                }
            }
        }
    }

    private func budgetLegend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 14, height: 14)
            Text(label).font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
        }
    }

    private var planLink: some View {
        NavigationLink { PlanDetailView() } label: {
            KitCard(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "target").font(.title2).foregroundStyle(KitTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                        Text("Goals, wishlist, debts, and sinking funds")
                            .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var incomeCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly income")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AmountTextField(text: $model.incomeText,
                                    font: .system(size: 26, weight: .bold).monospacedDigit(),
                                    color: KitTheme.textPrimary)
                    Text("EGP").font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
    }

    private var budgetCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly budget")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AmountTextField(text: $model.budgetText,
                                    font: .system(size: 26, weight: .bold).monospacedDigit(),
                                    color: KitTheme.primary)
                    Text("EGP").font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                }
                Text("What you allow yourself to spend this month. Expenses count against it; incoming transfers (e.g. InstaPay) add back to it. Shown on Home.")
                    .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
            }
        }
    }

    private var allocationsCard: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Allocations").font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    Text(model.remainingLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(remainingColor)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(remainingColor.opacity(0.12), in: Capsule())
                }
                // Choose how to allocate: by percentage of income, or by
                // actual EGP amounts. Switching converts your current values.
                Picker("Mode", selection: Binding(
                    get: { model.amountMode },
                    set: { model.amountMode = $0 }
                )) {
                    Text("Percent").tag(false)
                    Text("Amount").tag(true)
                }
                .pickerStyle(.segmented)
                if model.categories.isEmpty {
                    Text("No categories yet — add some in Settings.")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.categories.enumerated()), id: \.element.id) { index, category in
                            HStack(spacing: 12) {
                                Circle().fill(KitTheme.categoryColor(category.name)).frame(width: 12, height: 12)
                                Text(category.name)
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                                Spacer()
                                if model.amountMode {
                                    TextField("0", text: model.amountBinding(for: category.id ?? -1))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(KitTheme.textPrimary)
                                        .frame(width: 90)
                                    Text("EGP").font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                                } else {
                                    TextField("0", text: model.percentBinding(for: category.id ?? -1))
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(KitTheme.textPrimary)
                                        .frame(width: 52)
                                    Text("%").font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                                }
                            }
                            .padding(.vertical, 11)
                            if index < model.categories.count - 1 {
                                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var remainingColor: Color {
        if model.amountMode {
            return model.remainingAmount == 0 ? KitTheme.primary
                : (model.remainingAmount < 0 ? KitTheme.expense : KitTheme.textSecondary)
        }
        return model.remainingPercent == 0 ? KitTheme.primary
            : (model.remainingPercent < 0 ? KitTheme.expense : KitTheme.textSecondary)
    }

    private var suggestButton: some View {
        Button { model.suggestFromSpending() } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("Suggest from my spending")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(KitTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(KitTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        KitPrimaryButton("Save budget") { model.save() }
            .disabled(!model.canSave)
            .opacity(model.canSave ? 1 : 0.4)
    }
}

@MainActor
final class BudgetViewModel: ObservableObject {
    @Published var incomeText = ""
    /// The manual monthly budget (separate from income). Persisted to
    /// UserDefaults and read by the Home widget; posting on change keeps Home
    /// in sync. Guarded so a no-op set doesn't churn.
    @Published var budgetText = "" {
        didSet {
            guard oldValue != budgetText else { return }
            UserDefaults.standard.set(budgetText, forKey: HomeViewModel.budgetKey)
            NotificationCenter.default.post(name: .mizanDataDidChange, object: nil)
        }
    }
    @Published var categories: [Persistence.Category] = []
    /// categoryId → whole-percent text ("30"). Whole percents keep the
    /// exactly-100 rule intuitive on a phone keyboard; the service stores
    /// exact fractions (30 → 0.30).
    @Published var percentTexts: [Int64: String] = [:]
    /// categoryId → EGP amount text, used when the user prefers to allocate
    /// by money instead of percent. Converted to fractions on save.
    @Published var amountTexts: [Int64: String] = [:]
    /// false = allocate by percent (sum to 100%); true = allocate by amount
    /// (sum to income). Switching converts the current values across.
    @Published var amountMode = false {
        didSet {
            guard oldValue != amountMode else { return }
            amountMode ? fillAmountsFromPercents() : fillPercentsFromAmounts()
        }
    }
    @Published var message: String?
    /// Per-category budget cards (allocated vs spent, with a state).
    @Published var budgetItems: [BudgetItem] = []

    struct BudgetItem: Identifiable {
        let id = UUID()
        let name: String
        let spentText: String
        let limitText: String
        let fraction: Double
        /// Unclamped spent/limit — sorts over-budget (>1) ahead of the rest
        /// even though the ring itself clamps at 1.
        let rawFraction: Double
        let color: Color
        let stateLabel: String
    }

    private let service = SalaryAllocationService()

    /// Build the budget cards from this month's allocation summaries. Within
    /// (<80%) green · Risk (80–100%) orange · Overspending (>100%) blue.
    func loadBudgetItems() {
        // Same budget cycle as the Home card + widget (calendar month by
        // default, or the user's pay-day window).
        let summaries = (try? service.monthlySummary(in: BudgetCycle.currentWindow())) ?? []
        budgetItems = summaries.filter { $0.allocated > 0 }.map { summary in
            let spent = max(0, summary.spent)
            let fraction = NSDecimalNumber(decimal: spent / summary.allocated).doubleValue
            let color: Color
            let label: String
            if fraction > 1 { color = Color(hexValue: 0x3DB9FF); label = "Overspending" }
            else if fraction >= 0.8 { color = Color(hexValue: 0xFF9466); label = "Risk" }
            else { color = KitTheme.primary; label = "Within" }
            return BudgetItem(name: summary.category.name,
                              spentText: Money.egp(spent),
                              limitText: Money.egp(summary.allocated),
                              fraction: min(1, max(0, fraction)),
                              rawFraction: fraction,
                              color: color, stateLabel: label)
        }
    }

    private var incomeDecimal: Decimal { AmountFormat.decimal(incomeText) ?? 0 }

    var totalPercent: Int {
        percentTexts.values.compactMap(Int.init).reduce(0, +)
    }
    var remainingPercent: Int { 100 - totalPercent }

    /// Total allocated in EGP (amount mode) and what's left against income.
    var allocatedAmount: Decimal {
        amountTexts.values.compactMap { AmountFormat.decimal($0) }.reduce(Decimal(0), +)
    }
    var remainingAmount: Decimal { incomeDecimal - allocatedAmount }

    var remainingLabel: String {
        if amountMode {
            if remainingAmount == 0 { return "Fully allocated" }
            return remainingAmount > 0
                ? "\(Money.egp(remainingAmount)) left to allocate"
                : "\(Money.egp(-remainingAmount)) over income"
        }
        return remainingPercent == 0 ? "Fully allocated — 100%"
            : remainingPercent > 0 ? "\(remainingPercent)% left to allocate"
            : "\(-remainingPercent)% over budget"
    }
    var canSave: Bool {
        guard incomeDecimal > 0 else { return false }
        return amountMode ? remainingAmount == 0 : remainingPercent == 0
    }

    func percentBinding(for categoryId: Int64) -> Binding<String> {
        Binding(
            get: { self.percentTexts[categoryId] ?? "" },
            set: { self.percentTexts[categoryId] = $0 }
        )
    }

    func amountBinding(for categoryId: Int64) -> Binding<String> {
        Binding(
            get: { self.amountTexts[categoryId] ?? "" },
            set: { self.amountTexts[categoryId] = $0 }
        )
    }

    /// amount = percent% × income (used when switching into amount mode).
    private func fillAmountsFromPercents() {
        let income = incomeDecimal
        guard income > 0 else { return }
        for category in categories {
            guard let id = category.id else { continue }
            let whole = Int(percentTexts[id] ?? "") ?? 0
            amountTexts[id] = whole > 0 ? AmountFormat.grouped(income * Decimal(whole) / 100) : ""
        }
    }

    /// percent = round(amount ÷ income × 100) (used when switching back).
    private func fillPercentsFromAmounts() {
        let income = incomeDecimal
        guard income > 0 else { return }
        for category in categories {
            guard let id = category.id else { continue }
            let amount = AmountFormat.decimal(amountTexts[id] ?? "") ?? 0
            let percent = NSDecimalNumber(decimal: amount / income * 100).intValue
            percentTexts[id] = percent > 0 ? "\(percent)" : ""
        }
    }

    func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            categories = try dbQueue.read { db in
                try Persistence.Category.order(GRDB.Column("name")).fetchAll(db)
            }
            let income = try service.currentIncome()?.amount ?? 0
            if income > 0 { incomeText = AmountFormat.grouped(income) }
            budgetText = UserDefaults.standard.string(forKey: HomeViewModel.budgetKey) ?? ""
            for allocation in try service.currentAllocations() {
                // Percent field: rounded whole percent (amount-mode saves can
                // store non-round fractions). Amount field: fraction × income.
                let percent = NSDecimalNumber(decimal: allocation.percentage * 100).intValue
                percentTexts[allocation.categoryId] = "\(percent)"
                if income > 0 {
                    amountTexts[allocation.categoryId] = AmountFormat.grouped(income * allocation.percentage)
                }
            }
            loadBudgetItems()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Converts trailing-3-month spend shares into whole percents that sum
    /// to exactly 100 (floor everything, hand leftover points to the
    /// biggest categories) and fills the fields FOR REVIEW — the user
    /// still edits and saves; the app proposes, never imposes.
    func suggestFromSpending() {
        do {
            let shares = try service.categorySpendShares(trailingMonths: 3)
            guard !shares.isEmpty else {
                message = "Not enough spending history yet — capture a few weeks first."
                return
            }
            var whole: [Int64: Int] = shares.mapValues {
                Int(truncating: NSDecimalNumber(decimal: $0 * 100))
            }
            var leftover = 100 - whole.values.reduce(0, +)
            for categoryId in shares.sorted(by: { $0.value > $1.value }).map(\.key) {
                guard leftover > 0 else { break }
                whole[categoryId, default: 0] += 1
                leftover -= 1
            }
            percentTexts = whole.filter { $0.value > 0 }.mapValues { "\($0)" }
            message = "Suggested from your last 3 months — adjust anything, then Save."
        } catch {
            message = error.localizedDescription
        }
    }

    func save() {
        do {
            guard let income = AmountFormat.decimal(incomeText), income > 0 else {
                message = "Enter a valid income."
                return
            }
            try service.setIncome(amount: income, currency: "EGP")
            let allocations: [CategoryAllocation]
            if amountMode {
                // Exact fraction = amount ÷ income; since the amounts sum to
                // income (enforced by canSave), the fractions sum to 1.0.
                allocations = amountTexts.compactMap { categoryId, text in
                    guard let amount = AmountFormat.decimal(text), amount > 0 else { return nil }
                    return CategoryAllocation(categoryId: categoryId, percentage: amount / income)
                }
            } else {
                allocations = percentTexts.compactMap { categoryId, text in
                    guard let whole = Int(text), whole > 0 else { return nil }
                    return CategoryAllocation(categoryId: categoryId, percentage: Decimal(whole) / 100)
                }
            }
            try service.setAllocations(allocations)
            message = "Budget saved."
        } catch {
            message = error.localizedDescription
        }
    }
}

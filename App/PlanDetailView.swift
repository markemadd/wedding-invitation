import SwiftUI
import GRDB
import Budgeting
import SavingsAndGoals
import Persistence
import UI

// MARK: - PlanDetailView (ENHANCEMENTS Wave B3, formerly PlanView)
// The proactive planning screen: recurring-series suggestions (confirm,
// never auto-added), upcoming bills, goals with cut suggestions, wishlist
// with the dual time-to-save framing, debts, and sinking funds. No longer
// a tab — reached via a NavigationLink from BucketsView.
struct PlanDetailView: View {
    @StateObject private var model = PlanViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    if !model.candidates.isEmpty { recurringSection }
                    if !model.creepAlerts.isEmpty { creepSection }
                    if !model.bills.isEmpty { billsSection }
                    forecastSection
                    goalsSection
                    wishlistSection
                    debtsSection
                    fundsSection
                    linksSection
                }
                .padding(15)
                .padding(.bottom, TabBarLayout.clearance)
            }
            .kitBackground()
            .dismissableKeyboard()
            .navigationTitle("Plan")
            .task { model.load() }
            .refreshable { model.load() }
            .alert("Contribute to \(model.contributePrompt?.name ?? "")",
                   isPresented: .constant(model.contributePrompt != nil)) {
                TextField("Amount", text: $model.contributeAmount).keyboardType(.decimalPad)
                Button("Add") { model.contribute() }
                Button("Cancel", role: .cancel) { model.contributePrompt = nil }
            }
        }
    }

    /// Section header with an optional one-line "why this exists" — every
    /// planning tool explains itself instead of assuming finance literacy.
    private func planHeader(_ title: String, _ caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(KitTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recurringSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                planHeader("Looks recurring — add it?",
                           "Charges that repeat on a rhythm. Confirming one feeds the bills calendar and price-increase alerts — nothing is ever added without you.")
                ForEach(model.candidates) { candidate in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.merchant).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Text("every \(candidate.intervalDays) days · ~\(Money.egp(candidate.expectedAmount)) · \(Int(truncating: (candidate.confidence * 100) as NSNumber))% sure")
                                .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                        }
                        Spacer()
                        Button("Confirm") { model.confirm(candidate) }
                            .font(.system(size: 13, weight: .semibold)).tint(KitTheme.primary)
                    }
                }
            }
        }
    }

    private var creepSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                planHeader("Price increases")
                ForEach(model.creepAlerts) { alert in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.series.merchantPattern).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Text("Now \(Money.egp(alert.latestAmount)) — was \(Money.egp(alert.series.expectedAmount)) (+\(alert.increasePercent)%)")
                                .font(.system(size: 12)).foregroundStyle(KitTheme.expense)
                        }
                        Spacer()
                        Button("Accept") { model.acceptNewPrice(alert) }
                            .font(.system(size: 13, weight: .semibold)).tint(KitTheme.primary)
                    }
                }
            }
        }
    }

    private var billsSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 12) {
                planHeader("Upcoming bills",
                           "What's due soon, predicted from your confirmed recurring charges — so month-end never surprises you.")
                ForEach(model.bills) { bill in
                    HStack {
                        Text(bill.series.merchantPattern).font(.system(size: 14)).foregroundStyle(KitTheme.textPrimary)
                        Spacer()
                        Text(bill.nextExpectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 13)).foregroundStyle(KitTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var forecastSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 6) {
                planHeader("Net worth in 2 years")
                if let forecast = model.forecast {
                    // Percentile bands, never a single confident number.
                    Text("Median: \(Money.egp(forecast.p50))")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Text("Range: \(Money.egp(forecast.p10)) – \(Money.egp(forecast.p90)) (10th–90th percentile)")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                    Text(model.forecastAssumption ?? "")
                        .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                } else {
                    Text("Needs at least 2 months with recorded transactions to simulate — keep capturing.")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
    }

    private var goalsSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                planHeader("Goals",
                           "A target amount by a date. Mizan works out the monthly saving it needs, compares that to what you actually save, and suggests specific category cuts to close any gap.")
                ForEach(model.plans, id: \.goal.id) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(plan.goal.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Text("\(Money.egp(plan.goal.targetAmount)) · \(plan.monthsRemaining) mo")
                                .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                            Button { model.deleteGoal(plan.goal) } label: {
                                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(KitTheme.expense)
                            }
                        }
                        Text("Need \(Money.egp(plan.requiredMonthlySavings))/mo · saving \(Money.egp(plan.currentAverageSavings))/mo")
                            .font(.system(size: 12))
                            .foregroundStyle(plan.monthlyGap > 0 ? KitTheme.expense : KitTheme.primary)
                        if plan.monthlyGap > 0 {
                            ForEach(plan.suggestedCuts.prefix(3)) { cut in
                                Text("• Cut \(cut.category.name) by \(Money.egp(cut.suggestedReduction)) (now \(Money.egp(cut.currentMonthlySpend)))")
                                    .font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                            }
                        }
                        Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                    }
                }
                NavigationLink { NewGoalView(model: model) } label: {
                    Label("New goal", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.primary)
                }
            }
        }
    }

    private var wishlistSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                planHeader("Wishlist",
                           "Things you want but haven't bought. Each shows its true cost two ways: months of saving at your real rate, and the working days of your life the price equals.")
                ForEach(model.wishlist, id: \.item.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.item.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Text(Money.egp(entry.item.price)).font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                            Button { model.deleteWishlistItem(entry.item) } label: {
                                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(KitTheme.expense)
                            }
                        }
                        Text(entry.monthsBySavingsRate.map { "\($0) months at your savings rate" } ?? "not saving currently")
                            .font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                        Text("≈ \(Self.lifeEnergyDays(entry.daysOfLifeEnergy)) working days of your life")
                            .font(.system(size: 11)).foregroundStyle(AppTheme.accentCream)
                        Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                    }
                }
                HStack(spacing: 10) {
                    TextField("Item", text: $model.newWishName).foregroundStyle(KitTheme.textPrimary)
                    TextField("Price", text: $model.newWishPrice)
                        .keyboardType(.decimalPad).foregroundStyle(KitTheme.textPrimary).frame(width: 80)
                    Button("Add") { model.addWishlistItem() }
                        .font(.system(size: 14, weight: .semibold)).tint(KitTheme.primary)
                        .disabled(model.newWishName.isEmpty || Decimal(string: model.newWishPrice) == nil)
                }
                .font(.system(size: 14))
            }
        }
    }

    private var debtsSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                planHeader("Debts",
                           "Loans and card debt with real amortization. Tap one to see each month's interest vs principal and exactly when you'll be free of it.")
                ForEach(model.debts) { debt in
                    HStack {
                        NavigationLink { DebtScheduleView(debt: debt) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                                    Text("\(Money.egp(debt.principal)) @ \(debt.interestRate)% · \(debt.termMonths) mo")
                                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Button { model.deleteDebt(debt) } label: {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(KitTheme.expense)
                        }
                        .padding(.leading, 8)
                    }
                }
                NavigationLink { NewDebtView(model: model) } label: {
                    Label("New debt", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.primary)
                }
            }
        }
    }

    private var fundsSection: some View {
        KitCard {
            VStack(alignment: .leading, spacing: 14) {
                planHeader("Sinking funds",
                           "Put a little aside every month for expenses you KNOW are coming — car service, Eid, school fees — so they never ambush a single month's budget.")
                ForEach(model.funds) { fund in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(fund.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Button("+ Add") { model.contributePrompt = fund }
                                .font(.system(size: 13, weight: .semibold)).tint(KitTheme.primary)
                        }
                        KitProgressBar(fraction: model.fundProgress(fund))
                        let by = fund.targetDate.formatted(date: .abbreviated, time: .omitted)
                        Text("\(Money.egp(fund.currentAmount)) of \(Money.egp(fund.targetAmount)) · need \(Money.egp(model.fundMonthly(fund)))/mo by \(by)")
                            .font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                    }
                }
                NavigationLink { NewFundView(model: model) } label: {
                    Label("New sinking fund", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.primary)
                }
            }
        }
    }

    private var linksSection: some View {
        KitCard {
            VStack(spacing: 0) {
                planLink("Bills calendar", "calendar") { BillsCalendarView() }
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                planLink("Investments", "chart.line.uptrend.xyaxis") { InvestView() }
                Rectangle().fill(KitTheme.ink.opacity(0.06)).frame(height: 0.5)
                planLink("Item prices", "basket") { ItemPriceHistoryView() }
            }
        }
    }

    /// "12.5" — one decimal, since raw Decimal division prints dozens of
    /// digits ("12.34782608…"), which is what made this number unreadable.
    static func lifeEnergyDays(_ value: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: value).rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 1, raiseOnExactness: false,
            raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
        return "\(rounded)"
    }

    private func planLink<Destination: View>(_ title: String, _ icon: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(KitTheme.primary).frame(width: 24)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small creation forms

struct NewGoalView: View {
    @ObservedObject var model: PlanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var date = Calendar.current.date(byAdding: .month, value: 12, to: Date())!
    @State private var scope: GoalCutScope = .flexibleOnly

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Target amount (EGP)", text: $amount).keyboardType(.decimalPad)
            DatePicker("Target date", selection: $date, displayedComponents: .date)
            Picker("Cut scope", selection: $scope) {
                Text("Flexible categories only").tag(GoalCutScope.flexibleOnly)
                Text("Any category").tag(GoalCutScope.anyCategory)
            }
            Button("Create") {
                model.addGoal(name: name, amount: amount, date: date, scope: scope)
                dismiss()
            }
            .disabled(name.isEmpty || Decimal(string: amount) == nil)
        }
        .navigationTitle("New goal")
    }
}

struct NewDebtView: View {
    @ObservedObject var model: PlanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var principal = ""
    @State private var rate = ""
    @State private var months = ""

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Principal (EGP)", text: $principal).keyboardType(.decimalPad)
            TextField("Annual rate %", text: $rate).keyboardType(.decimalPad)
            TextField("Term (months)", text: $months).keyboardType(.numberPad)
            Button("Create") {
                model.addDebt(name: name, principal: principal, rate: rate, months: months)
                dismiss()
            }
            .disabled(name.isEmpty || Decimal(string: principal) == nil || Decimal(string: rate) == nil || Int(months) == nil)
        }
        .navigationTitle("New debt")
    }
}

struct NewFundView: View {
    @ObservedObject var model: PlanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var date = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Target amount (EGP)", text: $amount).keyboardType(.decimalPad)
            DatePicker("Needed by", selection: $date, displayedComponents: .date)
            Button("Create") {
                model.addFund(name: name, amount: amount, date: date)
                dismiss()
            }
            .disabled(name.isEmpty || Decimal(string: amount) == nil)
        }
        .navigationTitle("New sinking fund")
    }
}

struct DebtScheduleView: View {
    let debt: Debt

    var body: some View {
        let schedule = AmortizationCalculator().fullSchedule(
            principal: debt.principal, annualRate: debt.interestRate, termMonths: debt.termMonths
        )
        List {
            Section("Monthly payment: \(schedule.first?.payment ?? 0) EGP") {
                ForEach(schedule) { entry in
                    HStack {
                        Text("Mo \(entry.month)")
                        Spacer()
                        Text("principal \(entry.principalPortion) · interest \(entry.interestPortion)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(entry.remainingBalance)")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(debt.name)
    }
}

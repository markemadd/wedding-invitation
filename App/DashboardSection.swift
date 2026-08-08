import SwiftUI
import GRDB
import Budgeting
import Persistence
import UI

// MARK: - DashboardSection (blueprint Phases 3.2 + 3.6)
// The "big number" moment: net worth in the radial gauge (accounts summed
// through the FX table), this month's allocated/spent per category, the
// top-3 spending cards, and a cash-flow Sankey (the 6-month trend lives on
// the Insights tab).
struct DashboardSection: View {
    @StateObject private var model = DashboardViewModel()
    /// Drag-to-arrange (roadmap Should-have): widget order persists as a
    /// CSV of raw values; reordered in the Arrange sheet (long-press a
    /// widget or use the button below the widgets).
    @AppStorage("dashboardWidgetOrder") private var orderRaw = "netWorth,month,sankey"
    @State private var showArrange = false
    @State private var showNetWorthDetail = false

    // The 6-month trend moved to the Insights tab; a stale "trend" token in a
    // saved order string is simply ignored (Widget(rawValue:) returns nil).
    enum Widget: String, CaseIterable, Identifiable {
        case netWorth, month, sankey
        var id: String { rawValue }
        var title: String {
            switch self {
            case .netWorth: return "Net worth gauge"
            case .month: return "Top spending"
            case .sankey: return "Cash-flow (Sankey)"
            }
        }
    }

    private var order: [Widget] {
        var seen = orderRaw.split(separator: ",").compactMap { Widget(rawValue: String($0)) }
        for widget in Widget.allCases where !seen.contains(widget) { seen.append(widget) }
        return seen
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(order) { widget in
                widgetView(widget)
                    .contextMenu {
                        Button { showArrange = true } label: {
                            Label("Arrange widgets…", systemImage: "arrow.up.arrow.down")
                        }
                    }
            }
            Button { showArrange = true } label: {
                Label("Arrange", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
            }
            .tint(.secondary)
        }
        .sheet(isPresented: $showArrange) {
            ArrangeWidgetsSheet(orderRaw: $orderRaw)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNetWorthDetail) {
            NetWorthDetailSheet(
                netWorthText: model.netWorthText,
                spendable: model.spendableText,
                debt: model.debtText,
                history: model.netWorthHistory
            )
            .presentationDetents([.medium, .large])
        }
        .task { model.load() }
        // Live refresh: any transaction change (capture, edit, queue
        // import) re-computes the gauge and cards — the fix for "the
        // gauge doesn't update automatically".
        .onReceive(NotificationCenter.default.publisher(for: .mizanDataDidChange)) { _ in
            model.load()
        }
    }

    @ViewBuilder
    private func widgetView(_ widget: Widget) -> some View {
        switch widget {
        case .netWorth: netWorthCard
        case .month: if !model.summaries.isEmpty { monthCard }
        case .sankey: if model.sankeyIncome > 0 { sankeyCard }
        }
    }

    private var sankeyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where the money flows — this month")
                    .font(.headline)
                SankeyView(income: model.sankeyIncome, flows: model.sankeyFlows)
                    .frame(height: CGFloat(30 * max(3, model.sankeyFlows.count)))
                Text("Mint = spending · cream = saved")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var netWorthCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                ZStack {
                    // Gauge shows this month's savings rate: how much of
                    // income hasn't been spent yet (1 = untouched income).
                    RadialGauge(progress: model.savingsRate)
                        .frame(width: 150, height: 150)
                    VStack {
                        Text("Net worth")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.netWorthText)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
                Text(model.monthLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Tap for breakdown")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { showNetWorthDetail = true }
        }
    }

    private var monthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top spending this month")
                    .font(.headline)
                ForEach(model.summaries.prefix(3)) { summary in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            CategoryChip(name: summary.category.name, size: 26)
                            Text(summary.category.name).font(.subheadline)
                            Spacer()
                            Text("\(summary.spent) / \(summary.allocated) EGP")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(summary.remaining < 0 ? .red : .secondary)
                        }
                        // Roadmap color language: mint on-track, cream
                        // approaching (≥80%), red over — now via the shared
                        // SegmentedProgressBar so every bar reads alike.
                        SegmentedProgressBar(fraction: model.usedFraction(summary))
                    }
                }
            }
        }
    }

}

// MARK: - ArrangeWidgetsSheet
// The drag-to-reorder editor: standard List drag handles, order persists
// via the bound CSV string.
struct ArrangeWidgetsSheet: View {
    @Binding var orderRaw: String
    @Environment(\.dismiss) private var dismiss

    private var widgets: [DashboardSection.Widget] {
        var seen = orderRaw.split(separator: ",")
            .compactMap { DashboardSection.Widget(rawValue: String($0)) }
        for widget in DashboardSection.Widget.allCases where !seen.contains(widget) { seen.append(widget) }
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

@MainActor
final class DashboardViewModel: ObservableObject {
    struct NetWorthPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double // Chart axis only — display geometry, not money math.
    }

    @Published var netWorthText = "—"
    /// Net-worth breakdown for the A5 detail sheet. Spendable = cash + bank
    /// + debit balances; debt = credit-card balances (this app's only
    /// liability account type). Shown as pre-formatted EGP strings.
    @Published var spendableText = "—"
    @Published var debtText = "—"
    @Published var netWorthHistory: [NetWorthPoint] = []
    @Published var savingsRate: Double = 0
    @Published var monthLine = ""
    @Published var summaries: [SalaryAllocationService.CategoryAllocationSummary] = []
    /// Sankey inputs (Double: display geometry, not money math).
    @Published var sankeyIncome: Double = 0
    @Published var sankeyFlows: [SankeyView.Flow] = []

    private let allocationService = SalaryAllocationService()

    func usedFraction(_ summary: SalaryAllocationService.CategoryAllocationSummary) -> Double {
        guard summary.allocated > 0 else { return 0 }
        return NSDecimalNumber(decimal: summary.spent / summary.allocated).doubleValue
    }

    /// Net-worth split for the A5 detail sheet: spendable = cash/bank/debit
    /// balances; debt = credit-card balances (this app's only liability
    /// account type).
    private struct NetWorthBreakdown {
        var total = Decimal(0)
        var spendable = Decimal(0)
        var debt = Decimal(0)
    }

    /// Loads the gauge number, the spendable/debt split, and the snapshot
    /// history in one place so `load()` stays readable. O(accounts).
    private func loadNetWorth(_ dbQueue: DatabaseQueue) throws {
        let breakdown = try dbQueue.read { db -> NetWorthBreakdown in
            let converter = try CurrencyConverter(db: db)
            var result = NetWorthBreakdown()
            for account in try Account.fetchAll(db) {
                let egp = converter.toEGP(account.balance, from: account.currency)
                result.total += egp
                if AccountType(rawValue: account.type) == .creditCard {
                    result.debt += egp
                } else {
                    result.spendable += egp
                }
            }
            return result
        }
        netWorthText = "\(breakdown.total) EGP"
        spendableText = "\(breakdown.spendable) EGP"
        debtText = "\(breakdown.debt) EGP"

        // Net-worth trend from frozen snapshots (already in DB) — a
        // historical line that doesn't shift as old transactions are edited,
        // sorted oldest→newest for the chart.
        netWorthHistory = try dbQueue.read { db in
            try NetWorthSnapshot.order(GRDB.Column("date")).fetchAll(db).map {
                NetWorthPoint(date: $0.date, value: NSDecimalNumber(decimal: $0.netWorth).doubleValue)
            }
        }
    }

    func load() {
        do {
            let dbQueue = try DatabaseManager.shared.dbQueue()
            try loadNetWorth(dbQueue)

            // This month, sorted by spend for the top-3 cards.
            summaries = try allocationService.monthlySummary(for: Date()).sorted { $0.spent > $1.spent }
            let spent = try allocationService.totalSpent(for: Date())
            if let income = try allocationService.currentIncome(), income.amount > 0 {
                let saved = income.amount - spent
                savingsRate = max(0, min(1, NSDecimalNumber(decimal: saved / income.amount).doubleValue))
                monthLine = "Spent \(spent) of \(income.amount) EGP this month"
            } else {
                savingsRate = 0
                monthLine = spent > 0 ? "Spent \(spent) EGP this month — set your income in Budget" : "Set your income in the Budget tab"
            }

            // Sankey: income splits into per-category spending flows (top 6
            // for legibility), an "Other" catch-all for the rest of the
            // spending, and the saved remainder in cream. Together these sum
            // to income exactly, so the diagram conserves — the left income
            // bar equals the stacked right bars.
            if let income = try allocationService.currentIncome(), income.amount > 0 {
                let shown = summaries.filter { $0.spent > 0 }.prefix(6)
                let shownSum = shown.reduce(Decimal(0)) { $0 + $1.spent }
                var flows = shown.map {
                    SankeyView.Flow(name: $0.category.name,
                                    value: NSDecimalNumber(decimal: $0.spent).doubleValue)
                }
                // Spending beyond the top 6 (and any net rounding) so the
                // shown flows account for all of `spent`, not just the top 6.
                let other = spent - shownSum
                if other > 0 {
                    flows.append(SankeyView.Flow(name: "Other",
                                                 value: NSDecimalNumber(decimal: other).doubleValue))
                }
                let saved = max(0, income.amount - spent)
                if saved > 0 {
                    flows.append(SankeyView.Flow(name: "Saved",
                                                 value: NSDecimalNumber(decimal: saved).doubleValue,
                                                 isSavings: true))
                }
                sankeyIncome = NSDecimalNumber(decimal: income.amount).doubleValue
                sankeyFlows = flows
            } else {
                sankeyIncome = 0
                sankeyFlows = []
            }
        } catch {
            monthLine = "Could not load dashboard: \(error.localizedDescription)"
        }
    }
}

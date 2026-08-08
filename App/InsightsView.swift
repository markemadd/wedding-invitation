import SwiftUI
import Charts
import Persistence
import UI

// MARK: - InsightsView — "Data Overview" redesign
// One scroll of everything Mizan knows, per the Claude Design spec:
// period selector (Month/Quarter/Year), net-worth hero with a savings-rate
// gauge, KPI strip, net-worth trend, income-vs-spending bars, budget
// split, category performance, debt payoff, goals & sinking funds, the
// month story (shareable) + spending pace, and the on-device data
// footprint. All numbers come from InsightsViewModel — no arithmetic here.
struct InsightsView: View {
    @StateObject private var model = InsightsViewModel()
    @State private var showStoryShare = false
    @State private var selectedDay: Int?
    @State private var selectedWeekday: String?

    var body: some View {
        NavigationStack {
            ZStack {
                KitTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        periodSegment
                        if model.hasData {
                            heroCard
                            kpiStrip
                            if model.nwTrend.count >= 2 { netWorthTrendCard }
                            flowCard
                            if !model.allocSlices.isEmpty { budgetSplitCard }
                            if !model.categoryRows.isEmpty { categoriesCard }
                            if !model.debts.isEmpty { debtCard }
                            forecastCard
                            if !model.goalRings.isEmpty || !model.fundBars.isEmpty { goalsCard }
                            if !model.storyLines.isEmpty { storyCard }
                            if model.period == .month { paceCard }
                            if model.period == .month && !model.weekdayTotals.isEmpty { weekdayCard }
                            footprintCard
                        } else {
                            insightsEmptyState
                        }
                    }
                    .padding(16)
                    .padding(.bottom, TabBarLayout.clearance)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showStoryShare) {
                StoryCardShareView(
                    monthTitle: Date().formatted(.dateTime.month(.wide).year()),
                    lines: model.storyLines
                )
            }
            .task { model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .mizanDataDidChange)) { _ in
                model.load()
            }
        }
    }

    // MARK: Header + period segment

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(KitTheme.textPrimary)
                Text("Everything Mizan knows · \(model.periodLabel)")
                    .font(.system(size: 13))
                    .foregroundStyle(KitTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    /// Shown on a fresh install (no transactions yet) instead of a wall of
    /// zero-value cards, so the very first thing a new user (or an App Review
    /// tester) sees is guidance, not an empty dashboard.
    private var insightsEmptyState: some View {
        KitCard(padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(KitTheme.primary)
                Text("No insights yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KitTheme.textPrimary)
                Text("Add your first few transactions and Mizan will chart your spending, net worth, budgets and forecasts here.")
                    .font(.system(size: 13))
                    .foregroundStyle(KitTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.top, 24)
    }

    private var periodSegment: some View {
        HStack(spacing: 4) {
            ForEach(InsightsViewModel.Period.allCases) { period in
                let active = model.period == period
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { model.setPeriod(period) }
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 13, weight: active ? .bold : .semibold))
                        .foregroundStyle(active ? .black : KitTheme.ink.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 12).fill(KitTheme.primary)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(KitTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(KitTheme.ink.opacity(0.09), lineWidth: 0.5))
    }

    // MARK: Hero — net worth + savings gauge

    private var heroCard: some View {
        KitCard(padding: 18) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Net worth")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
                    Text(model.netWorthText)
                        .font(.system(size: 25, weight: .bold).monospacedDigit())
                        .foregroundStyle(KitTheme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 2)
                    if let delta = model.deltaText {
                        HStack(spacing: 4) {
                            Image(systemName: model.deltaPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                            Text(delta).font(.system(size: 12, weight: .bold).monospacedDigit())
                        }
                        .foregroundStyle(model.deltaPositive ? KitTheme.primary : KitTheme.expense)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background((model.deltaPositive ? KitTheme.primary : KitTheme.expense).opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .padding(.top, 8)
                    }
                    HStack(spacing: 14) {
                        heroStat("Spendable", model.spendableText, KitTheme.textPrimary)
                        heroStat("Debt", model.debtText, AppTheme.accentCream)
                    }
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                savingsGauge
            }
        }
    }

    private func heroStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(KitTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// 288° arc gauge (matches the design's dasharray 321.6/402): fraction
    /// of this period's income that was kept.
    private var savingsGauge: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.8)
                .stroke(KitTheme.ink.opacity(0.13), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(126))
            Circle()
                .trim(from: 0, to: 0.8 * model.gaugeFraction)
                .stroke(KitTheme.primary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(126))
                .animation(.easeOut(duration: 0.6), value: model.gaugeFraction)
            VStack(spacing: 0) {
                Text("\(model.savingsRate)%")
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(KitTheme.textPrimary)
                Text("saved \(model.periodShort)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(KitTheme.textSecondary)
            }
        }
        .frame(width: 120, height: 120)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 8) {
            kpiTile("Income", model.incomeText, KitTheme.textPrimary)
            kpiTile("Spent", model.spentText, AppTheme.accentCream)
            kpiTile("Saved", model.savedText, KitTheme.primary)
        }
    }

    private func kpiTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(KitTheme.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(KitTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Net worth trend

    private var netWorthTrendCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Net worth trend").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    Text("6 months").font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                }
                Chart(model.nwTrend) { point in
                    AreaMark(x: .value("Month", point.label), y: .value("Net worth", point.value))
                        .foregroundStyle(
                            LinearGradient(colors: [KitTheme.primary.opacity(0.28), .clear],
                                           startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Month", point.label), y: .value("Net worth", point.value))
                        .foregroundStyle(KitTheme.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .frame(height: 110)
            }
        }
    }

    // MARK: Income vs spending

    private var flowCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Income vs spending")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    legendDot(KitTheme.primary, "Income")
                    legendDot(AppTheme.accentCream, "Spent")
                }
                if model.flowBars.allSatisfy({ $0.value == 0 }) {
                    Text("No income or spending recorded in this range yet.")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    Chart(model.flowBars) { bar in
                        BarMark(
                            x: .value("Period", bar.label),
                            y: .value("Amount", bar.value)
                        )
                        .position(by: .value("Series", bar.series))
                        .foregroundStyle(by: .value("Series", bar.series))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale([
                        "Income": KitTheme.primary,
                        "Spent": AppTheme.accentCream
                    ])
                    .chartLegend(.hidden)
                    .frame(height: 140)
                }
            }
        }
    }

    // MARK: Budget split donut

    private var budgetSplitCard: some View {
        KitCard(padding: 18) {
            HStack(spacing: 18) {
                ZStack {
                    DonutRing(segments: model.allocSlices.map {
                        DonutRing.Segment(value: $0.fraction, color: $0.color)
                    })
                    .frame(width: 120, height: 120)
                    VStack(spacing: 0) {
                        Text(model.allocTotalText)
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundStyle(KitTheme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 76)
                        Text("allocated").font(.system(size: 9)).foregroundStyle(KitTheme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Budget split")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                        .padding(.bottom, 3)
                    ForEach(model.allocSlices) { slice in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 9, height: 9)
                            Text(slice.name).font(.system(size: 13)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Text("\(slice.pct)% · \(slice.amountText)")
                                .font(.system(size: 11).monospacedDigit()).foregroundStyle(KitTheme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Spending by category

    private var categoriesCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Spending by category")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                // Stacked share bar: each category's slice of total spending.
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(model.categoryRows) { row in
                            Rectangle().fill(row.chipColor)
                                .frame(width: max(2, geo.size.width * row.share))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                ForEach(model.categoryRows) { row in
                    VStack(spacing: 7) {
                        HStack(spacing: 10) {
                            Text(String(row.name.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(row.chipColor)
                                .frame(width: 26, height: 26)
                                .background(row.chipColor.opacity(0.25), in: Circle())
                            Text(row.name)
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Text(row.amountsText)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(row.overBudget ? Color(hexValue: 0xFF5D5D) : KitTheme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(KitTheme.ink.opacity(0.12))
                                Capsule().fill(row.barTint)
                                    .frame(width: max(3, geo.size.width * row.barFraction))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                Text("spent / allocated per category — green within, cream near the limit, red over")
                    .font(.system(size: 10)).foregroundStyle(KitTheme.textTertiary)
            }
        }
    }

    // MARK: Debt payoff

    private var debtCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Debt payoff").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    Text("\(model.debtRemainingText) EGP left")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(AppTheme.accentCream)
                }
                ForEach(model.debts) { debt in
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(debt.name).font(.system(size: 13, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                            Spacer()
                            Text("\(debt.pctLabel) paid").font(.system(size: 11).monospacedDigit()).foregroundStyle(KitTheme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(KitTheme.ink.opacity(0.12))
                                Capsule().fill(KitTheme.primary)
                                    .frame(width: max(3, geo.size.width * debt.paidFraction))
                            }
                        }
                        .frame(height: 6)
                        HStack {
                            Text("\(debt.remainingText) left · \(debt.aprText)")
                            Spacer()
                            Text("Payoff \(debt.payoffText)")
                        }
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(KitTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: Goals & sinking funds

    private var goalsCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                if !model.goalRings.isEmpty {
                    Text("Goals").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    HStack(alignment: .top) {
                        ForEach(model.goalRings) { goal in
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle().stroke(KitTheme.ink.opacity(0.1), lineWidth: 6)
                                    Circle().trim(from: 0, to: goal.fraction)
                                        .stroke(KitTheme.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text(goal.pctLabel)
                                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                                        .foregroundStyle(KitTheme.textPrimary)
                                }
                                .frame(width: 72, height: 72)
                                Text(goal.name)
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(KitTheme.textPrimary)
                                    .lineLimit(1)
                                Text(goal.caption)
                                    .font(.system(size: 9)).foregroundStyle(KitTheme.textTertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                if !model.fundBars.isEmpty {
                    if !model.goalRings.isEmpty {
                        Rectangle().fill(KitTheme.ink.opacity(0.1)).frame(height: 0.5)
                    }
                    Text("SINKING FUNDS")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(KitTheme.textSecondary)
                        .kerning(0.5)
                    ForEach(model.fundBars) { fund in
                        VStack(spacing: 6) {
                            HStack {
                                Text(fund.name).font(.system(size: 12)).foregroundStyle(KitTheme.textPrimary)
                                Spacer()
                                Text(fund.progressText)
                                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(KitTheme.textSecondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(KitTheme.ink.opacity(0.12))
                                    Capsule().fill(AppTheme.accentCream)
                                        .frame(width: max(3, geo.size.width * fund.fraction))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: Month story (shareable)

    private var storyCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This month's story").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    Button { showStoryShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KitTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(model.storyLines, id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(KitTheme.textPrimary.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Spending pace (cumulative vs even budget burn)

    private var paceCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Spending pace").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    if model.hasBudgetPace && !model.paceDeltaText.isEmpty {
                        Text(model.paceDeltaText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.aheadOfPace ? KitTheme.primary : KitTheme.expense)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((model.aheadOfPace ? KitTheme.primary : KitTheme.expense).opacity(0.12), in: Capsule())
                    }
                }
                if model.cumulative.isEmpty || model.cumulative.allSatisfy({ $0.spent == 0 }) {
                    Text("No spending recorded yet this month.")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                } else {
                    Chart {
                        ForEach(model.cumulative) { point in
                            AreaMark(x: .value("Day", point.day), y: .value("Spent so far", point.spent))
                                .foregroundStyle(KitTheme.primary.opacity(0.12))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Day", point.day), y: .value("Spent so far", point.spent))
                                .foregroundStyle(KitTheme.primary)
                                .interpolationMethod(.monotone)
                        }
                        // The dashed line is the EVEN burn of the monthly
                        // budget — drawn only when a budget exists, and
                        // always named in the legend below.
                        if model.hasBudgetPace {
                            ForEach(model.cumulative.compactMap { p in p.pace.map { (p.day, $0) } }, id: \.0) { day, pace in
                                LineMark(x: .value("Day", day), y: .value("Even budget pace", pace))
                                    .foregroundStyle(AppTheme.accentCream)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            }
                        }
                        if let day = selectedDay, let sel = model.cumulative.first(where: { $0.day == day }) {
                            RuleMark(x: .value("Day", day)).foregroundStyle(KitTheme.ink.opacity(0.15))
                            PointMark(x: .value("Day", sel.day), y: .value("Spent so far", sel.spent))
                                .foregroundStyle(KitTheme.primary)
                        }
                    }
                    .chartLegend(.hidden)
                    .chartXSelection(value: $selectedDay)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                    .frame(height: 160)
                    HStack(spacing: 16) {
                        legendDot(KitTheme.primary, "Spent so far")
                        if model.hasBudgetPace { legendDot(AppTheme.accentCream, "Even budget pace") }
                        Spacer()
                        if let day = selectedDay, let sel = model.cumulative.first(where: { $0.day == day }) {
                            Text("Day \(day): \(Money.egp(sel.spentTotal))")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(KitTheme.textPrimary)
                        } else {
                            Text("Tap the chart to read a day")
                                .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Weekday spread

    private var weekdayCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Spending by day").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    if let label = selectedWeekday,
                       let point = model.weekdayTotals.first(where: { $0.label == label }) {
                        Text("\(label): \(Money.egp(point.total))")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(KitTheme.primary)
                    } else {
                        Text("tap a bar").font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                    }
                }
                Chart(model.weekdayTotals) { point in
                    BarMark(x: .value("Day", point.label), y: .value("Amount", point.amount))
                        .foregroundStyle(selectedWeekday == point.label ? KitTheme.primary : KitTheme.primary.opacity(0.45))
                        .cornerRadius(4)
                }
                .chartXSelection(value: $selectedWeekday)
                .frame(height: 140)
                Text(model.weekdayInsight)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(KitTheme.textSecondary)
            }
        }
    }

    // MARK: Data footprint

    private var footprintCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Data captured").font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Text("On-device, encrypted · never leaves your iPhone")
                        .font(.system(size: 11)).foregroundStyle(KitTheme.textTertiary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(model.footprint) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(KitTheme.textPrimary)
                            Text(stat.label).font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(KitTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if !model.sources.isEmpty {
                    Text("HOW IT'S CAPTURED")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(KitTheme.textSecondary)
                        .kerning(0.5)
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(model.sources) { source in
                                Rectangle().fill(source.color)
                                    .frame(width: max(2, geo.size.width * source.fraction))
                            }
                        }
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())
                    FlowLayoutRow(sources: model.sources)
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
        }
    }
}

// MARK: - Forecast card (extension keeps the main view under the line budget)

extension InsightsView {
    var forecastCard: some View {
        KitCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Net worth forecast")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KitTheme.textPrimary)
                    Spacer()
                    Picker("Horizon", selection: Binding(
                        get: { model.forecastMonths },
                        set: { model.setForecastHorizon($0) }
                    )) {
                        Text("1y").tag(12)
                        Text("2y").tag(24)
                        Text("5y").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                if let p50 = model.forecastP50, let p10 = model.forecastP10, let p90 = model.forecastP90 {
                    Chart {
                        ForEach(model.forecastBands) { band in
                            AreaMark(
                                x: .value("Month", band.month),
                                yStart: .value("Low", band.p10),
                                yEnd: .value("High", band.p90))
                                .foregroundStyle(KitTheme.primary.opacity(0.15))
                                .interpolationMethod(.monotone)
                        }
                        ForEach(model.forecastBands) { band in
                            LineMark(x: .value("Month", band.month), y: .value("Median", band.p50))
                                .foregroundStyle(KitTheme.primary)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let month = value.as(Int.self) { Text("\(month)mo") }
                            }
                        }
                    }
                    .frame(height: 150)
                    VStack(spacing: 6) {
                        forecastRow("Median", Money.egp(p50), KitTheme.primary)
                        forecastRow("Optimistic (90th)", Money.egp(p90), KitTheme.textSecondary)
                        forecastRow("Pessimistic (10th)", Money.egp(p10), KitTheme.textSecondary)
                    }
                    Text(model.forecastAssumption)
                        .font(.system(size: 10)).foregroundStyle(KitTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Needs at least 2 months with recorded transactions to simulate — keep capturing and this fills in.")
                        .font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
                }
            }
        }
    }

    private func forecastRow(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(KitTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }
}

/// Source legend chips, wrapping onto two rows when needed.
private struct FlowLayoutRow: View {
    let sources: [InsightsViewModel.SourceSlice]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  alignment: .leading, spacing: 10) {
            ForEach(sources) { source in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(source.color).frame(width: 8, height: 8)
                    Text(source.name).font(.system(size: 11)).foregroundStyle(KitTheme.textSecondary)
                    Text("\(source.pct)%")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(KitTheme.textTertiary)
                }
            }
        }
    }
}

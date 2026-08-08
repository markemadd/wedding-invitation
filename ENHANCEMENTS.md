# Mizan — Enhancement Plan (Phase 2)

Authored after a full code audit of all 21 Swift files against the inspiration
screenshots. The app is feature-complete per the original blueprint. This
document describes what to build next to make it significantly better — not
just polished, but genuinely more useful day-to-day.

Work through the waves in order. Each wave is independently shippable (build,
test, install) without blocking the next.

---

## Current state (after blueprint)

| Tab | What it does |
|-----|-------------|
| Home | Capture hub + dashboard (net worth gauge, top spending, Sankey, 6M trend) |
| Transactions | Search + swipe-edit over full history |
| Budget | Salary allocation editor (100% rule) |
| Plan | Recurring suggestions, bills, goals, wishlist, debts, sinking funds, investments |
| Settings | Accounts, categories, FX rates, export, backup |

Foundations are solid: SQLCipher encryption, Face ID gate, TransactionWriter,
PrivacyShield, GlassCard, RadialGauge, AppTheme — all in place.

---

## Wave A — UI polish (no new screens, no migrations)

These are targeted fixes to specific files. Each one is a small, contained
change that makes the app noticeably more consistent with the design direction.

### A1 — SegmentedProgressBar component (new file)

**File to create:** `Packages/UI/Sources/UI/SegmentedProgressBar.swift`

Replace every `ProgressView(value:)` in the app with this. Current single-color
bars ignore the mint/cream/red color language from the blueprint.

```swift
// Three segments: spent (mint on-track, cream ≥80%, red over) /
// remaining (white.opacity(0.15)) — matches the multi-segment pattern
// from the blueprint's Section 2 and the inspiration's wishlist cards.
public struct SegmentedProgressBar: View {
    public let fraction: Double   // 0...1+, clamped visually at 1
    public let height: CGFloat

    public init(fraction: Double, height: CGFloat = 6) {
        self.fraction = fraction
        self.height = height
    }

    private var tint: Color {
        fraction >= 1.0 ? .red
        : fraction >= 0.8 ? AppTheme.accentCream
        : AppTheme.accentMint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: height)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(1, fraction), height: height)
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: height)
    }
}
```

**Files to update after creating this:**
- `App/DashboardSection.swift` — replace `ProgressView(value: min(1, model.usedFraction(summary)))` with `SegmentedProgressBar(fraction: model.usedFraction(summary))`
- `App/PlanView.swift` — replace `ProgressView(value: model.fundProgress(fund))` in `fundsSection` with `SegmentedProgressBar(fraction: model.fundProgress(fund))`

### A2 — Category color chips (new file)

**File to create:** `Packages/UI/Sources/UI/CategoryChip.swift`

Circular colored chip used wherever a category appears inline (transaction rows,
budget cards). Color is derived deterministically from the category name so it's
stable across relaunches without storing a color field.

```swift
public struct CategoryChip: View {
    public let name: String
    public let size: CGFloat

    public init(name: String, size: CGFloat = 32) {
        self.name = name
        self.size = size
    }

    // Deterministic hue from name hash — same category always same color,
    // no DB column needed, O(1). Capped to a warm palette (exclude cold
    // blues/grays that read as "default/unset").
    private var chipColor: Color {
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let hue = Double(hash % 300) / 360.0   // 0–300° excludes blue-gray band
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(chipColor.opacity(0.25))
                .frame(width: size, height: size)
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(chipColor)
        }
    }
}
```

**Files to update:**
- `App/TransactionsView.swift` — add `CategoryChip` before the merchant text in `row(_:)`
- `App/DashboardSection.swift` — add chip beside category name in `monthCard`

### A3 — Transaction row direction colors

**File:** `App/TransactionsView.swift` → `row(_:)` function

Currently the amount text has no color differentiation. Income should be mint,
expenses red.

```swift
// Change the amount Text in row(_:) from .primary foreground to:
Text("\(transaction.direction == .income ? "+" : "−")\(transaction.amount) \(transaction.currency)")
    .font(.subheadline.monospacedDigit())
    .foregroundStyle(transaction.direction == .income ? AppTheme.accentMint : .red)
```

### A4 — Dual-series trend chart

**File:** `App/DashboardSection.swift` → `trendCard` and `DashboardViewModel`

Current trend chart shows expenses only. Change to income (mint) vs expenses
(cream) side-by-side bars using `foregroundStyle(by:)`.

```swift
// In DashboardViewModel, replace TrendPoint with:
struct TrendPoint: Identifiable {
    let id = UUID()
    let label: String
    let series: String    // "Income" or "Expenses"
    let value: Double
}

// In trendCard, replace the Chart body with:
Chart(model.trend) { point in
    BarMark(
        x: .value("Month", point.label),
        y: .value("Amount", point.value)
    )
    .foregroundStyle(by: .value("Series", point.series))
}
.chartForegroundStyleScale([
    "Income": AppTheme.accentMint,
    "Expenses": AppTheme.accentCream
])
.frame(height: 140)
```

Also update `DashboardViewModel.load()` to build two TrendPoints per month
(income via `allocationService.currentIncome()` per month, expenses via
`allocationService.totalSpent(for:)`).

### A5 — Net worth detail sheet

**File:** `App/DashboardSection.swift` → `netWorthCard`

Make the gauge card tappable. On tap it presents a sheet with:
- Spendable (sum of `AccountType.checking/savings` balances)
- Assets (sum of `AccountType.investment/asset` balances)
- Debt (sum of `AccountType.creditCard/loan` balances, shown negative)
- Line chart from `NetWorthSnapshot` records (already in DB)

No new DB migration needed — `NetWorthSnapshot` table and `Account.type` are
already there.

---

## Wave B — New screens (new files, one DB migration)

### B1 — Bills tab (new first-class tab)

The biggest UX improvement. Currently bills/subscriptions are buried in PlanView.
Promote to a dedicated tab with three sub-tabs.

**New file:** `App/BillsView.swift`

Structure:
```
BillsView
├── Picker: Subscriptions / Installments / Smart Suggestions
├── SubscriptionsTab  — cards from RecurringSeries where intervalDays ≤ 31
├── InstallmentsTab   — cards from new installmentPlan table
└── SmartSuggestionsTab — RecurringDetectionService candidates, swipeable Add/Dismiss
```

**Header card** (same teal/purple gradient as inspiration):
```
Monthly spending: EGP X
[Active: N]  [Per year: EGP X]  [This week: N]
```

**DB migration (v6):** Add `installmentPlan` table:
```sql
CREATE TABLE installmentPlan (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,              -- e.g. "ValU — iPhone"
    providerName TEXT,               -- e.g. "ValU", "Halan"
    monthlyAmount TEXT NOT NULL,     -- Decimal as TEXT
    totalInstallments INTEGER NOT NULL,
    paidCount INTEGER NOT NULL DEFAULT 0,
    startDate DATETIME NOT NULL,
    currency TEXT NOT NULL DEFAULT 'EGP'
)
```

**File:** `Packages/Persistence/Sources/Persistence/Records/InstallmentPlan.swift`

Add `migrator.registerMigration("v6_installment_plans")` in `DatabaseManager.runMigrations`.

**InstallmentPlan progress card** (matches inspiration "3 of 12 paid"):
```swift
struct InstallmentCard: View {
    let plan: InstallmentPlan
    // ...
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CategoryChip(name: plan.providerName ?? plan.name)
                    VStack(alignment: .leading) {
                        Text(plan.name).font(.subheadline.weight(.medium))
                        Text("\(plan.paidCount) of \(plan.totalInstallments) paid")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(plan.monthlyAmount) EGP / mo")
                        .font(.subheadline.monospacedDigit())
                }
                SegmentedProgressBar(fraction: Double(plan.paidCount) / Double(plan.totalInstallments))
            }
        }
    }
}
```

**Smart Suggestions tab** — wrap each `RecurringSeriesCandidate` in a swipeable card:
- Swipe right (mint) = Confirm → writes a `RecurringSeries` row
- Swipe left (red) = Dismiss → removes candidate from list
- Replaces the raw List section currently in PlanView

### B2 — Insights tab (new first-class tab)

**New file:** `App/InsightsView.swift`

Three segments via `Picker` (Overview / Trends / Details):

**Overview segment:**
- Monthly spend total + saved badge (`+EGP X saved`)
- Income stat, vs-last-period %, budget-used %
- Daily Spending area chart (current month, x = day, y = amount)
- Stat row: Average / Highest / Total spend

**Trends segment:**
- Dual-series 6M bar chart (income mint / expenses cream) with 3M/6M toggle
- Period Comparison card (this month vs last month):
  - Income row: `EGP X  ▲ 730%  (was EGP Y)`
  - Expenses row: `EGP X  ▼ 27%  (was EGP Y)`
  - Net Balance: This period vs last period

**Details segment:**
- Spending by Day (group by weekday, BarMark — Sun to Sat)
- Auto-insight: "You spend N% more on weekdays" computed from the grouped totals
- Weekdays total vs Weekends total

All data comes from existing `monthlySummary()`, `totalSpent()`, and direct
GRDB queries — no new service methods beyond a `groupByWeekday()` helper.

**New file:** `App/InsightsViewModel.swift`

```swift
// groupByWeekday: O(n) scan of this month's transactions.
// Returns [0...6] → total spend, where 0 = Sunday.
func groupByWeekday(transactions: [Transaction]) -> [Int: Decimal] {
    var result: [Int: Decimal] = [:]
    let cal = Calendar.current
    for t in transactions where t.direction == .expense {
        let day = cal.component(.weekday, from: t.date) - 1  // 0-indexed
        result[day, default: 0] += t.amount
    }
    return result
}
```

### B3 — Tab bar restructure

**File:** `App/MainTabView.swift`

New 5-tab layout matching the inspiration:

```swift
TabView {
    WalletView()      // renamed ContentView — home + recent transactions
        .tabItem { Label("Wallet", systemImage: "creditcard.fill") }
    BillsView()
        .tabItem { Label("Bills", systemImage: "arrow.2.circlepath") }
    BucketsView()     // renamed BudgetView + absorbs goals/wishlist/debts/funds from PlanView
        .tabItem { Label("Buckets", systemImage: "basket.fill") }
    InsightsView()
        .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
    SettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
}
```

`BucketsView` = current BudgetView + a "Plan" NavigationLink that opens the
goals/wishlist/debts/sinking funds section as a pushed screen. PlanView becomes
`PlanDetailView`, no longer a tab.

`WalletView` = current ContentView + rename. Capture buttons stay, recent list
stays, DashboardSection stays.

---

## Wave C — AI Mizan tab

The LLM package (`Packages/LLM/`) and `PromptTemplates.swift` are already
wired. This wave adds the user-facing chat screen.

### C1 — AI chat screen

**New file:** `App/MizanAIView.swift`

Layout (matches inspiration's "Hey Shady" screen):
- Large greeting: `"Hey [name]"` (name from Settings or a one-time prompt)
- Subheading: `"Ask me anything about your money"`
- "Continue your conversation >" row (persists last session in UserDefaults)
- 6 quick-prompt chips (tappable, fires the prompt directly):
  - "How much did I spend this month?"
  - "Can I afford EGP X this weekend?"
  - "Show my top categories"
  - "Trend over the last 30 days"
  - "How am I doing on budgets?"
  - "Find expenses over EGP 1000"

Context injection before each LLM call:
```swift
// Inject a small JSON context block so the LLM answers from real data,
// not hallucinated figures. Keep it under ~400 tokens.
struct MizanContext: Encodable {
    let currentMonth: String
    let totalSpent: String
    let income: String
    let topCategories: [String]   // ["Food: 3,800", "Transfer: 8,300", ...]
    let budgetUsedPercent: Int
    let netWorth: String
}
```

### C2 — AI Roasting mode

Toggle in the AI screen header (or Settings). When on, the LLM system prompt
gains a persona instruction: "You are a brutally honest but funny financial
advisor. Roast the user's spending habits using the context provided."

One extra button on the AI screen: "Roast my spending 🔥" → fires the roast
prompt with full monthly context injected. No new architecture — just a second
prompt template in `PromptTemplates.swift`.

**File:** `Packages/LLM/Sources/LLM/PromptTemplates.swift` — add:
```swift
static func roastPrompt(context: MizanContext) -> String {
    """
    You are a brutally honest but funny financial roaster.
    The user's spending data this month: \(context.summary).
    Give a short, sharp, comedic roast (3-4 sentences max).
    End with one genuine tip disguised as a joke.
    """
}
```

---

## Execution order

```
Wave A (UI polish — no migration, no new tabs)
  A1 SegmentedProgressBar    → new file + 2 replacements
  A2 CategoryChip            → new file + 2 usage sites
  A3 Transaction row colors  → 3-line change in TransactionsView.swift
  A4 Dual-series trend chart → DashboardSection + DashboardViewModel
  A5 Net worth detail sheet  → DashboardSection (tap gesture + sheet)

Wave B (new screens — 1 migration, 3 new files)
  B1 InstallmentPlan migration (v6) → DatabaseManager.runMigrations
  B1 InstallmentPlan record  → new Persistence record file
  B1 BillsView               → new App screen file
  B2 InsightsView            → new App screen file
  B2 InsightsViewModel       → new App file
  B3 MainTabView restructure → rename + rewire tabs

Wave C (AI tab — no migration)
  C1 MizanAIView             → new App screen file
  C1 MizanContext injector   → new helper in LLM package
  C2 Roast prompt template   → add to PromptTemplates.swift
```

## Testing notes per wave

**Wave A** — no schema changes, so no migration risk. Run the full test suite
after each change (`xcodebuild ... test`). The UIThemeTests in
`Packages/UI/Tests/` should still pass; add a preview for SegmentedProgressBar
and CategoryChip before committing.

**Wave B** — migration v6 is additive (new table only), so existing device data
is safe. Test on simulator first: install, verify v6 runs, add one installment
plan, confirm progress bar updates when paidCount increments. After the tab
restructure, verify all five original tabs still work via the new names.

**Wave C** — LLM inference is gated by the existing `LLMService` guard; if the
model isn't bundled the chat screen should degrade gracefully to an empty state
with a "Model not available" message rather than crashing.

---

## Commit conventions (same as CLAUDE.md)

- Format: `what + why + "Suite: N green"`
- Author: Mark Emad <markgaras90@gmail.com>
- Co-author trailer: `Co-authored-by: Claude <claude@anthropic.com>`

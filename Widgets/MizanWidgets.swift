import WidgetKit
import SwiftUI

// MARK: - Mizan widgets
// "Safe to spend today" on the Home Screen and Lock Screen. The widget
// process reads ONLY the derived WidgetSnapshot the app publishes to the
// App Group — it never touches the encrypted database, whose key is
// Face-ID-gated and unreachable here by design.

@main
struct MizanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
        NetWorthWidget()
        BudgetRingWidget()
    }
}

// The widget target doesn't link the UI package (it would drag the whole
// design system into the extension), so the few colors it needs are
// restated here. Keep in sync with KitTheme: mint 0xA6F059, canvas 0x08090C,
// cream 0xF2E3B3.
extension Color {
    static let mizanMint = Color(.sRGB, red: 0xA6 / 255, green: 0xF0 / 255, blue: 0x59 / 255)
    static let mizanCanvas = Color(.sRGB, red: 0x08 / 255, green: 0x09 / 255, blue: 0x0C / 255)
    static let mizanCream = Color(.sRGB, red: 0xF2 / 255, green: 0xE3 / 255, blue: 0xB3 / 255)
}

// Shared money formatting for the widgets (the UI package isn't linked).
enum WidgetFormat {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()
    static func egp(_ value: Decimal) -> String {
        (formatter.string(from: value as NSNumber) ?? "\(value)") + " EGP"
    }
    /// "8.4K" / "840" — compact for tight dials.
    static func compact(_ value: Decimal) -> String {
        let d = NSDecimalNumber(decimal: value).doubleValue
        if abs(d) >= 100_000 { return String(format: "%.0fK", d / 1000) }
        if abs(d) >= 1000 { return String(format: "%.1fK", d / 1000) }
        return String(format: "%.0f", d)
    }
}

struct MizanEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct MizanProvider: TimelineProvider {
    func placeholder(in context: Context) -> MizanEntry {
        MizanEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MizanEntry) -> Void) {
        // The gallery preview falls back to the sample so it never shows
        // real figures while the user is just browsing widgets.
        let snapshot = context.isPreview ? .sample : WidgetSnapshotStore.read()
        completion(MizanEntry(date: .now, snapshot: snapshot ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MizanEntry>) -> Void) {
        let entry = MizanEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // Data-driven refreshes arrive from the app (reloadTimelines on
        // every data change). This midnight refresh only re-divides the
        // remaining budget across one fewer day.
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct SafeToSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: MizanProvider()) { entry in
            SafeToSpendView(entry: entry)
                .containerBackground(for: .widget) { Color.mizanCanvas }
        }
        .configurationDisplayName("Safe to spend")
        .description("Today's safe-to-spend from your monthly budget. Computed on-device; no transactions leave the app.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Net worth widget

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MizanNetWorth", provider: MizanProvider()) { entry in
            NetWorthView(entry: entry)
                .containerBackground(for: .widget) { Color.mizanCanvas }
        }
        .configurationDisplayName("Net worth")
        .description("Your net worth and its recent trend. Read on-device from your accounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Budget ring widget

struct BudgetRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MizanBudgetRing", provider: MizanProvider()) { entry in
            BudgetRingView(entry: entry)
                .containerBackground(for: .widget) { Color.mizanCanvas }
        }
        .configurationDisplayName("Budget ring")
        .description("How much of this month's budget you've spent.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Views

struct SafeToSpendView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MizanEntry

    private var safeToday: Decimal? { entry.snapshot?.safePerDay(on: entry.date) }
    private var daysLeft: Int { entry.snapshot?.daysLeft(on: entry.date) ?? 0 }
    private var remainingFraction: Double {
        1 - min(1, max(0, entry.snapshot?.usedFraction ?? 0))
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    private var inline: some View {
        // Single line for the Lock Screen inline slot.
        Label(
            safeToday.map { "\(Self.money($0)) safe today" } ?? "Set a budget in Mizan",
            systemImage: "leaf.fill"
        )
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.mizanMint)
                Text("SAFE TODAY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let safeToday {
                Text(Self.money(safeToday))
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(Color.mizanMint)
                            .frame(width: geo.size.width * remainingFraction)
                    }
                }
                .frame(height: 5)
            } else {
                Spacer(minLength: 0)
                Text("Set a monthly budget in Mizan to see your daily safe-to-spend.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill").font(.system(size: 10, weight: .bold))
                Text("Safe to spend").font(.system(size: 12, weight: .semibold))
            }
            if let safeToday {
                Text(Self.money(safeToday))
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") left this month")
                    .font(.system(size: 11))
                    .opacity(0.7)
            } else {
                Text("Set a budget in Mizan")
                    .font(.system(size: 12))
                    .opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        Gauge(value: remainingFraction) {
            Image(systemName: "leaf.fill")
        } currentValueLabel: {
            Text(safeToday.map(Self.compact) ?? "—")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    // MARK: Formatting (kept local — the UI package isn't linked here)

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// "1,240 EGP" — whole pounds; widget space is too tight for piasters.
    static func money(_ value: Decimal) -> String {
        (formatter.string(from: value as NSNumber) ?? "\(value)") + " EGP"
    }

    /// "8.4K" / "840" — for the Lock Screen circular dial.
    static func compact(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        if double >= 100_000 { return String(format: "%.0fK", double / 1000) }
        if double >= 1000 { return String(format: "%.1fK", double / 1000) }
        return String(format: "%.0f", double)
    }
}

// MARK: - Net worth view

struct NetWorthView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MizanEntry

    private var netWorth: String? { entry.snapshot?.netWorthText }
    private var trend: [Double] { entry.snapshot?.netWorthTrend ?? [] }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.mizanMint)
            Text("NET WORTH")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let netWorth {
                Text(netWorth + " EGP")
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
                Spacer(minLength: 0)
                Sparkline(points: trend).frame(height: 34)
            } else {
                Spacer(minLength: 0)
                Text("Add accounts in Mizan to track net worth.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Text((netWorth ?? "—") + " EGP")
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
                if let bill = entry.snapshot?.nextBillName, let amount = entry.snapshot?.nextBillAmountText {
                    Text("Next: \(bill) · \(amount) EGP")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Sparkline(points: trend).frame(width: 130, height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 10, weight: .bold))
                Text("Net worth").font(.system(size: 12, weight: .semibold))
            }
            Text((netWorth ?? "—") + " EGP")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Minimal filled sparkline for the net-worth trend (geometry only).
private struct Sparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geo in
            let pts = normalized(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Color.mizanMint.opacity(0.3), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(Color.mizanMint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        let lo = points.min() ?? 0, hi = points.max() ?? 1
        let range = hi - lo
        return points.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
            let normalizedY = range > 0 ? (value - lo) / range : 0.5
            let y = size.height * (1 - CGFloat(normalizedY))
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Budget ring view

struct BudgetRingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MizanEntry

    private var used: Double { min(1, max(0, entry.snapshot?.usedFraction ?? 0)) }
    private var hasBudget: Bool { entry.snapshot?.hasBudget ?? false }
    private var ringColor: Color { used >= 1 ? .red : used >= 0.8 ? Color.mizanCream : Color.mizanMint }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.mizanMint)
                Text("BUDGET")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            if hasBudget {
                HStack {
                    ZStack {
                        Circle().stroke(.white.opacity(0.14), lineWidth: 8)
                        Circle().trim(from: 0, to: used)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int((used * 100).rounded()))%")
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)
                    Spacer()
                }
                if let spent = entry.snapshot?.spentText, let budget = entry.snapshot?.budgetText {
                    Text("\(spent) / \(budget) EGP")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                Spacer(minLength: 0)
                Text("Set a monthly budget in Mizan.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var circular: some View {
        Gauge(value: used) {
            Image(systemName: "chart.pie.fill")
        } currentValueLabel: {
            Text("\(Int((used * 100).rounded()))%")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
    }
}

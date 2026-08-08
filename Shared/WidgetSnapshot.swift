import Foundation

// MARK: - WidgetSnapshot (compiled into BOTH the app and the widget extension)
// The PendingCaptureQueue pattern applied to display surfaces: widgets run
// outside the Face-ID-gated session, so the app publishes a TINY derived
// snapshot to the App Group container — never transactions, never account
// balances, only the budget aggregates the user has explicitly chosen to
// put on their Home/Lock Screen. Same protection class as the pending
// queue file (device-level until first unlock after boot).
struct WidgetSnapshot: Codable {
    /// Remaining monthly budget — Decimal serialized as text (exactness rule).
    let remainingText: String
    /// Fraction of the budget consumed, 0...1+ (gauge geometry only).
    let usedFraction: Double
    /// Epoch of the first instant of NEXT month. The widget derives
    /// days-left at render time, so the per-day number rolls over correctly
    /// at midnight even if the app never opens that day.
    let monthEndEpoch: TimeInterval
    let hasBudget: Bool
    let updatedAt: Date

    // Additional glanceable figures for the extra widgets. All optional so
    // an older snapshot (before these existed) still decodes — the app
    // rewrites the full snapshot on next launch.
    /// Net worth (sum of accounts in EGP) as grouped text, e.g. "624,800".
    var netWorthText: String?
    /// Up to 6 monthly net-worth points (oldest→newest) for a sparkline.
    var netWorthTrend: [Double]?
    /// Spent so far this month (net) as text.
    var spentText: String?
    /// The monthly budget cap as text.
    var budgetText: String?
    /// Next upcoming bill/subscription, if any.
    var nextBillName: String?
    var nextBillDateEpoch: TimeInterval?
    var nextBillAmountText: String?

    var remaining: Decimal? {
        Decimal(string: remainingText, locale: Locale(identifier: "en_US_POSIX"))
    }

    var nextBillDate: Date? {
        nextBillDateEpoch.map { Date(timeIntervalSince1970: $0) }
    }

    /// Safe-to-spend for a given day: remaining budget spread evenly over
    /// the days left in the month (minimum 1, so a stale snapshot from a
    /// finished month never divides by zero).
    func safePerDay(on date: Date = Date()) -> Decimal? {
        guard hasBudget, let remaining else { return nil }
        let start = Calendar.current.startOfDay(for: date)
        let monthEnd = Date(timeIntervalSince1970: monthEndEpoch)
        let days = max(1, Calendar.current.dateComponents([.day], from: start, to: monthEnd).day ?? 1)
        return remaining / Decimal(days)
    }

    func daysLeft(on date: Date = Date()) -> Int {
        let start = Calendar.current.startOfDay(for: date)
        let monthEnd = Date(timeIntervalSince1970: monthEndEpoch)
        return max(1, Calendar.current.dateComponents([.day], from: start, to: monthEnd).day ?? 1)
    }

    /// Gallery/placeholder sample — obviously round numbers, no real data.
    static let sample = WidgetSnapshot(
        remainingText: "8400",
        usedFraction: 0.42,
        monthEndEpoch: Date().addingTimeInterval(10 * 86_400).timeIntervalSince1970,
        hasBudget: true,
        updatedAt: Date(),
        netWorthText: "624,800",
        netWorthTrend: [560, 575, 582, 598, 606, 625],
        spentText: "6,100",
        budgetText: "10,500",
        nextBillName: "Netflix",
        nextBillDateEpoch: Date().addingTimeInterval(3 * 86_400).timeIntervalSince1970,
        nextBillAmountText: "165"
    )
}

enum WidgetSnapshotStore {
    static let appGroupId = "group.com.markemad.mizan"
    /// The widget kind string — shared so the app reloads exactly this widget.
    static let widgetKind = "MizanSafeToSpend"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("widget_snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        // Failure is non-fatal by design: the widget simply keeps showing
        // its previous snapshot until the next successful publish.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

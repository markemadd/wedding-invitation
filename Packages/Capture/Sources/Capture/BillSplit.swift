import Foundation

// MARK: - Bill splitting
// Pure, deterministic split math for the "Split a bill" flow (restaurant check
// or a shared supermarket run). Items come from ReceiptOCRService (or manual
// entry); each item is assigned to one or more people and its cost is divided
// equally among them. Extras (tax, tip, service, delivery) are distributed
// either proportionally to each person's subtotal or equally. Money is Decimal
// end-to-end — the same rule as the rest of Mizan.

/// One line on the bill, assigned to zero or more people (by index). An empty
/// assignment means "not assigned yet" and is surfaced to the user, not
/// silently dropped.
public struct BillSplitItem: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var price: Decimal
    public var assignedTo: Set<Int>

    public init(id: UUID = UUID(), name: String, price: Decimal, assignedTo: Set<Int> = []) {
        self.id = id
        self.name = name
        self.price = price
        self.assignedTo = assignedTo
    }
}

/// How a shared charge (tax / tip / service / delivery) is spread across people.
public enum ExtraSplitMode: String, CaseIterable, Sendable {
    case proportional   // in proportion to each person's item subtotal
    case equal          // the same amount for everyone

    public var label: String { self == .proportional ? "By share" : "Split evenly" }
}

public struct BillSplitExtra: Identifiable, Equatable {
    public let id: UUID
    public var label: String
    public var amount: Decimal
    public var mode: ExtraSplitMode

    public init(id: UUID = UUID(), label: String, amount: Decimal, mode: ExtraSplitMode = .proportional) {
        self.id = id
        self.label = label
        self.amount = amount
        self.mode = mode
    }
}

public struct BillSplitCalculator {
    public init() {}

    /// Per-person subtotal from their equal share of each assigned item.
    /// Unassigned items contribute to no one (see `unassignedTotal`).
    public func subtotals(items: [BillSplitItem], peopleCount: Int) -> [Decimal] {
        var totals = Array(repeating: Decimal(0), count: max(0, peopleCount))
        guard peopleCount > 0 else { return totals }
        for item in items where !item.assignedTo.isEmpty {
            let share = item.price / Decimal(item.assignedTo.count)
            for person in item.assignedTo where person >= 0 && person < peopleCount {
                totals[person] += share
            }
        }
        return totals
    }

    /// Spread one extra charge across people given their subtotals.
    public func distribute(_ amount: Decimal, over subtotals: [Decimal], mode: ExtraSplitMode) -> [Decimal] {
        let count = subtotals.count
        guard count > 0, amount != 0 else { return Array(repeating: Decimal(0), count: count) }
        switch mode {
        case .equal:
            let each = amount / Decimal(count)
            return Array(repeating: each, count: count)
        case .proportional:
            let base = subtotals.reduce(Decimal(0), +)
            guard base > 0 else {
                let each = amount / Decimal(count)
                return Array(repeating: each, count: count)
            }
            return subtotals.map { amount * $0 / base }
        }
    }

    /// Final per-person totals = subtotal + their share of every extra.
    public func totals(items: [BillSplitItem], peopleCount: Int, extras: [BillSplitExtra]) -> [Decimal] {
        let subs = subtotals(items: items, peopleCount: peopleCount)
        var result = subs
        for extra in extras {
            let dist = distribute(extra.amount, over: subs, mode: extra.mode)
            for index in result.indices { result[index] += dist[index] }
        }
        return result
    }

    /// Value of items nobody is assigned to yet — shown as a warning.
    public func unassignedTotal(_ items: [BillSplitItem]) -> Decimal {
        items.filter { $0.assignedTo.isEmpty }.reduce(Decimal(0)) { $0 + $1.price }
    }

    /// Round each total to 2 decimal places, then push the rounding residual
    /// onto the largest share so the per-person totals sum EXACTLY to the
    /// rounded grand total (no vanishing/duplicated cents).
    public func rounded(_ values: [Decimal]) -> [Decimal] {
        guard !values.isEmpty else { return [] }
        var result = values.map { Self.round2($0) }
        let exact = Self.round2(values.reduce(Decimal(0), +))
        let residual = exact - result.reduce(Decimal(0), +)
        if residual != 0, let maxIndex = result.indices.max(by: { result[$0] < result[$1] }) {
            result[maxIndex] += residual
        }
        return result
    }

    public static func round2(_ decimal: Decimal) -> Decimal {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }
}

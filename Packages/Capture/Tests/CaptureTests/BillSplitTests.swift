import XCTest
@testable import Capture

final class BillSplitTests: XCTestCase {
    private let calc = BillSplitCalculator()

    func testSubtotalsSplitSharedItemsEqually() {
        let items = [
            BillSplitItem(name: "Burger", price: 200, assignedTo: [0]),
            BillSplitItem(name: "Fries (shared)", price: 60, assignedTo: [0, 1]),
            BillSplitItem(name: "Juice", price: 40, assignedTo: [1]),
        ]
        let subs = calc.subtotals(items: items, peopleCount: 2)
        XCTAssertEqual(subs[0], 230) // 200 + 30
        XCTAssertEqual(subs[1], 70)  // 40 + 30
    }

    func testUnassignedItemsAreReportedNotDropped() {
        let items = [
            BillSplitItem(name: "Coke", price: 25, assignedTo: [0]),
            BillSplitItem(name: "Water", price: 15, assignedTo: []),
        ]
        XCTAssertEqual(calc.unassignedTotal(items), 15)
        XCTAssertEqual(calc.subtotals(items: items, peopleCount: 2)[0], 25)
    }

    func testExtraDistributedProportionally() {
        let subs: [Decimal] = [230, 70] // total 300
        let dist = calc.distribute(30, over: subs, mode: .proportional)
        XCTAssertEqual(dist[0], 23) // 30 * 230/300
        XCTAssertEqual(dist[1], 7)  // 30 * 70/300
    }

    func testExtraDistributedEqually() {
        let dist = calc.distribute(30, over: [230, 70], mode: .equal)
        XCTAssertEqual(dist[0], 15)
        XCTAssertEqual(dist[1], 15)
    }

    func testTotalsAddSubtotalPlusExtras() {
        let items = [
            BillSplitItem(name: "A", price: 230, assignedTo: [0]),
            BillSplitItem(name: "B", price: 70, assignedTo: [1]),
        ]
        let totals = calc.totals(
            items: items, peopleCount: 2,
            extras: [BillSplitExtra(label: "Service 10%", amount: 30, mode: .proportional)])
        XCTAssertEqual(totals[0], 253) // 230 + 23
        XCTAssertEqual(totals[1], 77)  // 70 + 7
    }

    func testRoundingReconcilesToGrandTotal() {
        // Three-way even split of 100 → 33.33 each, one cent residual.
        let rounded = calc.rounded([Decimal(string: "33.333333")!,
                                    Decimal(string: "33.333333")!,
                                    Decimal(string: "33.333333")!])
        XCTAssertEqual(rounded.reduce(Decimal(0), +), Decimal(string: "100")!)
        XCTAssertEqual(Set(rounded).count, 2) // two at 33.33, one at 33.34
    }
}

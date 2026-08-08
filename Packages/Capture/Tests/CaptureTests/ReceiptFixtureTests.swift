import XCTest
import Foundation
@testable import Capture

// MARK: - Real-receipt regression tests
// Each fixture is the actual Vision output (text + geometry) for one of
// the user's real receipts, dumped by Tools/ReceiptProbe.swift with the
// exact recognition settings the app uses. Expected values were read off
// the receipt photos by eye. If a heuristic change breaks one of these,
// it broke a real receipt — not a synthetic hypothetical.
//
// NOTE ON AGING: date extraction enforces a plausibility window relative
// to "now" (not future, ≤3 years old). These receipts are from 2025–2026,
// so date assertions hold until mid-2028 — refresh the fixture set with
// newer receipts when they start expiring.
final class ReceiptFixtureTests: XCTestCase {
    private struct DumpLine: Codable {
        let text: String
        let h: Double
        let top: Double
        let left: Double
        let w: Double
    }

    private struct Expectation {
        let fixture: String
        let amount: Decimal
        let currency: String
        let date: (day: Int, month: Int, year: Int)?
        /// Lowercased substring that must appear in the merchant guess.
        let merchantContains: String
    }

    /// Ground truth for all 10 sample receipts.
    private let expectations: [Expectation] = [
        .init(fixture: "IMG_7550", amount: Decimal(string: "32.50")!, currency: "EUR",
              date: (25, 6, 2026), merchantContains: "adidas"),
        .init(fixture: "IMG_7551", amount: Decimal(string: "173.00")!, currency: "EUR",
              date: (20, 6, 2026), merchantContains: "carette"),
        .init(fixture: "IMG_7552", amount: Decimal(string: "119.96")!, currency: "EUR",
              date: (24, 6, 2026), merchantContains: "c&a"),
        .init(fixture: "IMG_7553", amount: Decimal(string: "40.00")!, currency: "EUR",
              date: (22, 6, 2026), merchantContains: "disneyland"),
        .init(fixture: "IMG_7554", amount: Decimal(string: "330.00")!, currency: "EUR",
              date: (24, 6, 2026), merchantContains: "swatch"),
        .init(fixture: "IMG_7555", amount: Decimal(string: "5.10")!, currency: "EUR",
              date: (20, 6, 2026), merchantContains: "ratp"),
        .init(fixture: "IMG_7556", amount: Decimal(string: "6.50")!, currency: "EUR",
              date: (26, 6, 2026), merchantContains: "five guys"),
        .init(fixture: "IMG_7557", amount: Decimal(string: "13.75")!, currency: "EUR",
              date: (25, 5, 2025), merchantContains: "mercadona"),
        .init(fixture: "IMG_7558", amount: Decimal(string: "113.00")!, currency: "EUR",
              date: (21, 6, 2026), merchantContains: "escargot"),
        .init(fixture: "IMG_7559", amount: Decimal(string: "48.10")!, currency: "EUR",
              date: (20, 6, 2026), merchantContains: "soleil")
    ]

    private func loadFixture(_ name: String) throws -> [OCRLine] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "Missing fixture \(name).json"
        )
        let dump = try JSONDecoder().decode([DumpLine].self, from: Data(contentsOf: url))
        return dump.map {
            OCRLine(
                text: $0.text,
                normalizedHeight: $0.h,
                topOffset: $0.top,
                leftOffset: $0.left,
                normalizedWidth: $0.w
            )
        }
    }

    func testAllRealReceiptsExtractCorrectly() throws {
        let service = ReceiptOCRService()
        // Same wiring as the app: the merchant table doubles as the brand
        // dictionary for the merchant-scoring boost.
        let brands = CategoryMatcher.keywordTable.map(\.keyword)
        let calendar = Calendar(identifier: .gregorian)

        for expectation in self.expectations {
            let lines = try loadFixture(expectation.fixture)
            let result = service.extractCandidates(fromOCRLines: lines, knownMerchantKeywords: brands)

            XCTAssertEqual(result.amount, expectation.amount,
                           "\(expectation.fixture): wrong total")
            XCTAssertEqual(result.currency, expectation.currency,
                           "\(expectation.fixture): wrong currency")

            let merchant = (result.merchant ?? "").lowercased()
            XCTAssertTrue(merchant.contains(expectation.merchantContains),
                          "\(expectation.fixture): merchant '\(merchant)' missing '\(expectation.merchantContains)'")

            if let expected = expectation.date {
                let date = try XCTUnwrap(result.date, "\(expectation.fixture): no date extracted")
                let parts = calendar.dateComponents([.day, .month, .year], from: date)
                XCTAssertEqual(parts.day, expected.day, "\(expectation.fixture): wrong day")
                XCTAssertEqual(parts.month, expected.month, "\(expectation.fixture): wrong month")
                XCTAssertEqual(parts.year, expected.year, "\(expectation.fixture): wrong year")
            }
        }
    }
}

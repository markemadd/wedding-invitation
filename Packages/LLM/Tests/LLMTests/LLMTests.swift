import XCTest
@testable import LLM

// Blueprint checkpoint (adapted): "confirm the LLM produces valid,
// parseable JSON for the categorization prompt across at least 20 varied
// test merchants." Model-quality runs happen on-device once weights exist;
// what unit tests CAN lock down is the contract around the model — the
// prompt renders for 20 varied merchants, and the strict parser accepts
// only valid in-list replies, rejecting every malformed variant.
final class LLMTests: XCTestCase {
    private let categories = [
        "food", "gas", "barber", "coffee", "cinema", "shopping",
        "transportation", "travel", "luxury", "supermarket", "sports"
    ]

    private let twentyMerchants = [
        "Carrefour City", "سوبر ماركت خير زمان", "Starbucks Zamalek",
        "Uber Trip", "EgyptAir", "VOX Cinema", "Gold's Gym", "Zara",
        "McDonald's Nasr City", "Mobil Station", "Careem", "Spinneys",
        "Cilantro Cafe", "Decathlon", "Barber Shop El Dokki", "IKEA",
        "Talabat Order", "H&M City Stars", "Booking.com", "كافيه المهندسين"
    ]

    func testCategorizationPromptRendersForTwentyVariedMerchants() {
        for merchant in twentyMerchants {
            let prompt = PromptTemplates.categorization(
                merchant: merchant, amount: "150.50", categories: categories
            )
            XCTAssertTrue(prompt.contains(merchant))
            XCTAssertTrue(prompt.contains("\"category\""))
            for category in categories {
                XCTAssertTrue(prompt.contains(category))
            }
        }
        XCTAssertEqual(twentyMerchants.count, 20)
    }

    func testParserAcceptsOnlyValidInListJSON() {
        // Clean reply.
        XCTAssertEqual(
            PromptTemplates.parseCategorizationReply(#"{"category": "coffee"}"#, allowedCategories: categories),
            "coffee"
        )
        // Wrapped in prose/code fences — models do this constantly.
        XCTAssertEqual(
            PromptTemplates.parseCategorizationReply(
                "Sure! ```json\n{\"category\": \"travel\"}\n```", allowedCategories: categories
            ),
            "travel"
        )
        // Out-of-list category: REJECTED, lands in review.
        XCTAssertNil(PromptTemplates.parseCategorizationReply(
            #"{"category": "groceries"}"#, allowedCategories: categories
        ))
        // Malformed variants: all rejected.
        for bad in ["not json at all", #"{"cat": "coffee"}"#, "{\"category\": }", ""] {
            XCTAssertNil(PromptTemplates.parseCategorizationReply(bad, allowedCategories: categories))
        }
    }

    func testRoastPromptCarriesInjectedContextNumbers() {
        let context = MizanContext(
            currentMonth: "July 2026",
            totalSpent: "12,400",
            income: "20,000",
            topCategories: ["Food: 3,800", "Transfer: 8,300"],
            budgetUsedPercent: 62,
            netWorth: "145,000"
        )
        let prompt = PromptTemplates.roastPrompt(context: context)
        // The roast must be grounded in the real figures, not free-invented.
        for expected in ["12,400", "20,000", "62%", "145,000", "Food: 3,800"] {
            XCTAssertTrue(prompt.contains(expected), "missing \(expected)")
        }
        // Persona + honesty guardrail both present.
        XCTAssertTrue(prompt.lowercased().contains("roaster"))
        XCTAssertTrue(prompt.lowercased().contains("do not invent"))
    }

    func testLLMServiceIsUnavailableWithoutBackend() async {
        // The normal state today: no weights bundled → graceful path.
        let service = LLMService()
        XCTAssertFalse(service.isAvailable)
        let context = MizanContext(
            currentMonth: "July 2026", totalSpent: "1", income: "2",
            topCategories: [], budgetUsedPercent: 0, netWorth: "3"
        )
        do {
            _ = try await service.answer(question: "hi", context: context)
            XCTFail("expected modelUnavailable")
        } catch {
            XCTAssertTrue(error is LLMError)
        }
    }

    func testNarrationPromptCarriesAllPercentiles() {
        let prompt = PromptTemplates.forecastNarration(
            p10: "90,000", p50: "120,000", p90: "160,000",
            monthsAhead: 24, successProbability: "88%"
        )
        for expected in ["90,000", "120,000", "160,000", "24", "88%"] {
            XCTAssertTrue(prompt.contains(expected))
        }
    }
}

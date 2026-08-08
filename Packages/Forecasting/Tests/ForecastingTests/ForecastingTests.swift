import XCTest
import GRDB
import Persistence
@testable import Forecasting

private struct TestKeyProvider: DatabaseKeyProviding {
    func fetchDatabaseKey() throws -> Data { Data(repeating: 0x55, count: 32) }
}

final class ForecastingTests: XCTestCase {
    // MARK: - Monte Carlo (blueprint checkpoint)

    /// Known-mean, known-variance input: p50 must land close to the
    /// deterministic mean × months projection, and zero variance must
    /// match it exactly across the whole band.
    func testP50TracksDeterministicProjection() {
        let service = ForecastingService()

        // Zero variance: every trial is identical → all bands equal.
        let flat = service.projectNetWorth(
            monthsAhead: 24,
            currentNetWorth: 100_000,
            historicalMonthlySavings: [5_000, 5_000, 5_000]
        )
        XCTAssertEqual(flat.p10, flat.p90)
        XCTAssertEqual(flat.p50, 100_000 + 5_000 * 24) // = 220,000 exactly.

        // Real variance: p50 within 5% of the deterministic answer, and
        // the bands ordered correctly.
        let noisy = service.projectNetWorth(
            monthsAhead: 24,
            currentNetWorth: 100_000,
            historicalMonthlySavings: [3_000, 5_000, 7_000]
        )
        let deterministic = Decimal(100_000 + 5_000 * 24)
        let tolerance = deterministic * Decimal(string: "0.05")!
        XCTAssertLessThan(abs(noisy.p50 - deterministic), tolerance)
        XCTAssertLessThan(noisy.p10, noisy.p50)
        XCTAssertLessThan(noisy.p50, noisy.p90)
    }

    func testSuccessProbabilityBounds() throws {
        let service = ForecastingService()
        let result = service.projectNetWorth(
            monthsAhead: 12,
            currentNetWorth: 0,
            historicalMonthlySavings: [1_000, 1_200, 800],
            successThreshold: 6_000 // Half the ~12,000 expectation: near-certain.
        )
        let probability = try XCTUnwrap(result.successProbability)
        XCTAssertGreaterThan(probability, 0.9)
        XCTAssertLessThanOrEqual(probability, 1.0)
    }

    // MARK: - Investments (blueprint checkpoint: hand-computed gains)

    func testFIFOGainsMatchHandCalculation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvestTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let manager = DatabaseManager(
            keyProvider: TestKeyProvider(),
            databaseURL: tempDir.appendingPathComponent("invest.sqlite")
        )
        let service = InvestmentService(databaseManager: manager)

        // Two lots: 10 @ 100 (older), 10 @ 150 (newer).
        let holding = try service.addHolding(ticker: "aapl", assetClass: "US equity", currency: "USD")
        let id = holding.id!
        try service.addLot(holdingId: id, quantity: 10, purchasePrice: 100,
                           purchaseDate: Date(timeIntervalSinceNow: -86_400 * 60))
        try service.addLot(holdingId: id, quantity: 10, purchasePrice: 150,
                           purchaseDate: Date(timeIntervalSinceNow: -86_400 * 10))

        // Sell 15 @ 200. FIFO hand math: 10 from the 100-lot →
        // (200−100)×10 = 1,000; then 5 from the 150-lot →
        // (200−150)×5 = 250. Realized = 1,250.
        let realized = try service.recordSale(holdingId: id, quantity: 15, salePrice: 200)
        XCTAssertEqual(realized, 1_250)

        // Remaining: 5 @ 150. Unrealized at current price 180:
        // (180−150)×5 = 150. Market value 900.
        try service.updateCurrentPrice(holdingId: id, price: 180)
        let position = try XCTUnwrap(service.positions().first)
        XCTAssertEqual(position.quantity, 5)
        XCTAssertEqual(position.unrealizedGain, 150)
        XCTAssertEqual(position.marketValue, 900)

        // Overselling must throw, never go negative.
        XCTAssertThrowsError(try service.recordSale(holdingId: id, quantity: 6, salePrice: 200))

        // Asset-class breakdown groups by the manual label.
        let breakdown = try service.assetClassBreakdown()
        XCTAssertEqual(breakdown.first?.assetClass, "US equity")
        XCTAssertEqual(breakdown.first?.value, 900)
    }

    // MARK: - Stock signal import (Phase 6.3 / Phase 7 checklist)

    func testValidSignalFileParses() throws {
        let json = """
        [{"ticker": "AAPL", "signal": "buy", "confidence": 0.8,
          "rationale": "Strong quarter", "timestamp": "2026-07-01T10:00:00Z"}]
        """
        let signals = try StockSignalImport.parse(Data(json.utf8))
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.signal, .buy)
    }

    /// The Phase 7 checklist item, run continuously: a field missing or a
    /// wrong type must reject the WHOLE file, never partially import.
    func testMalformedSignalFilesAreRejectedOutright() {
        let missingField = #"[{"ticker": "AAPL", "signal": "buy", "confidence": 0.8, "timestamp": "2026-07-01T10:00:00Z"}]"#
        let wrongType = #"[{"ticker": "AAPL", "signal": "buy", "confidence": "high", "rationale": "x", "timestamp": "2026-07-01T10:00:00Z"}]"#
        let badEnum = #"[{"ticker": "AAPL", "signal": "yolo", "confidence": 0.8, "rationale": "x", "timestamp": "2026-07-01T10:00:00Z"}]"#
        let outOfRange = #"[{"ticker": "AAPL", "signal": "buy", "confidence": 1.5, "rationale": "x", "timestamp": "2026-07-01T10:00:00Z"}]"#
        let oneBadEntry = #"""
        [{"ticker": "AAPL", "signal": "buy", "confidence": 0.8, "rationale": "x", "timestamp": "2026-07-01T10:00:00Z"},
         {"ticker": "", "signal": "sell", "confidence": 0.5, "rationale": "x", "timestamp": "2026-07-01T10:00:00Z"}]
        """#
        for bad in [missingField, wrongType, badEnum, outOfRange, oneBadEntry, "not json", "[]"] {
            XCTAssertThrowsError(try StockSignalImport.parse(Data(bad.utf8)),
                                 "Must reject: \(bad.prefix(40))")
        }
    }

    // MARK: - Price fetch gate

    func testFetchRefusesWhenDisabled() async {
        do {
            _ = try await PriceFetchService().fetchPrice(ticker: "AAPL", enabled: false)
            XCTFail("Disabled fetch must throw")
        } catch {
            XCTAssertEqual(error as? PriceFetchService.FetchError, .disabled)
        }
    }
}

extension PriceFetchService.FetchError: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

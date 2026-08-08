import Foundation
import GRDB

// MARK: - FxRate (Phase 3 conversion decision)
// One row per foreign currency: how many EGP one unit is worth. The
// blueprint's Phase 3 watch-out demands the conversion approach be decided
// BEFORE savings math and forecasting assume a unified currency — this is
// that decision: every aggregate converts to EGP through this table.
//
// Rates are MANUAL and user-edited (Settings): no network, per the
// security model. Phase 5's narrow price/FX fetch may update them later.
// This table is a deliberate, documented addition beyond the Section 5
// ERD, forced by real multi-currency receipts arriving in Phase 2.
public struct FxRate: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "fxRate"

    /// ISO code, e.g. "EUR". Primary key.
    public var currencyCode: String
    /// EGP per 1 unit of this currency. Exact Decimal, stored as TEXT.
    public var rateToEGP: Decimal
    public var updatedAt: Date

    public var id: String { currencyCode }

    public init(currencyCode: String, rateToEGP: Decimal, updatedAt: Date) {
        self.currencyCode = currencyCode
        self.rateToEGP = rateToEGP
        self.updatedAt = updatedAt
    }
}

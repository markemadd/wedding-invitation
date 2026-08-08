import Foundation
import GRDB
import Persistence

// MARK: - CategoryMatcher
// Suggests a category for a merchant string. Used by the wallet App Intent
// (blueprint 2.3) and the voice parser (2.4).
//
// ── STUB, AWAITING REAL DATA ────────────────────────────────────────────
// The blueprint deliberately leaves the merchant-to-category lookup table
// as a stub: it must be built from the user's REAL merchant list (actual
// Apple Pay merchant strings, Egyptian store names in Arabic and English),
// not guessed formats. Until that list is provided, the table below holds
// only a couple of obviously-safe generic entries, and everything else
// lands in "Uncategorized" for manual review — a wrong guess is worse
// than an honest "review me". Phase 5's on-device LLM later upgrades this
// lookup into a smarter classifier constrained to existing categories.
// ─────────────────────────────────────────────────────────────────────────
public struct CategoryMatcher {
    /// Lowercased keyword → category name from the user's canonical list.
    /// Matching is substring-based (merchant strings from Apple Pay often
    /// carry branch numbers and noise). O(k) per lookup; the table is
    /// small, effectively constant.
    ///
    /// Seeded with brands from the user's real receipt samples plus common
    /// Egyptian/global names as educated defaults. Grows as the user
    /// supplies actual merchant strings; anything unknown stays
    /// Uncategorized for review rather than being guessed.
    // Public: the app also feeds these keywords to ReceiptOCRService as
    // the brand dictionary for merchant scoring.
    public static let keywordTable: [(keyword: String, categoryName: String)] = [
        // supermarket
        ("carrefour", "supermarket"), ("spinneys", "supermarket"),
        ("mercadona", "supermarket"), ("seoudi", "supermarket"),
        ("kheir zaman", "supermarket"), ("metro market", "supermarket"),
        ("gourmet", "supermarket"), ("kazyon", "supermarket"),
        // food (restaurants / fast food)
        ("mcdonald", "food"), ("kfc", "food"), ("burger", "food"),
        ("pizza", "food"), ("five guys", "food"), ("restaurant", "food"),
        ("talabat", "food"), ("elmenus", "food"),
        // coffee
        ("starbucks", "coffee"), ("costa", "coffee"), ("cilantro", "coffee"),
        ("caribou", "coffee"), ("tim hortons", "coffee"), ("coffee", "coffee"),
        ("carette", "coffee"), ("espresso", "coffee"),
        // transportation (city transit / ride hailing)
        ("uber", "transportation"), ("careem", "transportation"),
        ("swvl", "transportation"), ("ratp", "transportation"),
        ("metro", "transportation"),
        // gas
        ("mobil", "gas"), ("total energies", "gas"), ("chillout", "gas"),
        ("wataniya", "gas"), ("misr petroleum", "gas"),
        // cinema
        ("cinema", "cinema"), ("vox", "cinema"), ("imax", "cinema"),
        ("galaxy", "cinema"),
        // shopping (clothing / general retail)
        ("adidas", "shopping"), ("nike", "shopping"), ("zara", "shopping"),
        ("h&m", "shopping"), ("c&a", "shopping"), ("amazon", "shopping"),
        ("noon", "shopping"), ("swatch", "shopping"),
        // sports
        ("decathlon", "sports"), ("gym", "sports"), ("fitness", "sports"),
        // travel
        ("egyptair", "travel"), ("airline", "travel"), ("airways", "travel"),
        ("booking", "travel"), ("airbnb", "travel"), ("hotel", "travel"),
        ("disneyland", "travel"),
        // barber
        ("barber", "barber"), ("salon", "barber"),
        // instapay transfers (the SMS intent prefixes transfer captures
        // with "InstaPay:" so this always matches)
        ("instapay", "instapay"), ("انستاباي", "instapay")
        // luxury: intentionally empty — too personal to guess; add the
        // user's actual merchants when provided.
    ]

    public init() {}

    /// Returns the id of the best-guess category. Resolution order:
    ///  1. THE USER'S OWN HISTORY — if this merchant was captured before
    ///     and manually categorized, reuse that category. This is what
    ///     stops the same shop landing in "Uncategorized" twice: correct
    ///     it once, and every future wallet/SMS/receipt capture of it is
    ///     categorized automatically. O(log n) via the merchant lookup.
    ///  2. The keyword table (brands).
    ///  3. "Uncategorized" for review — a wrong guess is worse than an
    ///     honest "review me".
    public func suggestCategoryId(forMerchant merchant: String, db: Database) throws -> Int64 {
        let lowered = merchant.lowercased()

        let uncategorizedId = try StarterDataBootstrapper.uncategorizedCategoryId(db)
        let historical = try Int64.fetchAll(db, sql: """
            SELECT categoryId FROM "transaction"
            WHERE LOWER(merchant) = ? ORDER BY date DESC LIMIT 5
            """, arguments: [lowered])
        if let remembered = historical.first(where: { $0 != uncategorizedId }) {
            return remembered
        }
        for entry in Self.keywordTable {
            if lowered.contains(entry.keyword) {
                if let match = try Persistence.Category
                    .filter(GRDB.Column("name") == entry.categoryName)
                    .fetchOne(db), let id = match.id {
                    return id
                }
            }
        }
        return try StarterDataBootstrapper.uncategorizedCategoryId(db)
    }
}

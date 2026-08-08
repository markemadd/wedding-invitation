import SwiftUI
import GRDB
import Persistence
import UI

// MARK: - ItemPriceHistoryView
// Per-item price tracking across receipts: search an item name and see
// every price you've paid, where, and when — the "is milk cheaper at
// Carrefour or Seoudi" question, answered from your own receipts.
struct ItemPriceHistoryView: View {
    @State private var query = ""
    @State private var results: [Entry] = []

    struct Entry: Identifiable {
        let id: Int64
        let name: String
        let price: Decimal
        let date: Date
        let merchant: String
    }

    var body: some View {
        List {
            if results.isEmpty {
                Text(query.isEmpty
                     ? "Scanned receipts save their line items automatically. Search an item to see its price history."
                     : "No items matching \"\(query)\" yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(results) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.name).font(.subheadline)
                        Spacer()
                        Text("\(entry.price)").font(.subheadline.monospacedDigit())
                    }
                    Text("\(entry.merchant) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Item prices")
        .searchable(text: $query, prompt: "Item name…")
        .onChange(of: query) { _, _ in search() }
        .task { search() }
    }

    /// LIKE search joined to the transaction for merchant/date, newest
    /// first. O(items) scan — fine at personal scale, index later if not.
    private func search() {
        results = (try? DatabaseManager.shared.dbQueue().read { db -> [Entry] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT ri.id AS id, ri.name AS name, ri.price AS price,
                       t.date AS date, t.merchant AS merchant
                FROM receiptItem ri
                JOIN "transaction" t ON t.id = ri.transactionId
                WHERE ri.name LIKE ?
                ORDER BY t.date DESC
                LIMIT 100
                """, arguments: ["%\(query)%"])
            return rows.compactMap { row in
                guard let id: Int64 = row["id"], let name: String = row["name"] else { return nil }
                let priceText: String = row["price"] ?? "0"
                return Entry(
                    id: id,
                    name: name,
                    price: Decimal(string: priceText, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
                    date: row["date"] ?? Date(),
                    merchant: row["merchant"] ?? "—"
                )
            }
        }) ?? []
    }
}

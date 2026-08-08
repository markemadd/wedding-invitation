import Foundation
import GRDB

// MARK: - ExportService (blueprint Phase 6.2)
// CSV for spreadsheets/tax, JSON for a full structured backup independent
// of the encrypted .sqlite backup. Deliberately the simplest code in the
// project (per the roadmap's v5 guidance): plain serialization, no
// cleverness. Files are written to tmp and handed to a share sheet; the
// user decides where they go from there.
public struct ExportService {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// RFC-4180-style escaping: quote fields containing commas, quotes, or
    /// newlines; double embedded quotes. Merchant names are user/OCR text
    /// and absolutely will contain commas.
    static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// One row per transaction with names resolved, O(n).
    public func transactionsCSV() throws -> String {
        try databaseManager.dbQueue().read { db in
            let categories = Dictionary(uniqueKeysWithValues: try Category.fetchAll(db).compactMap { category in
                category.id.map { ($0, category.name) }
            })
            let accounts = Dictionary(uniqueKeysWithValues: try Account.fetchAll(db).compactMap { account in
                account.id.map { ($0, account.name) }
            })
            let formatter = ISO8601DateFormatter()

            var csv = "id,date,amount,currency,merchant,category,account,source\n"
            for txn in try Transaction.order(GRDB.Column("date")).fetchAll(db) {
                let fields = [
                    "\(txn.id ?? 0)",
                    formatter.string(from: txn.date),
                    "\(txn.amount)",
                    txn.currency,
                    Self.csvEscape(txn.merchant ?? ""),
                    Self.csvEscape(categories[txn.categoryId] ?? ""),
                    Self.csvEscape(accounts[txn.accountId] ?? ""),
                    txn.source.rawValue
                ]
                csv += fields.joined(separator: ",") + "\n"
            }
            return csv
        }
    }

    /// Everything, as one JSON document of Codable records — a complete
    /// plaintext structured backup (the user chooses to create it; the
    /// encrypted .sqlite backup remains the safe default).
    public func fullJSON() throws -> Data {
        struct FullExport: Encodable {
            let exportedAt: Date
            let accounts: [Account]
            let categories: [Category]
            let transactions: [Transaction]
            let allocations: [CategoryAllocation]
            let income: Income?
            let recurringSeries: [RecurringSeries]
            let goals: [Goal]
            let wishlist: [WishlistItem]
            let debts: [Debt]
            let sinkingFunds: [SinkingFund]
            let holdings: [Holding]
            let lots: [CostBasisLot]
            let netWorthSnapshots: [NetWorthSnapshot]
            let fxRates: [FxRate]
        }
        let export = try databaseManager.dbQueue().read { db in
            FullExport(
                exportedAt: Date(),
                accounts: try Account.fetchAll(db),
                categories: try Category.fetchAll(db),
                transactions: try Transaction.fetchAll(db),
                allocations: try CategoryAllocation.fetchAll(db),
                income: try Income.fetchOne(db, key: 1),
                recurringSeries: try RecurringSeries.fetchAll(db),
                goals: try Goal.fetchAll(db),
                wishlist: try WishlistItem.fetchAll(db),
                debts: try Debt.fetchAll(db),
                sinkingFunds: try SinkingFund.fetchAll(db),
                holdings: try Holding.fetchAll(db),
                lots: try CostBasisLot.fetchAll(db),
                netWorthSnapshots: try NetWorthSnapshot.fetchAll(db),
                fxRates: try FxRate.fetchAll(db)
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Writes content to tmp for the share sheet, complete file protection.
    public func writeExportFile(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .completeFileProtection)
        return url
    }
}

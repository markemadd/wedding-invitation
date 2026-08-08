import Foundation
import GRDB
import Persistence

// MARK: - TransactionSearchService (blueprint Phase 3.4)
// Filtered transaction queries for the list/search screen. All filters are
// optional and combine with AND. The merchant filter is LIKE '%query%';
// date filtering rides the indexed date column. O(log n + results) for
// date-bounded queries; a bare text search is a linear scan, acceptable
// for a personal-scale table and easy to index later if it ever isn't.
public struct TransactionSearchService {
    public struct Filter {
        public var text: String?
        public var categoryId: Int64?
        public var accountId: Int64?
        public var from: Date?
        public var to: Date?

        public init(
            text: String? = nil,
            categoryId: Int64? = nil,
            accountId: Int64? = nil,
            from: Date? = nil,
            to: Date? = nil
        ) {
            self.text = text
            self.categoryId = categoryId
            self.accountId = accountId
            self.from = from
            self.to = to
        }
    }

    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    public func search(_ filter: Filter, limit: Int = 200) throws -> [Persistence.Transaction] {
        try databaseManager.dbQueue().read { db in
            var request = Persistence.Transaction.order(GRDB.Column("date").desc)
            if let text = filter.text, !text.isEmpty {
                request = request.filter(GRDB.Column("merchant").like("%\(text)%"))
            }
            if let categoryId = filter.categoryId {
                request = request.filter(GRDB.Column("categoryId") == categoryId)
            }
            if let accountId = filter.accountId {
                request = request.filter(GRDB.Column("accountId") == accountId)
            }
            if let from = filter.from {
                request = request.filter(GRDB.Column("date") >= from)
            }
            if let to = filter.to {
                request = request.filter(GRDB.Column("date") < to)
            }
            return try request.limit(limit).fetchAll(db)
        }
    }
}

import Foundation
import GRDB

// MARK: - Goal (ERD Section 5)
// A savings goal ("50,000 EGP by next June"). Deliberately NOT linked to
// categories or transactions by foreign key — the what-if planner evaluates
// goals against live aggregates computed at query time (blueprint Section 5
// note), so a goal never goes stale pointing at deleted rows.
public struct Goal: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "goal"

    public var id: Int64?
    public var name: String
    public var targetAmount: Decimal
    public var targetDate: Date
    /// Whether cut suggestions may touch any category or only flexible ones —
    /// chosen per-goal (blueprint Section 3 "cut scope chosen per-goal").
    public var cutScope: GoalCutScope
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        targetAmount: Decimal,
        targetDate: Date,
        cutScope: GoalCutScope,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.cutScope = cutScope
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// Persistence module — filled in during Phase 1.
//
// Will contain: DatabaseManager (the single encrypted-connection owner every
// other module reads through), GRDB record types for the full ERD in
// blueprint Section 5, and the schema migrations.
//
// Nothing outside this module ever opens SQLite directly — that rule is what
// makes the encryption and lock behavior enforceable in one place.

/// Namespace marker so the module compiles before Phase 1 adds real code.
public enum PersistenceModule {}

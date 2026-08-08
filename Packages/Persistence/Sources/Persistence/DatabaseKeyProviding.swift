import Foundation

// MARK: - DatabaseKeyProviding
// Abstracts "where the SQLCipher key comes from" so that:
//   - Production uses MizanSecurity's KeychainKeyManager (Secure Enclave-
//     backed, biometric-gated) — wired up once at app launch.
//   - Tests use a fixed in-memory key, because Keychain access control and
//     Face ID cannot run in a unit-test process; the biometric path is
//     verified on-device per the Phase 1 testing checkpoint instead.
//
// The protocol lives in Persistence (not MizanSecurity) so the dependency
// arrow points the right way: security conforms to what persistence needs,
// and Persistence never imports security code.
public protocol DatabaseKeyProviding {
    /// Returns the raw 256-bit database encryption key. Implementations may
    /// prompt for biometrics as a side effect (the Keychain access-control
    /// policy does exactly that).
    func fetchDatabaseKey() throws -> Data
}

import Foundation
import Security
import LocalAuthentication
import Persistence

// MARK: - KeychainKeyManager (blueprint Phase 1.1)
// Owns the single 256-bit database encryption key. The key never exists
// in plain memory longer than one function call, and is never written to
// disk anywhere except inside the Secure Enclave-backed Keychain entry.
public final class KeychainKeyManager {
    private let keyTag = "com.mizan.app.dbEncryptionKey"

    /// Set by AppLockViewModel after a successful biometric evaluation, and
    /// attached to Keychain reads via kSecUseAuthenticationContext. This is
    /// what makes the whole unlock flow show ONE Face ID prompt instead of
    /// two (one for the LAContext UI gate, a second for the Keychain read).
    public var authenticationContext: LAContext?

    public init() {}

    /// Generates a new 256-bit key on first launch only. Time complexity is
    /// irrelevant here — this runs exactly once in the app's lifetime.
    ///
    /// Existence is checked by attempting the add and treating
    /// errSecDuplicateItem as "already exists": probing with a read first
    /// (as in a naive check) would trigger a spurious Face ID prompt,
    /// because reads of this item are biometric-gated by design.
    public func generateAndStoreKeyIfNeeded() throws {
        var keyBytes = [UInt8](repeating: 0, count: 32) // 256 bits
        let status = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard status == errSecSuccess else {
            throw KeyManagerError.randomGenerationFailed
        }
        let keyData = Data(keyBytes)

        // kSecAccessControlBiometryCurrentSet: the key becomes UNUSABLE if
        // the enrolled Face ID/Touch ID set changes (e.g. a new fingerprint
        // is added) — a deliberate security tripwire, not a bug.
        // kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: never migrates to
        // another device via backup, and requires a passcode to exist at all.
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            throw KeyManagerError.accessControlCreationFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: access
        ]

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            return // Key already exists from a previous launch — nothing to do.
        default:
            throw KeyManagerError.keychainWriteFailed(addStatus)
        }
    }

    /// Retrieves the key. This call itself triggers the Face ID prompt via
    /// the access-control policy attached at creation time (unless a
    /// pre-authenticated LAContext is attached — see authenticationContext).
    public func retrieveKey() throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true
        ]
        if let context = authenticationContext {
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyManagerError.keyNotFound(status)
        }
        return data
    }
}

// The conformance DatabaseManager is configured with at app launch.
extension KeychainKeyManager: DatabaseKeyProviding {
    public func fetchDatabaseKey() throws -> Data {
        try retrieveKey()
    }
}

public enum KeyManagerError: Error, LocalizedError {
    case randomGenerationFailed
    case accessControlCreationFailed
    case keychainWriteFailed(OSStatus)
    case keyNotFound(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Could not generate a random encryption key."
        case .accessControlCreationFailed:
            return "Could not create the biometric access-control policy."
        case .keychainWriteFailed(let status):
            return "Could not store the encryption key in the Keychain (status \(status))."
        case .keyNotFound(let status):
            return "Could not read the encryption key from the Keychain (status \(status))."
        }
    }
}

import Foundation
import CryptoKit
import CommonCrypto
import Persistence

// MARK: - BackupService (blueprint Phase 1.5)
// Exports a single self-contained encrypted backup file, protected by a
// SEPARATE passphrase entered at export time — deliberately independent of
// this phone's Secure Enclave, so the backup remains restorable after the
// phone is lost, wiped, or replaced.
//
// DESIGN NOTE — envelope encryption, a deliberate upgrade over the
// blueprint's simplified sketch: the blueprint's example encrypted only the
// raw .sqlite bytes, but those bytes are themselves SQLCipher-encrypted
// with the device key, which lives ONLY in this phone's Keychain — such a
// backup could never be opened anywhere else, defeating its stated purpose
// ("independent of this phone's Secure Enclave"). Instead the payload here
// is [database key || database file], sealed together under the
// passphrase-derived key. Restoring on any device = decrypt with the
// passphrase, then open the SQLCipher file with the recovered key. No
// plaintext financial data is ever written to disk in the process.
//
// File format (all lengths fixed, no parsing ambiguity):
//   bytes 0..3   magic "MZBK"
//   byte  4      format version (1)
//   bytes 5..20  16-byte random PBKDF2 salt
//   bytes 21..   AES.GCM combined sealed box (12-byte nonce ++ ciphertext
//                ++ 16-byte auth tag) over: 32-byte DB key ++ sqlite bytes
public final class BackupService {
    private static let magic = Data("MZBK".utf8)
    private static let formatVersion: UInt8 = 1
    private static let saltLength = 16
    private static let dbKeyLength = 32

    /// PBKDF2-HMAC-SHA256 iteration count, per OWASP's password-storage
    /// guidance (600,000 for PBKDF2-SHA256, 2023 revision). The blueprint
    /// suggested HKDF, but HKDF is a key-*expansion* function for inputs
    /// that are already high-entropy — it does nothing to slow brute force
    /// on a human-typed passphrase. PBKDF2 with a high iteration count is
    /// the appropriate primitive here, and CommonCrypto ships it on-device
    /// (no third-party code).
    private static let pbkdf2Iterations: UInt32 = 600_000

    private let keyManager: KeychainKeyManager

    public init(keyManager: KeychainKeyManager) {
        self.keyManager = keyManager
    }

    /// Builds the encrypted backup and returns a temporary file URL to hand
    /// to a share sheet. Reading the key prompts Face ID via the Keychain
    /// access-control policy (or reuses the unlock session's context) —
    /// exporting is deliberately a biometric-gated action.
    public func exportEncryptedBackup(passphrase: String) throws -> URL {
        let databaseBytes = try DatabaseManager.shared.readDatabaseFileSnapshot()
        let dbKey = try keyManager.retrieveKey()
        let backupData = try Self.makeBackupData(
            databaseBytes: databaseBytes,
            databaseKey: dbKey,
            passphrase: passphrase
        )
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mizan_backup_\(Int(Date().timeIntervalSince1970)).mzbk")
        try backupData.write(to: exportURL, options: .completeFileProtection)
        return exportURL
    }

    // MARK: - Pure encrypt/decrypt core (unit-testable, no Keychain/device)

    static func makeBackupData(databaseBytes: Data, databaseKey: Data, passphrase: String) throws -> Data {
        guard databaseKey.count == dbKeyLength else { throw BackupError.malformedKey }
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }

        var salt = Data(count: saltLength)
        let saltResult = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
        }
        guard saltResult == errSecSuccess else { throw BackupError.encryptionFailed }

        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let payload = databaseKey + databaseBytes
        let sealed = try AES.GCM.seal(payload, using: key)
        guard let combined = sealed.combined else { throw BackupError.encryptionFailed }

        return magic + Data([formatVersion]) + salt + combined
    }

    /// Inverse of makeBackupData. Throws on a wrong passphrase — AES-GCM's
    /// authentication tag guarantees failure is clean and explicit, never
    /// silently returning garbage bytes (a Phase 7 checklist item).
    public static func decryptBackup(_ data: Data, passphrase: String) throws -> RestoredBackup {
        let headerLength = magic.count + 1 + saltLength
        guard data.count > headerLength,
              data.prefix(magic.count) == magic,
              data[magic.count] == formatVersion else {
            throw BackupError.unrecognizedFormat
        }
        let salt = data.subdata(in: (magic.count + 1)..<headerLength)
        let sealedData = data.subdata(in: headerLength..<data.count)

        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let payload: Data
        do {
            let box = try AES.GCM.SealedBox(combined: sealedData)
            payload = try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.wrongPassphraseOrCorrupt
        }

        guard payload.count > dbKeyLength else { throw BackupError.unrecognizedFormat }
        return RestoredBackup(
            databaseKey: payload.prefix(dbKeyLength),
            databaseBytes: payload.suffix(from: payload.startIndex + dbKeyLength)
        )
    }

    /// PBKDF2-HMAC-SHA256 → 256-bit AES key. O(iterations), deliberately
    /// slow (~a second on-device) to make offline brute force expensive.
    private static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let passphraseBytes = Array(passphrase.utf8)
        let result = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase, passphraseBytes.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdf2Iterations,
                    derivedPtr.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        guard result == kCCSuccess else { throw BackupError.encryptionFailed }
        return SymmetricKey(data: derived)
    }
}

public struct RestoredBackup {
    /// The raw SQLCipher key recovered from the backup.
    public let databaseKey: Data
    /// The SQLCipher-encrypted database file bytes.
    public let databaseBytes: Data
}

public enum BackupError: Error, LocalizedError {
    case emptyPassphrase
    case malformedKey
    case encryptionFailed
    case unrecognizedFormat
    case wrongPassphraseOrCorrupt

    public var errorDescription: String? {
        switch self {
        case .emptyPassphrase: return "A backup passphrase is required."
        case .malformedKey: return "The database key has an unexpected size."
        case .encryptionFailed: return "Encrypting the backup failed."
        case .unrecognizedFormat: return "This file is not a Mizan backup."
        case .wrongPassphraseOrCorrupt: return "Wrong passphrase, or the backup file is damaged."
        }
    }
}

import XCTest
@testable import MizanSecurity

// Backup round-trip tests — the simulator-runnable half of the Phase 1
// checkpoint item "export a backup, attempt to open it with the wrong
// passphrase, and confirm it fails." Keychain/biometric behavior is
// verified on-device via the manual checklist instead.
//
// Note: each key derivation deliberately costs ~600k PBKDF2 iterations, so
// this suite takes a few seconds by design — do not "optimize" the
// iteration count down for test speed.
final class MizanSecurityTests: XCTestCase {
    private let sampleKey = Data(repeating: 0xC3, count: 32)
    private let sampleDatabase = Data("pretend-sqlcipher-bytes-\(String(repeating: "x", count: 512))".utf8)

    func testBackupRoundTripWithCorrectPassphrase() throws {
        let backup = try BackupService.makeBackupData(
            databaseBytes: sampleDatabase,
            databaseKey: sampleKey,
            passphrase: "correct horse battery staple"
        )
        let restored = try BackupService.decryptBackup(backup, passphrase: "correct horse battery staple")
        XCTAssertEqual(restored.databaseKey, sampleKey)
        XCTAssertEqual(restored.databaseBytes, sampleDatabase)
    }

    func testWrongPassphraseFailsCleanly() throws {
        let backup = try BackupService.makeBackupData(
            databaseBytes: sampleDatabase,
            databaseKey: sampleKey,
            passphrase: "right"
        )
        XCTAssertThrowsError(try BackupService.decryptBackup(backup, passphrase: "wrong")) { error in
            XCTAssertEqual(error as? BackupError, .wrongPassphraseOrCorrupt)
        }
    }

    func testTamperedBackupFailsAuthentication() throws {
        var backup = try BackupService.makeBackupData(
            databaseBytes: sampleDatabase,
            databaseKey: sampleKey,
            passphrase: "pw"
        )
        backup[backup.count - 1] ^= 0xFF // Flip one ciphertext bit.
        XCTAssertThrowsError(try BackupService.decryptBackup(backup, passphrase: "pw")) { error in
            XCTAssertEqual(error as? BackupError, .wrongPassphraseOrCorrupt)
        }
    }

    func testUnrecognizedFileIsRejected() {
        let notABackup = Data("just some random file contents".utf8)
        XCTAssertThrowsError(try BackupService.decryptBackup(notABackup, passphrase: "pw")) { error in
            XCTAssertEqual(error as? BackupError, .unrecognizedFormat)
        }
    }

    func testEmptyPassphraseIsRejected() {
        XCTAssertThrowsError(
            try BackupService.makeBackupData(
                databaseBytes: sampleDatabase,
                databaseKey: sampleKey,
                passphrase: ""
            )
        ) { error in
            XCTAssertEqual(error as? BackupError, .emptyPassphrase)
        }
    }

    /// Two exports of identical content must differ (random salt + nonce) —
    /// a backup file must never leak "the data hasn't changed since the
    /// last export" to anyone holding both files.
    func testBackupsAreNotDeterministic() throws {
        let one = try BackupService.makeBackupData(databaseBytes: sampleDatabase, databaseKey: sampleKey, passphrase: "pw")
        let two = try BackupService.makeBackupData(databaseBytes: sampleDatabase, databaseKey: sampleKey, passphrase: "pw")
        XCTAssertNotEqual(one, two)
    }
}

extension BackupError: Equatable {
    public static func == (lhs: BackupError, rhs: BackupError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

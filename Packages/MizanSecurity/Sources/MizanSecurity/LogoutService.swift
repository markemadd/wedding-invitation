import Foundation
import Persistence

// MARK: - LogoutService (blueprint Phase 1.4)
// The deliberate top-right "log out" action — more than a re-lock: it
// invalidates every piece of in-memory decrypted state (the open database
// connection AND the authenticated biometric context), so using the app
// again requires the full unlock flow from scratch, not a fast re-prompt.
//
// Deliberately NOT deleting the Keychain key here: that would mean losing
// access to the encrypted data permanently. True "logout" for a
// single-user local app means "require full biometric re-proof before
// doing anything else." Only wipe the key entirely if an explicit
// "erase all data" feature is built later — keep that a clearly separate,
// scarier action.
public final class LogoutService {
    private let keyManager: KeychainKeyManager

    public init(keyManager: KeychainKeyManager) {
        self.keyManager = keyManager
    }

    public func logout() {
        keyManager.authenticationContext?.invalidate()
        keyManager.authenticationContext = nil
        DatabaseManager.shared.invalidateSession()
    }
}

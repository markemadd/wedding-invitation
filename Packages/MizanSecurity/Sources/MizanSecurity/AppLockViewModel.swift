import SwiftUI
import LocalAuthentication
import Persistence

// MARK: - AppLockViewModel (blueprint Phase 1.3)
// Drives the unlock screen. The app locks INSTANTLY on .background — no
// grace period, per the security requirement — and re-entry requires
// Face ID / Touch ID with device passcode as the automatic fallback.
@MainActor
public final class AppLockViewModel: ObservableObject {
    @Published public private(set) var isUnlocked = false
    /// Set when an unlock attempt fails for a reason worth showing (e.g.
    /// biometrics unavailable); nil on plain user cancellation.
    @Published public private(set) var unlockErrorMessage: String?

    /// Exposed so backup export (Settings) reuses the unlock session's
    /// authenticated context — one Face ID prompt, not two.
    public let keyManager: KeychainKeyManager

    public init(keyManager: KeychainKeyManager) {
        self.keyManager = keyManager
    }

    #if DEBUG
    /// Screenshot-mode only: start unlocked without a biometric prompt. Never
    /// called in Release (the caller is compiled out) — see MizanApp.
    public func debugForceUnlock() {
        isUnlocked = true
    }
    #endif

    /// Immediate, synchronous, no Task/delay/timer — called from the
    /// scenePhase observer the moment the app is backgrounded.
    public func lock() {
        isUnlocked = false
        // Tear down the decrypted connection, not just the UI. A stale
        // authenticated LAContext must not survive either, or the next
        // "unlock" would silently skip the biometric check.
        keyManager.authenticationContext?.invalidate()
        keyManager.authenticationContext = nil
        DatabaseManager.shared.invalidateSession()
    }

    public func attemptUnlock() async {
        unlockErrorMessage = nil
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = false
            unlockErrorMessage = "Biometric unlock is unavailable on this device."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // Face ID/Touch ID, falls back to device passcode automatically.
                localizedReason: "Unlock your finances"
            )
            guard success else {
                isUnlocked = false
                return
            }

            // Reusing this authenticated context for the Keychain read is
            // what keeps the flow to a single Face ID prompt.
            keyManager.authenticationContext = context

            // First launch only: creates the key. A no-op afterwards.
            try keyManager.generateAndStoreKeyIfNeeded()

            // Open the encrypted connection NOW rather than lazily, so a
            // key problem (e.g. the biometryCurrentSet tripwire fired after
            // a biometric re-enrollment) surfaces here as a lock-screen
            // error instead of a crash deep inside some feature screen.
            _ = try DatabaseManager.shared.dbQueue()

            isUnlocked = true
        } catch {
            isUnlocked = false
            unlockErrorMessage = "Could not unlock: \(error.localizedDescription)"
        }
    }
}

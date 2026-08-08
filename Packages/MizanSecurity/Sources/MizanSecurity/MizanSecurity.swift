// MizanSecurity module — filled in during Phase 1.
//
// Will contain: KeychainKeyManager (Secure Enclave-backed 256-bit database
// key with biometryCurrentSet access control), AppLockViewModel (immediate
// lock on backgrounding), LogoutService (session invalidation distinct from
// re-lock), and BackupService (passphrase-encrypted export, independent of
// the device's biometric key).

/// Namespace marker so the module compiles before Phase 1 adds real code.
public enum MizanSecurityModule {}

import Foundation
import CryptoKit
import Security

// MARK: - PendingCaptureQueue
// WHY THIS EXISTS: the Shortcuts automations (Apple Pay wallet trigger,
// bank-SMS message trigger) run in the BACKGROUND, where the main
// database is unreachable by design — its key is Face-ID-gated and a
// background intent can't show a biometric prompt. That's exactly why the
// user saw "wallet integration not working": the intent died silently on
// the Keychain read. Instead, intents append to this small queue and the
// app imports it (dedup + categorization + real insert) on next unlock.
//
// SECURITY TRADEOFF, made deliberately and visibly: queue items (merchant,
// amount, date — no balances, no card numbers) are AES-GCM encrypted under
// a SEPARATE key stored with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
// and NO biometric gate — that's what lets a background intent write while
// the phone is in a pocket. Until the next unlock drains it, this data has
// device-level (not Face-ID-level) protection. Accepted in exchange for
// capture actually working; the main ledger's protection is unchanged.
public final class PendingCaptureQueue {
    public struct PendingCapture: Codable, Equatable {
        public let merchant: String
        /// Decimal serialized as string — exactness rule applies here too.
        public let amountText: String
        public let currency: String
        public let dateEpoch: TimeInterval
        public let sourceRaw: String
        /// Optional for backward compatibility with items queued before
        /// direction existed; nil = expense.
        public let directionRaw: String?
        /// Last 4 digits of the card the SMS named, for account routing at
        /// import time. Optional for back-compat with older queued items.
        public let cardLast4: String?

        public init(merchant: String, amount: Decimal, currency: String, date: Date,
                    sourceRaw: String, directionRaw: String? = nil, cardLast4: String? = nil) {
            self.merchant = merchant
            self.amountText = "\(amount)"
            self.currency = currency
            self.dateEpoch = date.timeIntervalSince1970
            self.sourceRaw = sourceRaw
            self.directionRaw = directionRaw
            self.cardLast4 = cardLast4
        }

        public var amount: Decimal? {
            Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX"))
        }
        public var date: Date { Date(timeIntervalSince1970: dateEpoch) }
    }

    private let fileURL: URL
    /// Injectable for tests (unit tests can't touch the real Keychain).
    private let keyProvider: () throws -> Data

    public init(
        fileURL: URL? = nil,
        keyProvider: (() throws -> Data)? = nil
    ) {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? supportDir.appendingPathComponent("pending_captures.enc")
        self.keyProvider = keyProvider ?? Self.keychainQueueKey
    }

    // MARK: Queue key (non-biometric, background-writable)

    private static let keyAccount = "com.mizan.app.pendingQueueKey"

    private static func keychainQueueKey() throws -> Data {
        // Try read first (no access control on this item → no prompt).
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        if SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return data
        }
        // Create on first use. AfterFirstUnlockThisDeviceOnly: readable by
        // background intents once the phone has been unlocked since boot,
        // never migrates to another device.
        var keyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes) == errSecSuccess else {
            throw QueueError.keyUnavailable
        }
        let keyData = Data(keyBytes)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw QueueError.keyUnavailable
        }
        // Duplicate = another process won the race; re-read theirs.
        if status == errSecDuplicateItem {
            var again: AnyObject?
            guard SecItemCopyMatching(readQuery as CFDictionary, &again) == errSecSuccess,
                  let data = again as? Data else { throw QueueError.keyUnavailable }
            return data
        }
        return keyData
    }

    // MARK: Operations

    /// O(queue length) read-modify-write — queues hold at most a day or
    /// two of captures, so this is tiny.
    public func append(_ item: PendingCapture) throws {
        var items = try readAll()
        items.append(item)
        try write(items)
    }

    /// Returns everything and clears the file — call under an unlocked
    /// session so the items go straight into the real database.
    public func drainAll() throws -> [PendingCapture] {
        let items = try readAll()
        if !items.isEmpty {
            try FileManager.default.removeItem(at: fileURL)
        }
        return items
    }

    private func readAll() throws -> [PendingCapture] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let sealed = try Data(contentsOf: fileURL)
        let key = SymmetricKey(data: try keyProvider())
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([PendingCapture].self, from: plain)
        } catch {
            // A corrupt/tampered queue must never brick capture: drop it
            // (the ledger is untouched; at worst a queued item is lost).
            try? FileManager.default.removeItem(at: fileURL)
            return []
        }
    }

    private func write(_ items: [PendingCapture]) throws {
        let key = SymmetricKey(data: try keyProvider())
        let plain = try JSONEncoder().encode(items)
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw QueueError.encryptionFailed
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try combined.write(to: fileURL, options: .completeFileProtectionUntilFirstUserAuthentication)
    }

    public enum QueueError: Error {
        case keyUnavailable
        case encryptionFailed
    }
}

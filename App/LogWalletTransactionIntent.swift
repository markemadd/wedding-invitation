import AppIntents
import Foundation
import Capture

// MARK: - LogWalletTransactionIntent (blueprint Phase 2.3, reworked)
// Called by the Shortcuts Wallet/Transaction automation. REWORKED after
// on-device testing showed the original design failing: this intent runs
// in the background, and the database key is Face-ID-gated — a background
// process can't prompt for Face ID, so opening the database died
// silently. Now the intent only APPENDS to the encrypted pending queue
// (no biometrics needed); the app imports the queue — duplicate-checked
// against bank SMS and categorized — on the next unlock.
struct LogWalletTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log wallet transaction"
    static let description = IntentDescription(
        "Queues an Apple Pay transaction; Mizan imports it next time you unlock."
    )

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Amount")
    var amount: Double // Shortcuts passes Double; exact-decimal via string below.

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Defensive validation — external automation input, not a trusted
        // form (the Phase 7 checklist attacks this with negative amounts
        // and empty merchants).
        guard amount > 0, amount.isFinite else {
            throw IntentError.invalidAmount
        }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else {
            throw IntentError.emptyMerchant
        }
        // String round-trip dodges Double's binary representation error.
        guard let decimalAmount = Decimal(string: String(amount)) else {
            throw IntentError.invalidAmount
        }

        try PendingCaptureQueue().append(.init(
            merchant: trimmedMerchant,
            amount: decimalAmount,
            currency: "EGP",
            date: Date(),
            sourceRaw: "walletIntent"
        ))
        return .result(dialog: "Queued for Mizan — imports on next unlock.")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case emptyMerchant

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: return "The transaction amount must be a positive number."
        case .emptyMerchant: return "The merchant name is empty."
        }
    }
}

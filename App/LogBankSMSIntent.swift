import AppIntents
import Foundation
import Capture

// MARK: - LogBankSMSIntent (reworked to queue — see wallet intent for why)
// Called by a Shortcuts personal automation: "When I get a message
// containing <bank keyword> → Run Immediately → this intent with the
// message text." iOS never lets apps read SMS directly; this hand-off is
// the sanctioned mechanism, and the text never leaves the device.
// Parsing (amount/merchant/date, Arabic+English) happens here; duplicate
// checking against wallet captures happens at import time, when the
// database is reachable.
struct LogBankSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Log bank SMS"
    static let description = IntentDescription(
        "Parses a bank notification message and queues it; Mizan imports it next time you unlock."
    )

    @Parameter(title: "Message text")
    var messageText: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = BankSMSParser().parse(messageText)

        guard let amount = parsed.amount, amount > 0 else {
            throw SMSIntentError.noAmountFound
        }

        // Incoming money (InstaPay receives, refunds) is queued as INCOME:
        // it raises the month's available money and nets against sends in
        // the transfers category — never skipped anymore.
        let direction = parsed.isDebit ? "expense" : "income"
        try PendingCaptureQueue().append(.init(
            merchant: parsed.merchant ?? "Bank SMS",
            amount: amount,
            currency: parsed.currency,
            date: parsed.date ?? Date(), // The date printed in the SMS when present.
            sourceRaw: "sms",
            directionRaw: direction,
            cardLast4: parsed.cardLast4 // Routes to the matching account at import.
        ))
        let verb = parsed.isDebit ? "spent at" : "received from"
        return .result(dialog: "Queued \(String(describing: amount)) \(parsed.currency) \(verb) \(parsed.merchant ?? "unknown").")
    }
}

enum SMSIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAmountFound

    var localizedStringResource: LocalizedStringResource {
        "Couldn't find an amount in that message."
    }
}

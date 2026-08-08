import Foundation
import GRDB
import Persistence

// MARK: - BankSMSParser (post-blueprint addition, user-requested)
// First-pass extraction from bank notification SMS text — same
// review-before-commit philosophy as OCR/voice: the parse pre-fills a
// form, a human confirms. Built against common Egyptian bank formats
// (English and Arabic); tune against the user's REAL bank messages when
// samples are provided, exactly like the receipt heuristics were.
public struct BankSMSParser {
    public struct ParsedSMS: Equatable {
        public let amount: Decimal?
        public let currency: String
        public let merchant: String?
        /// True for InstaPay/bank transfers — in/out of the transfers
        /// category rather than merchant spending.
        public let isTransfer: Bool
        /// The date printed IN the message ("يوم 06/07/26") — falls back
        /// to nil (caller uses receipt time) when absent.
        public let date: Date?
        /// false = the message looks like an incoming credit (salary,
        /// refund) — surfaced so the UI can warn instead of logging it as
        /// spending.
        public let isDebit: Bool
        /// Last 4 digits of the card the message names ("…****1234"), when
        /// present — used to route the capture to the matching account.
        public let cardLast4: String?
    }

    /// Words marking money OUT (log it) vs IN (warn, probably not a purchase).
    private static let debitKeywords = [
        "charged", "debited", "purchase", "spent", "used for", "payment of",
        "خصم", "شراء", "سحب", "مشتريات"
    ]
    private static let creditKeywords = [
        "credited", "received", "deposit", "refund", "إيداع", "استرداد", "تحويل وارد"
    ]

    public init() {}

    /// Transfer context markers (InstaPay et al.). A transfer SMS gets
    /// counterparty extraction (من for receives, إلى for sends) instead of
    /// merchant extraction — and receives are logged as INCOME, raising
    /// the month's available money, per the user's requirement.
    private static let transferKeywords = [
        "انستاباي", "instapay", "تحويل", "استلام", "حوالة", "transfer"
    ]
    private static let receiveKeywords = [
        "استلام", "تم استلام", "received", "وصلك", "إيداع", "اضيف", "أضيف",
        "credited", "إضافة", "اضافة", "لحسابكم"
    ]

    /// O(n) over the message length — bank SMS are a few hundred chars.
    public func parse(_ text: String) -> ParsedSMS {
        // Eastern Arabic digits and the Arabic decimal separator appear in
        // Arabic-language bank messages; normalize first (shared with OCR).
        let normalized = ReceiptOCRService.normalizeEasternArabicDigits(in: text)
        let lowered = normalized.lowercased()
        let (amount, currency) = Self.extractAmountAndCurrency(from: normalized)
        let date = ReceiptOCRService().findDateLikePattern(in: [normalized])

        // The date parsers set a default time (noon); the real message
        // usually prints the actual time ("الساعه 12:31", "at 14:05"), so
        // stamp it onto the resolved day. Without this every SMS landed at
        // 12:00 — the bug the user hit.
        let resolvedDate = Self.applyTime(from: normalized,
                                          to: date ?? Self.parseNoYearDate(from: normalized))
        let cardLast4 = Self.extractCardLast4(from: normalized)
        let isTransfer = Self.transferKeywords.contains { lowered.contains($0) }
        if isTransfer {
            let isReceive = Self.receiveKeywords.contains { lowered.contains($0) }
            // Counterparty: after من when receiving, إلى/الى when sending.
            // Prefixed "InstaPay:" so the category matcher always lands the
            // instapay category, and history-first learns counterparties.
            let counterparty = Self.extractTransferCounterparty(from: normalized, isReceive: isReceive)
            return ParsedSMS(
                amount: amount,
                currency: currency,
                merchant: "InstaPay: " + (counterparty ?? (isReceive ? "received" : "sent")),
                isTransfer: true,
                date: resolvedDate,
                isDebit: !isReceive,
                cardLast4: cardLast4
            )
        }

        let isDebit = !Self.creditKeywords.contains { lowered.contains($0) }
            || Self.debitKeywords.contains { lowered.contains($0) }
        return ParsedSMS(
            amount: amount,
            currency: currency,
            merchant: Self.extractMerchant(from: normalized),
            isTransfer: false,
            // Receipt date parser first (day-first Egyptian formats,
            // 2-digit years, plausibility window), then the no-year
            // fallback for InstaPay-style "يوم 07-04".
            date: resolvedDate,
            isDebit: isDebit,
            cardLast4: cardLast4
        )
    }

    /// The last 4 digits of the card named in the message. Tries masked
    /// forms first ("****1234", "xxxx1234"), then "ending 1234", then a
    /// card keyword followed shortly by 4 digits. `\D` guards keep it from
    /// grabbing 4 digits out of a longer number (amount, reference).
    static func extractCardLast4(from text: String) -> String? {
        let patterns = [
            #"[*xX•×٪•]{2,}\s*(\d{4})\b"#,
            #"(?:ending(?:\s+in|\s+with)?)\s*(\d{4})\b"#,
            #"(?:المنتهيه|المنتهية)\s*(?:بـ|ب|ب\s)?\s*(\d{4})\b"#,
            // "…رقم 5983" (card no.) / "card 5678". \d{4}\b won't grab a
            // longer reference number (رقم مرجعي 963077936261 has no 4-digit
            // boundary), and \D{0,14} keeps it near the keyword.
            #"(?:card|بطاقة|البطاقة|بطاقتك|كارت|رقم)\D{0,14}?(\d{4})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    /// Stamps the time printed in the message onto `date` (keeping its
    /// year/month/day). No time found → the date is returned unchanged.
    static func applyTime(from text: String, to date: Date?) -> Date? {
        guard let date, let (hour, minute) = extractTime(from: text) else { return date }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    /// The transaction time from a bank SMS. Prefers a time right after an
    /// explicit marker ("الساعه"/"الساعة"/"at"/"@"); otherwise the first
    /// HH:MM in the message. Handles 24-hour and 12-hour clocks with
    /// AM/PM or the Arabic ص (AM) / م (PM). Returns nil when no valid time
    /// is present.
    static func extractTime(from text: String, now: Date = Date()) -> (hour: Int, minute: Int)? {
        let meridiem = #"(?:\s*(?:([AaPp])[Mm])|\s*(ص|م))?"#
        let markerPattern = #"(?:الساعه|الساعة|\bat\b|@)\s*(\d{1,2}):(\d{2})"# + meridiem
        let barePattern = #"(?<![\d:])(\d{1,2}):(\d{2})(?![:\d])"# + meridiem

        func resolve(_ pattern: String) -> (Int, Int)? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            let full = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: full) {
                guard let hRange = Range(match.range(at: 1), in: text),
                      let mRange = Range(match.range(at: 2), in: text),
                      var hour = Int(text[hRange]), let minute = Int(text[mRange]),
                      (0...59).contains(minute) else { continue }
                let ampm = Range(match.range(at: 3), in: text).map { text[$0].lowercased() }
                let arabic = Range(match.range(at: 4), in: text).map { String(text[$0]) }
                let isPM = ampm == "p" || arabic == "م"
                let isAM = ampm == "a" || arabic == "ص"
                if isPM && hour < 12 { hour += 12 }
                if isAM && hour == 12 { hour = 0 }
                guard (0...23).contains(hour) else { continue }
                return (hour, minute)
            }
            return nil
        }
        return resolve(markerPattern) ?? resolve(barePattern)
    }

    /// "يوم 07-04" with NO year (real InstaPay format). Ambiguous between
    /// MM-DD and DD-MM: both readings are built in the current year
    /// (rolled back a year if that lands in the future) and the plausible
    /// candidate closest to now wins — instant-transfer SMS are captured
    /// within days, so recency is the strongest signal available.
    static func parseNoYearDate(from text: String, now: Date = Date()) -> Date? {
        let pattern = #"يوم\s+(\d{1,2})[-/](\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text),
              let first = Int(text[firstRange]), let second = Int(text[secondRange]) else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        func build(month: Int, day: Int) -> Date? {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = 12
            guard var date = calendar.date(from: parts),
                  calendar.component(.day, from: date) == day else { return nil }
            if date > now.addingTimeInterval(86_400) { // Future → it was last year.
                parts.year = year - 1
                guard let lastYear = calendar.date(from: parts) else { return nil }
                date = lastYear
            }
            return date
        }
        let candidates = [build(month: first, day: second), build(month: second, day: first)]
            .compactMap { $0 }
        return candidates.min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    /// من <name> for receives, إلى/الى <name> for sends. Ends at sentence
    /// boundaries or bank boilerplate (عبر/via/بتاريخ/يوم/الرصيد/المتاح).
    static func extractTransferCounterparty(from text: String, isReceive: Bool) -> String? {
        let marker = isReceive ? #"(?:\bمن\b|\bfrom\b)"# : #"(?:\bإلى\b|\bالى\b|\bto\b)"#
        let pattern = marker + #"\s+(.+?)(?:\s+رقم مرجعي|\s+رقم المرجع|\s+عبر|\s+via\s|\s+بتاريخ|\s+يوم\s|\s+الرصيد|\s+المتاح|\s+الساعه|\s+الساعة|\.\s|\.$|;|\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.count >= 2 ? name : nil
    }

    /// Currency-adjacent amounts win over bare numbers (an SMS also
    /// carries card digits, dates, balances — the transaction amount is
    /// the one glued to a currency marker; the FIRST such pair is the
    /// transaction, later ones are usually the remaining balance).
    static func extractAmountAndCurrency(from text: String) -> (Decimal?, String) {
        let currencyMap: [(pattern: String, code: String)] = [
            ("EGP", "EGP"), ("LE", "EGP"), ("L.E", "EGP"), ("جنيه", "EGP"), ("ج.م", "EGP"), ("جم", "EGP"),
            ("USD", "USD"), ("\\$", "USD"),
            ("EUR", "EUR"), ("€", "EUR"),
            ("GBP", "GBP"), ("£", "GBP")
        ]
        let number = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
        for entry in currencyMap {
            // currency before amount ("EGP 350.50") or after ("350.50 EGP",
            // "٣٥٠ جنيه").
            for pattern in ["\(entry.pattern)\\s*\(number)", "\(number)\\s*\(entry.pattern)"] {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else { continue }
                let numberString = text[range].replacingOccurrences(of: ",", with: "")
                if let amount = Decimal(string: numberString, locale: Locale(identifier: "en_US_POSIX")),
                   amount > 0 {
                    return (amount, entry.code)
                }
            }
        }
        return (nil, "EGP")
    }

    /// Merchant follows "at" / "في" / "لدى" and ends at "on <date>" / the
    /// next sentence-ish boundary. Bank formats vary — real samples will
    /// tighten this.
    static func extractMerchant(from text: String) -> String? {
        // Boundary subtlety: merchants contain dots ("AMAZON.EG"), so only
        // a SENTENCE period (dot followed by whitespace or end) terminates
        // the merchant, alongside " on <date>", Arabic date markers,
        // semicolons, and newlines.
        // Markers/boundaries grown from the user's REAL bank SMS:
        // "… عند Talabat يوم 06/07/26 الساعه 12:31 المتاح …" — merchant
        // follows عند, and يوم/الساعه/المتاح terminate it.
        let patterns = [
            #"(?:\bat\b|\bعند\b|\bفي\b|\bلدى\b)\s+(.+?)(?:\s+on\s|\s+بتاريخ\s|\s+يوم\s|\s+الساعه|\s+الساعة|\s+المتاح|\.\s|\.$|;|\n|$)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let merchant = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if merchant.count >= 2 { return merchant }
        }
        return nil
    }
}

// MARK: - DuplicateGuard
// Wallet intent, bank SMS, and manual entry can all record the SAME
// purchase. Before an automated path inserts, it asks: does a transaction
// with this exact amount already exist within ±3 hours? Amount+time is
// the robust key — merchant strings differ wildly between sources
// ("AMAZON.EG CAIRO" on SMS vs "Amazon" from the wallet).
public struct DuplicateGuard {
    private let databaseManager: DatabaseManager
    private let window: TimeInterval = 3 * 60 * 60

    public init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// O(log n) — rides the date index.
    public func existingDuplicate(amount: Decimal, around date: Date) throws -> Persistence.Transaction? {
        try databaseManager.dbQueue().read { db in
            try Persistence.Transaction
                .filter(GRDB.Column("amount") == "\(amount)")
                .filter(GRDB.Column("date") >= date.addingTimeInterval(-window))
                .filter(GRDB.Column("date") <= date.addingTimeInterval(window))
                .fetchOne(db)
        }
    }
}

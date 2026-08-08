import Foundation
import CoreGraphics
import Vision

// MARK: - ReceiptOCRService (blueprint Phase 2.2)
// On-device text recognition + heuristics for amount/merchant/date/currency.
// The heuristics below were tuned against the user's real receipt samples
// (10 receipts: Egyptian + European travel, English/French/Spanish/Catalan),
// which surfaced the concrete traps each rule addresses — see inline notes.
// Still strictly review-before-commit: OCR output is never trusted silently.
public struct ReceiptOCRService {
    public init() {}

    /// `orientation` MUST be the image's EXIF orientation. iPhone camera
    /// photos store pixels unrotated with an orientation flag; without
    /// forwarding it, Vision sees sideways text — recognition still mostly
    /// works (it auto-detects per line) but every bounding box is rotated,
    /// which silently destroys the row-merging and merchant-prominence
    /// geometry. Discovered by running the probe on the user's real HEIC
    /// receipts: "line heights" of 0.5 were actually line lengths.
    /// `knownMerchantKeywords`: lowercased brand keywords (typically
    /// CategoryMatcher's table, i.e. the user's merchant list) — rows
    /// containing one get a decisive merchant-scoring boost. Passed in
    /// rather than imported so this service stays a pure OCR component.
    public func extractCandidates(
        from image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        knownMerchantKeywords: [String] = []
    ) throws -> ReceiptCandidates {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // English first per the user's receipt mix; Arabic kept for local
        // receipts; French/Spanish cover the travel receipts in the sample
        // set (CARETTE, Mercadona, RATP…).
        request.recognitionLanguages = ["en", "ar", "fr", "es"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])

        // Vision's boundingBox is normalized, origin bottom-left; convert
        // to top-origin so "0 = top of receipt" throughout.
        let lines: [OCRLine] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return OCRLine(
                text: text,
                normalizedHeight: box.height,
                topOffset: 1 - box.maxY,
                leftOffset: box.minX,
                normalizedWidth: box.width
            )
        }
        return extractCandidates(fromOCRLines: lines, knownMerchantKeywords: knownMerchantKeywords)
    }

    /// String-only convenience for tests/callers without geometry: each
    /// string is its own row at uniform prominence.
    func extractCandidates(fromLines lines: [String]) -> ReceiptCandidates {
        extractCandidates(fromOCRLines: lines.enumerated().map { index, text in
            OCRLine(
                text: text,
                normalizedHeight: 0.02,
                topOffset: CGFloat(index) * 0.03,
                leftOffset: 0
            )
        })
    }

    func extractCandidates(
        fromOCRLines lines: [OCRLine],
        knownMerchantKeywords: [String] = []
    ) -> ReceiptCandidates {
        // Row reconstruction first: receipts are COLUMNAR ("TOTAL (€)"
        // left, "13,75" right), and Vision often emits label and value as
        // separate observations. Without re-joining rows, the total's
        // amount sits on a keyword-less line and keyword priority misses
        // it — observed on the Mercadona sample, where the cash-tendered
        // 50,00 would then beat the true 13,75 total.
        let rows = Self.mergeIntoRows(lines)
        let rowTexts = rows.map(\.text)
        let total = findTotalAmount(inRows: rowTexts)
        return ReceiptCandidates(
            amount: total,
            date: findDateLikePattern(in: rowTexts),
            merchant: findMerchantName(in: rows, knownMerchantKeywords: knownMerchantKeywords),
            lineItems: Self.extractLineItems(fromRows: rowTexts, total: total),
            currency: Self.detectCurrency(in: rowTexts),
            rawLines: rowTexts
        )
    }

    // MARK: - Row reconstruction

    /// Clusters observations whose vertical centers sit within ~60% of a
    /// line height of each other, then joins each cluster left-to-right.
    /// O(n log n) for the sort; n = observations per receipt (small).
    static func mergeIntoRows(_ lines: [OCRLine]) -> [OCRLine] {
        guard !lines.isEmpty else { return [] }
        let sorted = lines.sorted { $0.topOffset < $1.topOffset }

        var rows: [[OCRLine]] = []
        var current: [OCRLine] = [sorted[0]]
        for line in sorted.dropFirst() {
            let reference = current[0]
            // Capped: a tall logo line (RATP sample) otherwise gets a
            // tolerance bigger than the receipt's line spacing and
            // swallows the row beneath it.
            let tolerance = min(max(reference.normalizedHeight, line.normalizedHeight) * 0.6, 0.025)
            if abs(line.topOffset - reference.topOffset) <= tolerance {
                current.append(line)
            } else {
                rows.append(current)
                current = [line]
            }
        }
        rows.append(current)

        return rows.map { cluster in
            let ordered = cluster.sorted { $0.leftOffset < $1.leftOffset }
            let minLeft = ordered[0].leftOffset
            let maxRight = ordered.map { $0.leftOffset + $0.normalizedWidth }.max() ?? minLeft
            return OCRLine(
                text: ordered.map(\.text).joined(separator: " "),
                normalizedHeight: ordered.map(\.normalizedHeight).max() ?? 0,
                topOffset: ordered[0].topOffset,
                leftOffset: minLeft,
                normalizedWidth: maxRight - minLeft
            )
        }
    }

    // MARK: - Amount

    /// Words that mark a row as carrying the payable total. Multi-language,
    /// from the receipt samples: EN total, FR montant/ttc, ES/CA importe/
    /// total, AR الاجمالي/المجموع.
    private static let totalKeywords: [String] = [
        "total", "montant", "importe", "ttc",
        "اجمالي", "إجمالي", "الاجمالي", "المجموع"
    ]

    /// Words marking rows that hold MONEY GIVEN, not money owed — cash
    /// tendered and change. These rows regularly carry the biggest number
    /// on the receipt (Mercadona: tendered 50,00 vs total 13,75), so they
    /// are excluded before any largest-value comparison.
    private static let tenderKeywords: [String] = [
        "cash", "change", "especes", "espèces", "rendu", "efectivo",
        "cambiar", "lliurament", "devolució", "devolucio", "tender",
        "نقدي", "الباقي", "المدفوع"
    ]

    /// Strategy, validated against all 10 samples:
    ///  1. Among rows containing a total keyword (minus tender rows), take
    ///     the LARGEST value — beats "Sub-total"/"Total discounts" rows,
    ///     which are always ≤ the payable total.
    ///  2. If no keyword row carries a number (logo-style totals like
    ///     Swatch's "***** 330,00 € *****"), fall back to the largest
    ///     value on any non-tender row.
    /// O(n) over rows.
    func findTotalAmount(inRows rows: [String]) -> Decimal? {
        var keywordLargest: Decimal?
        var overallLargest: Decimal?

        for row in rows {
            let lowered = row.lowercased()
            if Self.tenderKeywords.contains(where: { lowered.contains($0) }) { continue }
            guard let rowMax = Self.largestCurrencyValue(in: row) else { continue }

            if Self.totalKeywords.contains(where: { lowered.contains($0) }) {
                if keywordLargest == nil || rowMax > keywordLargest! { keywordLargest = rowMax }
            }
            if overallLargest == nil || rowMax > overallLargest! { overallLargest = rowMax }
        }
        return keywordLargest ?? overallLargest
    }

    /// Largest "money-looking" number in one row: digits + exactly two
    /// decimals, "." or "," separator (European receipts use commas), with
    /// an optional space after the separator (OCR reads "119, 96" on the
    /// C&A sample). The `(?!\s*%)` lookahead excludes tax RATES — on the
    /// Five Guys sample a "10.00% Subtotal" row otherwise beat the total.
    static func largestCurrencyValue(in text: String) -> Decimal? {
        let pattern = #"[0-9]+[.,] ?[0-9]{2}\b(?!\s*%)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let normalized = normalizeEasternArabicDigits(in: text)
        var largest: Decimal?
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        for match in matches {
            guard let range = Range(match.range, in: normalized) else { continue }
            let numberString = normalized[range]
                .replacingOccurrences(of: " ", with: "") // "119, 96" → "119,96".
                .replacingOccurrences(of: ",", with: ".")
            if let value = Decimal(string: numberString), largest == nil || value > largest! {
                largest = value
            }
        }
        return largest
    }

    // MARK: - Currency

    /// Symbol/word → ISO code, checked in order. Egyptian pound is the
    /// default when nothing matches (home currency); euro receipts in the
    /// sample set made currency detection necessary at all — a travel
    /// dinner logged as 113 EGP instead of 113 EUR would corrupt every
    /// downstream aggregate.
    static func detectCurrency(in rows: [String]) -> String {
        let joined = rows.joined(separator: " ").lowercased()
        if joined.contains("€") || joined.contains("eur") { return "EUR" }
        if joined.contains("$") || joined.contains("usd") { return "USD" }
        if joined.contains("£") || joined.contains("gbp") { return "GBP" }
        if joined.contains("ج.م") || joined.contains("egp") || joined.contains("جنيه") { return "EGP" }
        return "EGP"
    }

    // MARK: - Merchant

    /// Rows that are receipt plumbing, not merchant names. Grown from the
    /// samples: greetings (BIENVENUE/¡Comparte!), legal ids (CIF/SIREN),
    /// staff/table lines (vendeur/servi par), contact lines. Substring
    /// match on the lowercased row; conservative on purpose — scoring,
    /// not exclusion, makes the final call.
    private static let merchantNoiseKeywords: [String] = [
        "receipt", "invoice", "tax", "vat", "phone", "telephone", "telefon",
        "cashier", "order", "table", "date", "time", "total", "subtotal",
        "change", "welcome", "bienvenue", "bienvenido", "comparte",
        "facture", "factura", "ticket", "vendeur", "caissier", "servi par",
        "justificatif", "salle", "cif", "nif", "siren", "siret", "http",
        "www", "tel:", "tél",
        // Thank-you footers — bold enough to out-score the real name on
        // the Soleil D'Or sample.
        "merci", "thank", "gracias", "bientôt", "bientot",
        // Payment rows, terminal output, register ids.
        "contactless", "mastercard", "visa", "cajero", "caja",
        "verified", "approved", "recepción", "recepcion",
        // Company-registry boilerplate (Spanish receipts print it large
        // enough to beat the brand line — the Adidas sample).
        "inscrita", "registro", "tomo", "folio",
        "فاتورة", "ضريب", "تليفون", "هاتف", "كاشير",
        "طلب", "تاريخ", "وقت", "اجمالي", "إجمالي", "الرقم", "عنوان",
        "شارع", "فرع", "مرحبا", "شكرا"
    ]

    /// Street words in the sample languages — address lines regularly win
    /// on position when the merchant is a logo image the OCR can't read
    /// (the Adidas sample), so they get named penalties.
    private static let streetKeywords: [String] = [
        "paseo", "calle", "avda", "avenida", "rue", "boulevard", "blvd",
        "place du", "street", "cedex", "شارع"
    ]

    /// Merchant = most PROMINENT plausible row — with one trump card: a
    /// row containing a KNOWN merchant keyword (the CategoryMatcher table,
    /// i.e. the user's own merchant list) wins over pure geometry. Paid
    /// for by the two logo-image receipts in the sample set (Five Guys,
    /// C&A), where the brand never appears as big text, only in small
    /// legal lines ("FIVE GUYS SPAIN S.L.U.", "C&A Modas SLU"). This also
    /// means every merchant the user adds to the table improves receipt
    /// scanning for free.
    ///
    /// Every geometric penalty below is likewise paid for by a specific
    /// failure on the user's real receipts:
    ///  - noise/street words (address beat the logo-only Adidas header)
    ///  - rows carrying money values ("Nombre d'articles: 119,96")
    ///  - rows carrying dates ("Recepción: ROBERT IONUT 26/06/2026")
    ///  - VERTICAL text, height > width (sideways text from a background
    ///    receipt in the frame won on the Soleil D'Or sample)
    ///  - digit-heavy / leading-digit / overlong rows (ids, addresses,
    ///    boilerplate). O(n) over rows.
    func findMerchantName(
        in lines: [OCRLine],
        knownMerchantKeywords: [String] = []
    ) -> String? {
        guard !lines.isEmpty else { return nil }
        let maxHeight = lines.map(\.normalizedHeight).max() ?? 0.01
        let dateProbe = try? NSRegularExpression(pattern: #"\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}"#)

        var best: (line: OCRLine, score: Double)?
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard text.count >= 3 else { continue }

            var score = 0.0
            score += (line.normalizedHeight / maxHeight) * 3.0
            if line.topOffset < 0.2 { score += 2.0 } else if line.topOffset < 0.4 { score += 0.8 }
            if line.topOffset > 0.7 { score -= 1.5 } // Bottom third: legal text, terminal output.

            let loweredForBrand = text.lowercased()
            if knownMerchantKeywords.contains(where: { loweredForBrand.contains($0) }) {
                score += 5.0 // Known brand trumps geometry.
            }

            let lowered = text.lowercased()
            if Self.merchantNoiseKeywords.contains(where: { lowered.contains($0) }) { score -= 4.0 }
            if Self.streetKeywords.contains(where: { lowered.contains($0) }) { score -= 3.0 }
            if Self.largestCurrencyValue(in: text) != nil { score -= 3.0 }
            if let dateProbe,
               dateProbe.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                score -= 2.0
            }
            if line.normalizedHeight > line.normalizedWidth * 1.2 { score -= 4.0 } // Vertical/rotated text.
            if text.contains(": ") || text.hasSuffix(":") { score -= 1.5 } // "Label : value" rows.
            let digitCount = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
            if Double(digitCount) / Double(text.count) > 0.4 { score -= 3.0 }
            if text.first?.isNumber == true { score -= 2.0 } // "3407 BC Barcelona…", "08007 Barcelona".
            if text.count > 40 { score -= 2.0 }

            if best == nil || score > best!.score {
                best = (line, score)
            }
        }
        if let best, best.score > 0 {
            return best.line.text.trimmingCharacters(in: .whitespaces)
        }
        return lines.first { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }?.text
    }

    // MARK: - Date

    /// Month names seen on the samples (French "20 JUIN 2026") plus
    /// English; extend as new languages appear.
    private static let monthNames: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5,
        "june": 6, "july": 7, "august": 8, "september": 9, "october": 10,
        "november": 11, "december": 12,
        "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4,
        "mai": 5, "juin": 6, "juillet": 7, "août": 8, "aout": 8,
        "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12,
        "decembre": 12
    ]

    /// Rows whose date should win over stray dates elsewhere.
    private static let dateKeywords: [String] = [
        "date", "data", "fecha", "edité", "edite", "تاريخ"
    ]

    /// Extracts the printed receipt date. Formats from the samples:
    /// numeric day-first (25/06/26, 22/6/2026), year-first (2026-06-21),
    /// French month names (samedi 20 juin 2026), Eastern Arabic digits.
    /// Plausibility window (not future, ≤3 years old) is load-bearing:
    /// the RATP sample prints card-validity dates in 2035/2036 that would
    /// otherwise win. Keyword rows beat stray dates; otherwise the most
    /// recent plausible date wins (a captured receipt is usually fresh).
    /// O(n) over rows.
    func findDateLikePattern(in lines: [String]) -> Date? {
        // The day-first year group, in match-priority order:
        //  1. 2-digit year glued to a HH:MM time — "24/06/2618:30" on the
        //     Swatch sample; MUST come before the 4-digit branch or the
        //     regex eats "2618" as a year and never retries;
        //  2. 4 digits ("22/6/2026");
        //  3. 2 digits not followed by another digit ("25/06/26").
        let dayFirst = #"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}(?=\d{2}:)|\d{4}|\d{2}(?!\d))"#
        let yearFirst = #"(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})"#
        let monthName = #"(\d{1,2})\s+([\p{L}]+)\s+(\d{4})"#
        guard let dayFirstRegex = try? NSRegularExpression(pattern: dayFirst),
              let yearFirstRegex = try? NSRegularExpression(pattern: yearFirst),
              let monthNameRegex = try? NSRegularExpression(pattern: monthName) else { return nil }

        var keywordCandidates: [Date] = []
        var otherCandidates: [Date] = []

        for line in lines {
            let normalized = Self.normalizeEasternArabicDigits(in: line)
            let range = NSRange(normalized.startIndex..., in: normalized)
            var found: [Date] = []

            // Year-first before day-first: "2026-06-21" also matches the
            // day-first pattern with nonsense groups.
            for match in yearFirstRegex.matches(in: normalized, range: range) {
                if let date = Self.makeDate(
                    day: Self.intGroup(3, of: match, in: normalized),
                    month: Self.intGroup(2, of: match, in: normalized),
                    year: Self.intGroup(1, of: match, in: normalized)
                ) { found.append(date) }
            }
            if found.isEmpty {
                for match in dayFirstRegex.matches(in: normalized, range: range) {
                    if let date = Self.makeDate(
                        day: Self.intGroup(1, of: match, in: normalized),
                        month: Self.intGroup(2, of: match, in: normalized),
                        year: Self.intGroup(3, of: match, in: normalized)
                    ) { found.append(date) }
                }
            }
            if found.isEmpty {
                for match in monthNameRegex.matches(in: normalized, range: range) {
                    guard let monthRange = Range(match.range(at: 2), in: normalized) else { continue }
                    let monthWord = normalized[monthRange].lowercased()
                    guard let month = Self.monthNames[monthWord] else { continue }
                    if let date = Self.makeDate(
                        day: Self.intGroup(1, of: match, in: normalized),
                        month: month,
                        year: Self.intGroup(3, of: match, in: normalized)
                    ) { found.append(date) }
                }
            }

            let lowered = normalized.lowercased()
            if Self.dateKeywords.contains(where: { lowered.contains($0) }) {
                keywordCandidates.append(contentsOf: found)
            } else {
                otherCandidates.append(contentsOf: found)
            }
        }

        return keywordCandidates.max() ?? otherCandidates.max()
    }

    private static func intGroup(_ index: Int, of match: NSTextCheckingResult, in text: String) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    /// Validates ranges and plausibility; noon local avoids off-by-one-day
    /// surprises around midnight/timezone edges.
    private static func makeDate(day: Int?, month: Int?, year: Int?) -> Date? {
        guard var year, let month, let day,
              (1...31).contains(day), (1...12).contains(month) else { return nil }
        if year < 100 { year += 2000 } // "26" → 2026.

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              // Reject impossible dates a lenient calendar would roll over
              // (31/02) by round-tripping the components.
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }

        let now = Date()
        guard date <= now.addingTimeInterval(60 * 60 * 24),
              date >= now.addingTimeInterval(-3 * 365 * 24 * 60 * 60)
        else { return nil }
        return date
    }

    /// Item lines: a name plus a price on the same row ("1 CREMA CATALANA
    /// 2,75"). Heuristics per real samples: the price is the row's last
    /// currency-like value, must not exceed the receipt total, and rows
    /// that are totals/tender/tax/dates/plumbing are skipped. Leading
    /// quantity markers ("1 x", "6") are stripped from the name. This is
    /// display-and-history data reviewed by the user — imperfection is
    /// acceptable, silence isn't. O(rows).
    static func extractLineItems(fromRows rows: [String], total: Decimal?) -> [ReceiptCandidates.LineItem] {
        let skipKeywords = totalKeywords + tenderKeywords + [
            "tva", "vat", "iva", "tax", "ضريب", "balance", "رصيد",
            "date", "تاريخ", "thank", "merci", "gracias", "شكرا",
            "subtotal", "discount", "خصم"
        ]
        var items: [ReceiptCandidates.LineItem] = []
        for row in rows {
            guard items.count < 30 else { break } // Receipts don't have more; runaway OCR does.
            let lowered = row.lowercased()
            if skipKeywords.contains(where: { lowered.contains($0) }) { continue }
            guard let price = largestCurrencyValue(in: row), price > 0 else { continue }
            if let total, price > total { continue } // Bigger than the total: id/balance noise.

            // Name = the row with the price token and separators removed.
            var name = normalizeEasternArabicDigits(in: row)
            // Strip ONLY the final space-delimited number token (the price
            // column). Allowing spaces inside the tail ate product codes:
            // "MOUSSE KOKO P-4 1,20" lost its "-4".
            if let range = name.range(of: #"\s+[0-9][0-9,.]*\s*$"#, options: .regularExpression) {
                name.removeSubrange(range)
            }
            name = name.replacingOccurrences(of: "^\\s*[0-9]+\\s*[xX×]?\\s*", with: "", options: .regularExpression) // Leading qty.
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .-*×x\t"))
            guard name.count >= 3 else { continue }
            // Mostly-digit "names" are barcodes/refs.
            let digits = name.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
            guard Double(digits) / Double(name.count) < 0.4 else { continue }
            items.append(ReceiptCandidates.LineItem(name: name, price: price))
        }
        return items
    }

    /// ٠١٢٣٤٥٦٧٨٩ → 0123456789, and the Arabic decimal separator "٫" → ".".
    static func normalizeEasternArabicDigits(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "٠": result.append("0")
            case "١": result.append("1")
            case "٢": result.append("2")
            case "٣": result.append("3")
            case "٤": result.append("4")
            case "٥": result.append("5")
            case "٦": result.append("6")
            case "٧": result.append("7")
            case "٨": result.append("8")
            case "٩": result.append("9")
            case "٫": result.append(".")
            default: result.append(character)
            }
        }
        return result
    }
}

/// One recognized text element with the geometry the heuristics need.
/// All values normalized 0…1; topOffset 0 = top of receipt, leftOffset
/// 0 = left edge (used to re-join columnar rows in reading order).
/// Width defaults to 1 so text-only callers never trip the vertical-text
/// (height > width) merchant penalty.
public struct OCRLine {
    public let text: String
    public let normalizedHeight: CGFloat
    public let topOffset: CGFloat
    public let leftOffset: CGFloat
    public let normalizedWidth: CGFloat

    public init(
        text: String,
        normalizedHeight: CGFloat,
        topOffset: CGFloat,
        leftOffset: CGFloat = 0,
        normalizedWidth: CGFloat = 1
    ) {
        self.text = text
        self.normalizedHeight = normalizedHeight
        self.topOffset = topOffset
        self.leftOffset = leftOffset
        self.normalizedWidth = normalizedWidth
    }
}

public struct ReceiptCandidates {
    public struct LineItem: Equatable {
        public let name: String
        public let price: Decimal

        public init(name: String, price: Decimal) {
            self.name = name
            self.price = price
        }
    }

    public let amount: Decimal?
    public let date: Date?
    public let merchant: String?
    /// Detected item lines (name + price) for per-item price history.
    public let lineItems: [LineItem]
    /// ISO code guessed from currency symbols/words on the receipt;
    /// defaults to EGP (home currency) when nothing matches.
    public let currency: String
    /// Raw reconstructed rows, shown in the review screen so a wrong guess
    /// can be diagnosed without re-photographing.
    public let rawLines: [String]
}

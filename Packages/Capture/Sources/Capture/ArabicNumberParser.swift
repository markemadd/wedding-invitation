import Foundation

// MARK: - ArabicNumberParser
// Informal Egyptian Arabic speech usually transcribes amounts as WORDS
// ("خمسين جنيه", "مية وخمسة وسبعين"), not digits — so the voice path needs
// a word-level number parser, not just a digit regex. This is a pragmatic
// table of Egyptian colloquial + Modern Standard spellings covering the
// realistic range of a spoken purchase amount (units, teens, tens,
// hundreds, thousands, and "ونص" = +0.5). It is NOT a general Arabic
// numeral grammar — the review screen remains the safety net, and the
// Phase 5 LLM later replaces this parser wholesale.
public struct ArabicNumberParser {
    /// word → value. Multiple spellings per number because Egyptian
    /// dialect spelling is unstandardized (تلاته/ثلاثة, مية/ميه/مائة …).
    private static let wordValues: [String: Decimal] = [
        // Units 1–9 (dialect + MSA spellings)
        "واحد": 1, "واحده": 1, "واحدة": 1,
        "اتنين": 2, "اثنين": 2, "إثنين": 2,
        "تلاته": 3, "تلاتة": 3, "ثلاثه": 3, "ثلاثة": 3,
        "اربعه": 4, "اربعة": 4, "أربعة": 4,
        "خمسه": 5, "خمسة": 5,
        "سته": 6, "ستة": 6,
        "سبعه": 7, "سبعة": 7,
        "تمانيه": 8, "تمانية": 8, "ثمانيه": 8, "ثمانية": 8, "تمنيه": 8,
        "تسعه": 9, "تسعة": 9,
        // 10–19
        "عشره": 10, "عشرة": 10,
        "حداشر": 11, "احداشر": 11, "إحدى عشر": 11,
        "اطناشر": 12, "اتناشر": 12, "إثنا عشر": 12,
        "تلطاشر": 13, "تلاتاشر": 13, "ثلاثة عشر": 13,
        "اربعطاشر": 14, "اربعتاشر": 14, "أربعة عشر": 14,
        "خمسطاشر": 15, "خمستاشر": 15, "خمسة عشر": 15,
        "سطاشر": 16, "ستاشر": 16, "ستة عشر": 16,
        "سبعطاشر": 17, "سبعتاشر": 17, "سبعة عشر": 17,
        "تمنطاشر": 18, "تمنتاشر": 18, "ثمانية عشر": 18,
        "تسعطاشر": 19, "تسعتاشر": 19, "تسعة عشر": 19,
        // Tens 20–90
        "عشرين": 20,
        "تلاتين": 30, "ثلاثين": 30,
        "اربعين": 40, "أربعين": 40,
        "خمسين": 50,
        "ستين": 60,
        "سبعين": 70,
        "تمانين": 80, "ثمانين": 80,
        "تسعين": 90,
        // Hundreds
        "ميه": 100, "مية": 100, "مائة": 100, "ماية": 100,
        "ميتين": 200, "مئتين": 200,
        "تلتميه": 300, "تلتمية": 300, "ثلاثمائة": 300, "تلاتمية": 300,
        "ربعميه": 400, "ربعمية": 400, "اربعمية": 400, "أربعمائة": 400,
        "خمسميه": 500, "خمسمية": 500, "خمسمائة": 500,
        "ستميه": 600, "ستمية": 600, "ستمائة": 600,
        "سبعميه": 700, "سبعمية": 700, "سبعمائة": 700,
        "تمنميه": 800, "تمنمية": 800, "ثمانمائة": 800,
        "تسعميه": 900, "تسعمية": 900, "تسعمائة": 900,
        // Thousands
        "الف": 1_000, "ألف": 1_000,
        "الفين": 2_000, "ألفين": 2_000,
        // "ونص" adds a half (…جنيه ونص)
        "نص": 0.5, "نصف": 0.5
    ]

    /// Multiplier words that scale what came before ("تلاتة الاف" = 3000).
    private static let multiplierValues: [String: Decimal] = [
        "الاف": 1_000, "آلاف": 1_000, "الف": 1_000, "ألف": 1_000
    ]

    public init() {}

    public struct ExtractedNumber: Equatable {
        public let value: Decimal
        /// Tokens of the utterance that were NOT part of the number — the
        /// caller's merchant hint.
        public let remainingTokens: [String]
    }

    /// Scans tokens for the longest run of number words (allowing the
    /// Arabic conjunction "و" glued or separate) and composes their value:
    /// additive within a scale, multiplicative for thousand-words.
    /// O(n) over token count.
    public func extractNumber(fromTokens tokens: [String]) -> ExtractedNumber? {
        var total = Decimal(0)
        var matchedAny = false
        var consumedIndices = Set<Int>()

        for (index, rawToken) in tokens.enumerated() {
            // "وخمسين" → "خمسين": the conjunction glues onto number words.
            let token = rawToken.hasPrefix("و") && rawToken.count > 1
                ? String(rawToken.dropFirst())
                : rawToken

            if let value = Self.wordValues[token] {
                total += value
                matchedAny = true
                consumedIndices.insert(index)
            } else if matchedAny, let multiplier = Self.multiplierValues[token] {
                total *= multiplier
                consumedIndices.insert(index)
            }
        }

        guard matchedAny, total > 0 else { return nil }
        let remaining = tokens.enumerated()
            .filter { !consumedIndices.contains($0.offset) }
            .map(\.element)
        return ExtractedNumber(value: total, remainingTokens: remaining)
    }
}

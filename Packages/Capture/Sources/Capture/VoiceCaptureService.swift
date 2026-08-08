import Foundation
import Speech

// MARK: - VoiceCaptureService (blueprint Phase 2.4)
// Transcribes a recorded audio file to text, strictly on-device. Parsing
// the text into a draft happens in VoiceDraftParser; the same
// review-before-commit pattern as OCR applies. Do not wait for the Phase 5
// LLM to make this usable — ship the regex first pass now, upgrade later.
public final class VoiceCaptureService {
    public enum Language: String, CaseIterable {
        case arabic = "ar"
        case english = "en"
    }

    // ar-EG isn't always available on-device; ar-SA is the documented
    // fallback the blueprint calls for. WhisperKit only enters the picture
    // if real-world testing shows SFSpeechRecognizer can't handle Egyptian
    // Arabic phrasing (Phase 0 watch-out: don't add it prematurely).
    // SFSpeechRecognizer is single-locale, so mixed-language support is a
    // user-facing toggle rather than automatic code-switching — WhisperKit
    // would lift that limitation if we adopt it.
    private let recognizer: SFSpeechRecognizer?

    public init(language: Language = .arabic) {
        switch language {
        case .arabic:
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-EG"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
        case .english:
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    public func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true // Never sends audio off-device — non-negotiable.

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}

public enum VoiceError: Error, LocalizedError {
    case recognizerUnavailable

    public var errorDescription: String? {
        "Arabic speech recognition is not available on this device."
    }
}

// MARK: - VoiceDraftParser
// Lightweight first-pass parse of the transcription: find the amount,
// treat the rest as a merchant hint for CategoryMatcher. Deliberately
// simple — a wrong parse is always caught by the review screen, and the
// Phase 5 LLM later replaces this with structured extraction.
public struct VoiceDraftParser {
    public init() {}

    public struct ParsedUtterance: Equatable {
        public let amount: Decimal?
        /// The utterance with the amount removed — a merchant/category hint.
        public let merchantHint: String
    }

    /// Currency words carry no information for the merchant hint.
    private static let currencyWords: Set<String> = [
        "جنيه", "جنية", "جم", "pound", "pounds", "egp", "le"
    ]

    /// Two passes, O(n) over the utterance length:
    ///  1. digits (Western or Eastern Arabic — "50.25", "٥٠") — the case
    ///     where the recognizer emitted numerals;
    ///  2. Arabic number WORDS ("خمسين", "مية وخمسة وسبعين") via
    ///     ArabicNumberParser — the common case for informal Egyptian
    ///     speech, which transcribes amounts as words.
    public func parse(_ utterance: String) -> ParsedUtterance {
        let normalized = ReceiptOCRService.normalizeEasternArabicDigits(in: utterance)

        // Pass 1: digit amounts.
        let pattern = #"[0-9]+(?:[.,][0-9]{1,2})?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
           ),
           let range = Range(match.range, in: normalized) {
            let numberString = normalized[range].replacingOccurrences(of: ",", with: ".")
            var remainder = normalized
            remainder.removeSubrange(range)
            return ParsedUtterance(
                amount: Decimal(string: numberString),
                merchantHint: Self.stripCurrencyWords(from: remainder)
            )
        }

        // Pass 2: spoken Arabic number words.
        let tokens = normalized.split(separator: " ").map(String.init)
        if let extracted = ArabicNumberParser().extractNumber(fromTokens: tokens) {
            return ParsedUtterance(
                amount: extracted.value,
                merchantHint: Self.stripCurrencyWords(from: extracted.remainingTokens.joined(separator: " "))
            )
        }

        return ParsedUtterance(amount: nil, merchantHint: Self.stripCurrencyWords(from: normalized))
    }

    private static func stripCurrencyWords(from text: String) -> String {
        text.split(separator: " ")
            .map(String.init)
            .filter { !currencyWords.contains($0.lowercased()) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

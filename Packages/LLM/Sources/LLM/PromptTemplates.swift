import Foundation

// MARK: - Prompt templates (blueprint Phase 5.1)
// Exactly three narrow templates — no open-ended chat mode. The LLM's job
// is language only: classification among KNOWN options, grounded Q&A, and
// narration of numbers computed elsewhere. It never does arithmetic or
// pattern detection; Phases 3–4's deterministic code owns those.
public enum PromptTemplates {
    /// 1. Categorization: merchant + amount → one category name from the
    /// provided list, as strict JSON. Treated as a classifier choosing
    /// among known options, never a free-text generator.
    public static func categorization(merchant: String, amount: String, categories: [String]) -> String {
        """
        You classify a purchase into exactly one category.
        Categories (choose ONE, verbatim): \(categories.joined(separator: ", "))
        Purchase: merchant "\(merchant)", amount \(amount).
        Reply with ONLY this JSON, nothing else:
        {"category": "<one of the listed categories>"}
        """
    }

    /// 2. Grounded chat: a small injected context block of REAL numbers,
    /// so answers reference actual data instead of hallucinating.
    public static func groundedQuestion(context: String, question: String) -> String {
        """
        You are a personal-finance assistant. Answer ONLY from the data
        below; if the data doesn't contain the answer, say so plainly.
        Never invent numbers. Keep answers to a few sentences.

        DATA:
        \(context)

        QUESTION: \(question)
        """
    }

    /// 3. Forecast narration: Monte Carlo percentiles → plain language.
    public static func forecastNarration(
        p10: String, p50: String, p90: String, monthsAhead: Int, successProbability: String?
    ) -> String {
        """
        Turn these net-worth projection results into one short, plain
        paragraph for the owner of the money. No advice, no hype — just
        what the numbers mean. All amounts are EGP.
        Horizon: \(monthsAhead) months.
        Pessimistic (10th percentile): \(p10)
        Median: \(p50)
        Optimistic (90th percentile): \(p90)
        \(successProbability.map { "Probability of reaching the goal: \($0)" } ?? "")
        """
    }

    /// 4. Roast mode (ENHANCEMENTS Wave C2): the same grounded numbers, a
    /// comedic persona. Still narration-only — the model riffs on figures
    /// computed elsewhere, it does not invent spending it hasn't been told
    /// about.
    public static func roastPrompt(context: MizanContext) -> String {
        """
        You are a brutally honest but funny financial roaster.
        The user's spending data this month:
        \(context.summary)
        Give a short, sharp, comedic roast (3-4 sentences max).
        Only reference the numbers above — do not invent spending.
        End with one genuine tip disguised as a joke.
        """
    }

    /// Strict parser for the categorization reply. Rejects anything that
    /// isn't exact JSON with a category from the allowed list — a wrong
    /// or malformed model output must land in review, never in the
    /// database (same review-before-commit rule as OCR/voice).
    public static func parseCategorizationReply(_ reply: String, allowedCategories: [String]) -> String? {
        // Models often wrap JSON in prose or code fences; extract the
        // first {...} block before parsing.
        guard let start = reply.firstIndex(of: "{"),
              let end = reply[start...].firstIndex(of: "}") else { return nil }
        let jsonText = String(reply[start...end])
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let category = object["category"] as? String else { return nil }
        return allowedCategories.contains(category) ? category : nil
    }
}

// MARK: - LanguageModelBackend
// The seam where MLX Swift plugs in. The backend is a protocol so the
// templates/parsers above are testable today, and the heavy mlx-swift
// dependency + quantized model weights (a ~1 GB user-supplied download —
// the app itself makes no network requests) land exactly when the model
// file exists, per the Phase 0 watch-out about not adding MLX early.
public protocol LanguageModelBackend {
    func complete(prompt: String) async throws -> String
}

import Foundation

// MARK: - LLMService (ENHANCEMENTS Wave C)
// The app-facing entry point to on-device inference. The heavy MLX backend
// and its ~1 GB weights are still deferred (blueprint Phase 0 watch-out),
// so a nil backend is the normal state today: `isAvailable` is false and
// the chat screen degrades to a "Model not available" empty state instead
// of crashing. When the weights ship, inject a real LanguageModelBackend
// here and everything above this seam keeps working unchanged.
public final class LLMService {
    private let backend: LanguageModelBackend?

    public init(backend: LanguageModelBackend? = nil) {
        self.backend = backend
    }

    /// Whether a model is actually loaded. The UI gates its send/roast
    /// affordances on this.
    public var isAvailable: Bool { backend != nil }

    /// Grounded question answered from injected real data.
    public func answer(question: String, context: MizanContext) async throws -> String {
        try await complete(PromptTemplates.groundedQuestion(context: context.summary, question: question))
    }

    /// The roasting persona (Wave C2), fired with full monthly context.
    public func roast(context: MizanContext) async throws -> String {
        try await complete(PromptTemplates.roastPrompt(context: context))
    }

    private func complete(_ prompt: String) async throws -> String {
        guard let backend else { throw LLMError.modelUnavailable }
        return try await backend.complete(prompt: prompt)
    }
}

public enum LLMError: Error, LocalizedError {
    case modelUnavailable

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "The on-device model isn't installed yet, so Mizan AI can't answer right now."
        }
    }
}

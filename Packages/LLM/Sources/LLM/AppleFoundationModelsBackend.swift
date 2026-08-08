import Foundation

// MARK: - AppleFoundationModelsBackend (on-device, free, most private)
// Apple's Foundation Models framework ships a ~3B on-device LLM on every
// Apple-Intelligence-capable device (iPhone 15 Pro / A17 Pro and up; iOS 26+).
// When present it is the BEST Mizan AI backend: it runs entirely on-device —
// the injected MizanContext figures never leave the phone — and it costs the
// user nothing and needs no setup or download.
//
// This whole file is compiled ONLY when the SDK actually has FoundationModels
// (Xcode 26 / iOS 26 SDK). On older toolchains (e.g. Xcode 16 / iOS 18 SDK)
// `canImport(FoundationModels)` is false and this compiles to nothing, so the
// app still builds and simply falls back to the other backends. It is also
// gated at runtime with `@available` + an availability check, so on a device
// without Apple Intelligence it reports unavailable rather than crashing.
//
// NOTE: written against Apple's documented API surface (SystemLanguageModel,
// LanguageModelSession). It cannot be compiled or tested until the project is
// built with the iOS 26 SDK — verify the call shapes after that upgrade.
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
public struct AppleFoundationModelsBackend: LanguageModelBackend {
    public init() {}

    /// True only when the device supports Apple Intelligence AND the model is
    /// downloaded and ready. Everything else (unsupported chip, feature off,
    /// model still downloading) reports false so we fall back cleanly.
    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func complete(prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif

import Foundation

// MARK: - RemoteLLMBackend (Mac-as-LAN-server)
// Talks to an OpenAI-compatible chat-completions endpoint the USER runs on
// their OWN machine — Ollama (`/v1/chat/completions` on :11434) or LM Studio
// (:1234). This is an EXPLICIT, opt-in departure from "nothing leaves the
// device": the prompt (which contains the injected MizanContext figures)
// travels to the user-configured host and back. It's meant for a private
// LAN / Tailscale link to the user's own computer — no third-party cloud,
// no credentials. The app defaults this OFF and only builds this backend
// when the user turns it on and supplies a host (mirrors PriceFetchService's
// allowlisted, default-off network posture).
//
// The model's reply is treated as DATA to display, never as instructions.
public struct RemoteLLMBackend: LanguageModelBackend {
    private let endpoint: URL
    private let model: String
    private let session: URLSession

    /// - baseURL: e.g. `http://192.168.1.20:11434` (Ollama) or
    ///   `http://mac.local:1234` (LM Studio). The `/v1/chat/completions`
    ///   path is appended.
    public init(baseURL: URL, model: String, session: URLSession = .shared) {
        self.endpoint = baseURL.appendingPathComponent("v1/chat/completions")
        self.model = model
        self.session = session
    }

    public func complete(prompt: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteLLMError.badResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw RemoteLLMError.server(status: http.statusCode)
        }
        // OpenAI-compatible shape: choices[0].message.content.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RemoteLLMError.unparseable
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum RemoteLLMError: Error, LocalizedError {
    case badResponse
    case server(status: Int)
    case unparseable

    public var errorDescription: String? {
        switch self {
        case .badResponse:
            return "No response from your AI server. Check that it's running and reachable on your network."
        case .server(let status):
            return "Your AI server returned an error (HTTP \(status)). Check the model name is loaded on it."
        case .unparseable:
            return "Your AI server replied in a format Mizan couldn't read (expected an OpenAI-compatible response)."
        }
    }
}

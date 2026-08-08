import Foundation

// MARK: - StockSignalImport (blueprint Phase 6.3)
// The external Cowork task's output channel. Fixed schema, STRICT
// validation — reject anything that doesn't match exactly, never partial-
// import (a Phase 7 checklist item attacks this with malformed files).
// Signals are EPHEMERAL display data: reviewed on screen, then discarded.
// They are never written to any persisted table and never auto-acted on —
// external advice stays external.
public enum StockSignalImport {
    public struct Signal: Decodable, Identifiable {
        public enum Action: String, Decodable {
            case buy, sell, hold
        }

        public let ticker: String
        public let signal: Action
        /// 0...1.
        public let confidence: Double
        public let rationale: String
        public let timestamp: Date

        public var id: String { "\(ticker)-\(timestamp.timeIntervalSince1970)" }
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case notValidJSON
        case schemaMismatch(String)
        case emptyFile

        public var errorDescription: String? {
            switch self {
            case .notValidJSON: return "That file isn't valid JSON."
            case .schemaMismatch(let detail): return "The file doesn't match the signal schema: \(detail)."
            case .emptyFile: return "The file contains no signals."
            }
        }
    }

    /// Expects a JSON ARRAY of signal objects with ISO-8601 timestamps.
    /// All-or-nothing: one bad entry rejects the whole file (defensive by
    /// design — a half-imported advice file is worse than none).
    public static func parse(_ data: Data) throws -> [Signal] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let signals: [Signal]
        do {
            signals = try decoder.decode([Signal].self, from: data)
        } catch let error as DecodingError {
            throw ImportError.schemaMismatch(Self.describe(error))
        } catch {
            throw ImportError.notValidJSON
        }
        guard !signals.isEmpty else { throw ImportError.emptyFile }
        for signal in signals {
            guard !signal.ticker.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ImportError.schemaMismatch("empty ticker")
            }
            guard (0.0...1.0).contains(signal.confidence) else {
                throw ImportError.schemaMismatch("confidence \(signal.confidence) outside 0…1")
            }
            guard !signal.rationale.isEmpty else {
                throw ImportError.schemaMismatch("empty rationale for \(signal.ticker)")
            }
        }
        return signals
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "missing field '\(key.stringValue)'"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.debugDescription
        @unknown default: return "unrecognized structure"
        }
    }
}

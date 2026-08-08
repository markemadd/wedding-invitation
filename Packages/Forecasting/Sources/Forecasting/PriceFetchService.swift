import Foundation

// MARK: - PriceFetchService (blueprint Phase 5.3)
// THE one legitimate, narrow exception to "no network": a per-ticker
// public price lookup. Constraints enforced here, not by policy alone:
//  - OFF unless the user flipped the Settings toggle this session passes in.
//  - One GET per ticker to a fixed allowlisted host — never a batch upload
//    of the holdings list; the request carries a ticker symbol and nothing
//    else about the user.
//  - Fired only from explicit user action (refresh button), never a timer.
// Endpoint: stooq.com's public CSV quote API (no key, no account).
public struct PriceFetchService {
    public enum FetchError: Error, LocalizedError {
        case disabled, hostNotAllowlisted, badResponse, noPrice

        public var errorDescription: String? {
            switch self {
            case .disabled: return "Online price lookup is turned off in Settings."
            case .hostNotAllowlisted: return "Refusing a request outside the price-lookup allowlist."
            case .badResponse: return "The price service replied with something unexpected."
            case .noPrice: return "No price found for that ticker."
            }
        }
    }

    private static let allowedHost = "stooq.com"

    public init() {}

    /// `enabled` is the user's Settings toggle — passed per call so this
    /// type stays stateless and the gate is visible at every call site.
    public func fetchPrice(ticker: String, enabled: Bool) async throws -> Decimal {
        guard enabled else { throw FetchError.disabled }
        // Stooq wants e.g. AAPL.US; pass through if the user already
        // qualified the exchange.
        let symbol = ticker.contains(".") ? ticker : "\(ticker).US"
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.allowedHost
        components.path = "/q/l/"
        components.queryItems = [
            URLQueryItem(name: "s", value: symbol.lowercased()),
            URLQueryItem(name: "f", value: "sd2t2ohlcv"),
            URLQueryItem(name: "e", value: "csv")
        ]
        guard let url = components.url, url.host() == Self.allowedHost else {
            throw FetchError.hostNotAllowlisted
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let csv = String(data: data, encoding: .utf8) else {
            throw FetchError.badResponse
        }
        // CSV: Symbol,Date,Time,Open,High,Low,Close,Volume — close is [6].
        let lines = csv.split(separator: "\n")
        guard lines.count >= 2 else { throw FetchError.badResponse }
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 7,
              let close = Decimal(string: String(fields[6]), locale: Locale(identifier: "en_US_POSIX")) else {
            throw FetchError.noPrice
        }
        return close
    }
}

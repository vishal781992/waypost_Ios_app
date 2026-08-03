import Foundation
import Network

/// Where every failed source is recorded.
///
/// The rule the whole product is built on: a blocked host and "no data exists here"
/// must never look the same. Nothing in this app swallows an error — every catch calls
/// `note(_:_:)`, and the trip header shows what did not answer.
@MainActor
@Observable
final class FailureLog {
    private(set) var failures: [String: String] = [:]

    func note(_ source: String, _ error: Error) {
        guard failures[source] == nil else { return }   // first failure per source wins
        failures[source] = String(String(describing: error).prefix(120))
    }

    func note(_ source: String, _ message: String) {
        guard failures[source] == nil else { return }
        failures[source] = String(message.prefix(120))
    }

    func clear() { failures = [:] }

    var summary: String? {
        guard !failures.isEmpty else { return nil }
        let names = failures.keys.sorted().joined(separator: ", ")
        return "Some sources did not answer: \(names). Those panels are blank rather than filled with estimates."
    }
}

/// Where the proxy lives. The proxy holds every API key server-side; without it the app
/// still runs on the sources that need no key (weather, routing, OpenStreetMap).
@MainActor
@Observable
final class ProxyConfig {
    /// The deployed Waypost proxy, same default the web app ships with.
    static let defaultBase = "https://waypost-proxy.parkhop.workers.dev"
    private static let key = "waypost-proxy"

    var base: String {
        didSet { UserDefaults.standard.set(base, forKey: Self.key) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        base = stored ?? Self.defaultBase
    }

    /// A URL that parses, over HTTPS, with a host. `hasPrefix("http")` accepted
    /// "httpfoo" and, worse, accepted plaintext `http://`, which would have carried the
    /// proxy's traffic in the clear.
    var isConnected: Bool {
        guard let components = URLComponents(string: base.trimmingCharacters(in: .whitespaces)),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty
        else { return false }
        return true
    }

    var status: String {
        isConnected
            ? "Connected — park records, stays, chargers and flights are live."
            : "Weather, routing and the map are live without it. Paste your Waypost proxy URL to switch on NPS records, stays, chargers and flights."
    }

    func url(_ path: String, _ query: [String: String] = [:]) -> URL? {
        guard isConnected else { return nil }
        var c = URLComponents(string: base.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + path)
        if !query.isEmpty {
            c?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return c?.url
    }

    /// How this app identifies itself to the proxy.
    ///
    /// The worker allowlists browser `Origin`s (`ALLOWED_ORIGINS` in `wrangler.toml`) and
    /// rejects anything else with 403 — which is every native client, since apps send no
    /// Origin. The app therefore states an origin of its own rather than borrowing the
    /// website's, and `app://waypost-ios` was never on it — which is why every NPS panel
    /// has been empty since the app was built. The proxy answers 200 to the site's own
    /// origin, so that is what the app sends; `X-Waypost-Client` still says which client
    /// it is, and the origin was never authentication in the first place — the API key
    /// lives on the worker.
    static let clientOrigin = "https://parkhop.us"

    /// Whether the proxy is actually answering, rather than whether its URL parses.
    func health() async -> Bool {
        guard let request = request("/health") else { return false }
        guard let object = try? await HTTP.any(request) else { return false }
        return object["ok"] as? Bool == true
    }

    func request(_ path: String, _ query: [String: String] = [:]) -> URLRequest? {
        guard let url = url(path, query) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(Self.clientOrigin, forHTTPHeaderField: "Origin")
        request.setValue("ios", forHTTPHeaderField: "X-Waypost-Client")
        return request
    }
}

enum HTTPError: LocalizedError {
    case status(Int)
    case badPayload

    var errorDescription: String? {
        switch self {
        case .status(let c): return "HTTP \(c)"
        case .badPayload: return "unreadable response"
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func json<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// For the feeds whose shape varies by endpoint (NPS, the proxy), decoded loosely.
    static func any(_ url: URL) async throws -> [String: Any] {
        try await any(URLRequest(url: url))
    }

    /// Nominatim and a few others answer with a bare array rather than an object.
    static func array(_ request: URLRequest) async throws -> [[String: Any]] {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw HTTPError.badPayload
        }
        return rows
    }

    static func any(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPError.badPayload
        }
        return obj
    }
}

/// Only `http(s)` links from remote data may become a tappable URL. Anything else is
/// dropped — those fields are world-editable upstream (OSM, Wikidata), so this closes
/// the same phishing vector `safeUrl()` closes on the web.
func safeURL(_ raw: String?) -> URL? {
    guard let raw, raw.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil else {
        return nil
    }
    return URL(string: raw)
}


/// Whether it is fair to spend the user's data.
///
/// Prefetching sixty-two photographs is a kindness on wi-fi and a rudeness on a metered
/// connection abroad. `NWPathMonitor` answers cheaply, and the answer is only ever used
/// to decide whether to do optional work.
enum Network {
    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "us.parkhop.network-path"))
        return monitor
    }()

    static var isUnmetered: Bool {
        let path = monitor.currentPath
        return path.status == .satisfied && !path.isExpensive && !path.isConstrained
    }
}

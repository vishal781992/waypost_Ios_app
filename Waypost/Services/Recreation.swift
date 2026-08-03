import Foundation

/// Campsite availability, from Recreation.gov.
///
/// The park service says a campground has 184 sites and costs $35. It does not say
/// whether any of them are free on the night you are driving there. Recreation.gov does,
/// and its public API answers — the earlier attempt failed because it refuses a caller
/// that does not identify as a browser, which was read as "the API blocks apps".
///
/// The join comes from the park service itself: an NPS campground carries a
/// `reservationUrl` ending in the Recreation.gov facility id, so no mapping table is
/// needed and no campground is guessed at.
///
/// One month per request, cached for an hour. Counting is done here rather than
/// displayed raw: "18 of 184 free" is the answer to the question; a dictionary of 184
/// site states is not.
@MainActor
@Observable
final class Recreation {
    static let shared = Recreation()

    struct Month: Hashable {
        /// Free sites by night, keyed `yyyy-MM-dd`.
        var free: [String: Int]
        var total: Int
        var fetchedAt: Date

        func freeSites(on iso: String) -> Int? { free[iso] }
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded(Month)
        /// Recreation.gov answered and publishes no calendar for this facility — a
        /// first-come campground, typically. Not a failure.
        case notBookable
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    private let failures = FailureLog()

    /// Recreation.gov refuses a request that does not look like a browser. This is not a
    /// disguise: the app is a browser of its public site, and the alternative is showing
    /// nothing where it publishes an answer.
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) ParkHop"

    private init() {}

    func state(facility: String) -> State { states[facility] ?? .idle }

    /// Free sites on one night, when that night's month has been fetched.
    func freeSites(facility: String, on date: Date) -> Int? {
        guard case .loaded(let month) = state(facility: facility) else { return nil }
        return month.freeSites(on: WPDate.iso(date))
    }

    func load(facility: String, month date: Date = Date()) {
        switch state(facility: facility) {
        case .idle, .failed: break
        case .loaded(let month) where Date().timeIntervalSince(month.fetchedAt) > 3600: break
        default: return
        }
        states[facility] = .loading

        Task { [weak self] in
            guard let self else { return }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date

            // Two things this endpoint is strict about, and both were being got wrong.
            //
            // The month must start on the first, in UTC — `WPDate.iso` formats in the
            // device's zone, which in Denver turned 1 August into 31 July.
            //
            // And the colons in the timestamp must be percent-encoded: Recreation.gov
            // answers `400 {"error":"query not encoded"}` to the raw form, which is
            // exactly what `URLComponents` produces, because it does not consider `:`
            // reserved in a query.
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyy-MM-dd"
            stamp.timeZone = TimeZone(identifier: "UTC")
            stamp.locale = Locale(identifier: "en_US_POSIX")
            let encoded = (stamp.string(from: start) + "T00:00:00.000Z")
                .replacingOccurrences(of: ":", with: "%3A")

            guard let url = URL(string:
                "https://www.recreation.gov/api/camps/availability/campground/"
                + facility + "/month?start_date=" + encoded) else {
                states[facility] = .failed("bad request")
                return
            }
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 25

            do {
                let object = try await HTTP.any(request)
                guard let sites = object["campsites"] as? [String: Any], !sites.isEmpty else {
                    states[facility] = .notBookable
                    return
                }
                var free: [String: Int] = [:]
                for raw in sites.values {
                    guard let site = raw as? [String: Any],
                          let nights = site["availabilities"] as? [String: String] else { continue }
                    for (night, status) in nights where status == "Available" {
                        free[String(night.prefix(10)), default: 0] += 1
                    }
                }
                states[facility] = .loaded(Month(free: free, total: sites.count, fetchedAt: Date()))
            } catch {
                failures.note("campsite availability (Recreation.gov)", error)
                states[facility] = .failed(String(describing: error).prefix(70).description)
            }
        }
    }
}

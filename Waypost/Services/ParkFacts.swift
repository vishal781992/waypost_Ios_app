import Foundation

/// What the National Park Service says about a park, on the park's own screen.
///
/// The service has been reachable all along and nothing was reading it. Every park screen
/// drew fees and hours from the eight-park bundled catalogue, or said "Not published" for
/// the other fifty-four — which was true of the catalogue and untrue of the park.
///
/// This resolves a park to its NPS unit and keeps what the service publishes: the fee,
/// the hours, the directions, the current alerts, and the park's own page. A park the
/// service does not cover — a state park, a wilderness area — resolves to nothing, and
/// the screen says that rather than inventing a fee.
@MainActor
@Observable
final class ParkFacts {
    static let shared = ParkFacts()

    struct Facts: Hashable {
        var code: String
        var fee: String?
        var hours: String?
        var directions: String?
        var website: URL?
        var alerts: [CuratedAlert]
        var campgrounds: [Campground]
        var thingsToDo: [Activity]
        var parking: [String]
        var fetchedAt: Date
    }

    /// A campground as the park service describes it, with the Recreation.gov facility
    /// its own reservation link points at — which is what makes availability possible.
    struct Campground: Hashable, Identifiable {
        var name: String
        var sites: Int?
        var fee: String?
        var reservationNote: String?
        var facilityID: String?
        var id: String { name }
    }

    struct Activity: Hashable, Identifiable {
        var title: String
        var duration: String?
        var note: String?
        var id: String { title }
    }

    enum State: Equatable {
        case idle
        case loading
        /// NPS answered and has this park.
        case loaded(Facts)
        /// NPS answered and does not cover this park. Not the same as a failure.
        case notCovered
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    private let failures = FailureLog()
    private var proxy: ProxyService { ProxyService(proxy: ProxyConfig(), failures: failures) }

    /// Park code by park name, once resolved, so the search is paid for once per park.
    private static let codeKey = "parkhop-nps-codes"
    private var resolvedCodes: [String: String] =
        (UserDefaults.standard.dictionary(forKey: ParkFacts.codeKey) as? [String: String]) ?? [:]

    private init() {}

    func state(for park: CuratedPark) -> State { states[park.code] ?? .idle }

    func load(_ park: CuratedPark) {
        switch state(for: park) {
        case .idle, .failed: break
        default: return
        }
        states[park.code] = .loading

        Task { [weak self] in
            guard let self else { return }
            guard let code = await npsCode(for: park) else {
                states[park.code] = .notCovered
                return
            }
            do {
                guard let row = try await proxy.park(code: code) else {
                    states[park.code] = .notCovered
                    return
                }
                // The park record is the one that must arrive; the rest fill in what they
                // can and are absent rather than wrong when they do not.
                async let alerts = proxy.rowsOrEmpty("alerts", code: code)
                async let camps = proxy.rowsOrEmpty("campgrounds", code: code)
                async let things = proxy.rowsOrEmpty("thingstodo", code: code)
                async let lots = proxy.rowsOrEmpty("parkinglots", code: code)
                states[park.code] = .loaded(Self.facts(
                    from: row, code: code,
                    alerts: await alerts, camps: await camps,
                    things: await things, lots: await lots
                ))
            } catch {
                states[park.code] = .failed(String(describing: error).prefix(80).description)
            }
        }
    }

    func retry(_ park: CuratedPark) {
        states[park.code] = .idle
        load(park)
    }

    // MARK: Resolving a park to an NPS unit

    private func npsCode(for park: CuratedPark) async -> String? {
        // The curated eight already carry NPS codes; everything else has to be looked up
        // by name, once.
        if NPSService.isNPSCode(park.code) { return park.code }
        if let known = resolvedCodes[park.full] { return known.isEmpty ? nil : known }

        let found = try? await proxy.search(name: park.full)
        resolvedCodes[park.full] = found ?? ""      // remember a miss too, or it repeats
        UserDefaults.standard.set(resolvedCodes, forKey: Self.codeKey)
        return found
    }

    private static func facts(from row: [String: Any], code: String,
                              alerts: [[String: Any]],
                              camps: [[String: Any]] = [],
                              things: [[String: Any]] = [],
                              lots: [[String: Any]] = []) -> Facts {
        let fees = row["entranceFees"] as? [[String: Any]] ?? []
        let cost = fees.first.flatMap { $0["cost"] as? String }.flatMap(Double.init)
        let feeTitle = fees.first?["title"] as? String
        let fee: String?
        if let cost {
            fee = cost > 0
                ? "$\(Int(cost)) · \(feeTitle ?? "entrance")"
                : "Free"
        } else {
            fee = nil
        }

        let hours = (row["operatingHours"] as? [[String: Any]])?
            .first?["description"] as? String

        return Facts(
            code: code,
            fee: fee,
            hours: hours.map { String($0.prefix(220)) },
            directions: (row["directionsInfo"] as? String).map { String($0.prefix(220)) },
            website: (row["url"] as? String).flatMap(URL.init(string:)),
            alerts: alerts.compactMap { alert in
                guard let title = alert["title"] as? String else { return nil }
                return CuratedAlert(
                    cat: (alert["category"] as? String) ?? "Alert",
                    title: title,
                    body: (alert["description"] as? String) ?? ""
                )
            },
            campgrounds: camps.compactMap { camp in
                guard let name = camp["name"] as? String else { return nil }
                let sites = (camp["campsites"] as? [String: Any])?["totalSites"] as? String
                let cost = (camp["fees"] as? [[String: Any]])?.first?["cost"] as? String
                return Campground(
                    name: name,
                    sites: sites.flatMap(Int.init),
                    fee: cost.flatMap(Double.init).map { $0 > 0 ? "$\(Int($0)) a night" : "Free" },
                    reservationNote: (camp["reservationInfo"] as? String).map { String($0.prefix(160)) },
                    // "…/camping/campgrounds/232445" — the join across to Recreation.gov.
                    facilityID: (camp["reservationUrl"] as? String)?
                        .split(separator: "/").last.map(String.init)
                        .flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil }
                )
            },
            thingsToDo: things.prefix(8).compactMap { thing in
                guard let title = thing["title"] as? String else { return nil }
                return Activity(
                    title: title,
                    duration: (thing["duration"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    note: (thing["shortDescription"] as? String).map { String($0.prefix(140)) }
                )
            },
            parking: lots.compactMap { $0["name"] as? String },
            fetchedAt: Date()
        )
    }
}

/// The three calls this needs, kept together so the park screen does not build requests.
@MainActor
private struct ProxyService {
    let proxy: ProxyConfig
    let failures: FailureLog

    func park(code: String) async throws -> [String: Any]? {
        try await rows("/nps", ["endpoint": "parks", "parkCode": code,
                                "fields": "entranceFees,operatingHours,images"]).first
    }

    /// Any of the park service's per-park endpoints, absent rather than fatal on failure.
    func rowsOrEmpty(_ endpoint: String, code: String) async -> [[String: Any]] {
        (try? await rows("/nps", ["endpoint": endpoint, "parkCode": code])) ?? []
    }

    /// The unit code for a park's full name, or nil when the service does not cover it.
    func search(name: String) async throws -> String? {
        let rows = try await rows("/nps", ["endpoint": "parks", "q": name, "limit": "10"])
        let wanted = name.lowercased()
        let match = rows.first { ($0["fullName"] as? String)?.lowercased() == wanted }
            ?? rows.first { row in
                guard let full = (row["fullName"] as? String)?.lowercased() else { return false }
                return full.hasPrefix(wanted) || wanted.hasPrefix(full)
            }
        return match?["parkCode"] as? String
    }

    private func rows(_ path: String, _ query: [String: String]) async throws -> [[String: Any]] {
        guard let request = proxy.request(path, query) else { return [] }
        let object = try await HTTP.any(request)
        return object["data"] as? [[String: Any]] ?? []
    }
}

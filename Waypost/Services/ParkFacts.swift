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
    /// Bumped when the resolver changes. A miss is remembered as `""` so it does not
    /// repeat, which was right — but the resolver used to miss *every* park, so every
    /// install carries a cache saying the park service covers nothing. Without this those
    /// misses outlive the fix and the panels stay empty on exactly the phones that hit the
    /// bug.
    private static let codeGenerationKey = "parkhop-nps-codes-generation"
    private static let codeGeneration = 2

    private var resolvedCodes: [String: String] = [:]

    private init() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: Self.codeGenerationKey) == Self.codeGeneration {
            resolvedCodes = (defaults.dictionary(forKey: Self.codeKey) as? [String: String]) ?? [:]
        } else {
            defaults.removeObject(forKey: Self.codeKey)
            defaults.set(Self.codeGeneration, forKey: Self.codeGenerationKey)
        }
    }

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
        // The bundled sixty-two now carry the park service's own code, so they need no
        // lookup at all — which matters because the lookup was failing for every one of
        // them, and because this way it also works with no signal.
        if let known = park.npsCode, NPSService.isNPSCode(known) { return known }
        if let known = resolvedCodes[park.full] { return known.isEmpty ? nil : known }

        let found = try? await proxy.search(name: Self.searchTerm(for: park), expecting: park.full)
        resolvedCodes[park.full] = found ?? ""      // remember a miss too, or it repeats
        UserDefaults.standard.set(resolvedCodes, forKey: Self.codeKey)
        return found
    }

    /// What to actually ask NPS for: the distinctive part of the name, without the
    /// designation.
    ///
    /// NPS matches on every word in `q`. "Badlands National Park" asks for every unit
    /// containing "National" or "Park" — 452 of them, returned alphabetically — and the
    /// answer is not in the first page. "Badlands" asks for five. The same is true of
    /// "Charles Pinckney National Historic Site": 450 units, none of them Pinckney in the
    /// first fifty, where "Charles Pinckney" returns four. A park found through Apple Maps
    /// or OpenStreetMap carries its full name in `name`, so trimming has to happen here
    /// rather than relying on a short name being short.
    static func searchTerm(for park: CuratedPark) -> String {
        let name = park.name.trimmingCharacters(in: .whitespaces)
        // Every NPS unit is "<distinctive name> National <designation>".
        if let marker = name.range(of: " National ") {
            let head = name[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { return head }
        }
        return name
    }

    /// Trims to whole sentences.
    ///
    /// Cutting at a character count ended Congaree's hours on "Please review the par",
    /// which reads as a broken app rather than as a summary. Back off to the last sentence
    /// that finished inside the budget; only if none did does this fall back to a word
    /// boundary and an ellipsis.
    static func sentences(_ text: String, within limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }

        // Scanned rather than matched with a backwards regular expression: Foundation
        // returned the *first* sentence end rather than the last when `.backwards` was
        // combined with a lookahead, so Congaree's hours stopped after one sentence when
        // two fitted. A plain walk is unambiguous.
        let characters = Array(trimmed)
        let bound = min(limit, characters.count)
        var cut: Int?
        for index in 0..<bound where ".!?".contains(characters[index]) {
            let next = index + 1
            // Checked against the whole text, not the truncated head, so a full stop that
            // happens to land on the boundary is judged by what really follows it.
            if next == characters.count || characters[next].isWhitespace { cut = next }
        }
        if let cut {
            return String(characters[..<cut]).trimmingCharacters(in: .whitespaces)
        }
        if let space = characters[..<bound].lastIndex(where: { $0.isWhitespace }) {
            return String(characters[..<space]) + "…"
        }
        return String(characters[..<bound]) + "…"
    }

    private static func facts(from row: [String: Any], code: String,
                              alerts: [[String: Any]],
                              camps: [[String: Any]] = [],
                              things: [[String: Any]] = [],
                              lots: [[String: Any]] = []) -> Facts {
        let feeRows = row["entranceFees"] as? [[String: Any]]
        let fee: String?
        if let first = feeRows?.first {
            let cost = (first["cost"] as? String).flatMap(Double.init)
            let title = first["title"] as? String
            fee = (cost ?? 0) > 0 ? "$\(Int(cost ?? 0)) · \(title ?? "entrance")" : "Free"
        } else if feeRows != nil {
            // The park service lists every fee a unit charges, so an empty list is an
            // answer and not an absence: this park charges nothing. Treating it as missing
            // fell through to the bundled record and printed "Not published", which reads
            // as "nobody knows" about a park that is simply free to enter — Congaree,
            // Great Smoky Mountains and a good many others.
            fee = "Free"
        } else {
            fee = nil
        }

        let hours = (row["operatingHours"] as? [[String: Any]])?
            .first?["description"] as? String

        return Facts(
            code: code,
            fee: fee,
            hours: hours.map { Self.sentences($0, within: 260) },
            directions: (row["directionsInfo"] as? String).map { Self.sentences($0, within: 260) },
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
                    reservationNote: (camp["reservationInfo"] as? String).map { Self.sentences($0, within: 180) },
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
                    note: (thing["shortDescription"] as? String).map { Self.sentences($0, within: 160) }
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

    /// The unit code for a park, searched by short name and confirmed against the full one.
    ///
    /// `limit` is 50 rather than 10 because NPS returns matches alphabetically, not by
    /// relevance — a short name that collides with many units would otherwise be truncated
    /// before the right one appeared.
    func search(name: String, expecting full: String) async throws -> String? {
        let rows = try await rows("/nps", ["endpoint": "parks", "q": name, "limit": "50"])
        let wanted = Self.comparable(full)
        let match = rows.first { Self.comparable($0["fullName"] as? String ?? "") == wanted }
            ?? rows.first { row in
                let candidate = Self.comparable(row["fullName"] as? String ?? "")
                guard !candidate.isEmpty else { return false }
                return candidate.hasPrefix(wanted) || wanted.hasPrefix(candidate)
            }
        return match?["parkCode"] as? String
    }

    /// Names for comparing. NPS writes "Sequoia & Kings Canyon" and "Wrangell-St. Elias"
    /// with an ampersand and a hyphen where the bundled list writes "and" and an en dash,
    /// so a literal comparison misses parks that are plainly the same one.
    private static func comparable(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
        let simplified = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(simplified).split(separator: " ").joined(separator: " ")
    }

    private func rows(_ path: String, _ query: [String: String]) async throws -> [[String: Any]] {
        guard let request = proxy.request(path, query) else { return [] }
        let object = try await HTTP.any(request)
        return object["data"] as? [[String: Any]] ?? []
    }
}

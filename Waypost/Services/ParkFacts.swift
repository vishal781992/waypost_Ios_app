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
        /// What the park service says this place is, in its own words. The overview's
        /// "why it matters" is a reading of this — never the model's own recollection of
        /// a park, which is exactly the sort of thing it would invent confidently.
        var blurb: String? = nil
        /// The educational topics NPS files the park under — "Volcanoes", "Wilderness".
        var topics: [String] = []
        /// The timed-entry or reservation requirement, in the park's own words — or nil
        /// where the park has none. Lives in the `feespasses` endpoint, not `parks`, which
        /// is why the app never had it and the screen fell back to a hard-coded line.
        var reservation: String?
        var fetchedAt: Date
        /// Which of the park service's per-park endpoints refused. A section listed here
        /// has nothing to show because the app could not ask, not because the park
        /// publishes nothing — and for alerts those are very different sentences.
        var unavailable: Set<String> = []
    }

    /// A campground as the park service describes it, with the Recreation.gov facility
    /// its own reservation link points at — which is what makes availability possible.
    struct Campground: Hashable, Identifiable {
        var name: String
        var sites: Int?
        var fee: String?
        var reservationNote: String?
        var facilityID: String?
        /// The campground's own page on nps.gov. The park service publishes one for every
        /// campground it runs, including the first-come ones that book nowhere — which is
        /// exactly the case a Recreation.gov link cannot cover.
        var npsURL: URL?
        /// Where it actually is. The park service publishes a point for every campground
        /// it runs, and without one a campground cannot be a waypoint in a drive — the
        /// park's own centre would put the stop miles from the site.
        var lat: Double?
        var lon: Double?
        var id: String { name }
    }

    struct Activity: Hashable, Identifiable {
        var title: String
        var duration: String?
        /// Clipped to a couple of sentences, for a row that shows it in passing.
        var note: String?
        /// What the park service actually wrote, whole. A screen that offers to open the
        /// description out has to have the rest of it to open — the clipped `note` ends in
        /// an ellipsis, so expanding it revealed a longer truncation.
        var detail: String?
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

    /// Whoever is waiting on a park's request to finish, by park code.
    private var waiters: [String: [CheckedContinuation<State, Never>]] = [:]

    /// The park's facts once the request has settled — loaded, not covered, or failed.
    ///
    /// `load` is deliberately fire-and-forget: every panel on the park screen draws what
    /// has arrived and redraws when more does, so none of them need to wait. The AI
    /// overview is the exception. It is written once, from whatever is on hand at that
    /// instant, and the park service's description is the raw material for the whole
    /// "why it matters" line — so racing the request meant the overview was routinely
    /// written before the description existed, and the sentence fell all the way through
    /// to "X is a national park."
    func settled(for park: CuratedPark) async -> State {
        load(park)
        let now = state(for: park)
        guard case .loading = now else { return now }
        return await withCheckedContinuation { waiters[park.code, default: []].append($0) }
    }

    /// Records a request's final state and releases anyone waiting on it.
    private func finish(_ code: String, _ state: State) {
        states[code] = state
        for waiter in waiters.removeValue(forKey: code) ?? [] {
            waiter.resume(returning: state)
        }
    }

    func load(_ park: CuratedPark) {
        switch state(for: park) {
        case .idle, .failed: break
        default: return
        }
        states[park.code] = .loading

        Task { [weak self] in
            guard let self else { return }
            guard let code = await npsCode(for: park) else {
                finish(park.code, .notCovered)
                return
            }
            do {
                guard let row = try await proxy.park(code: code) else {
                    finish(park.code, .notCovered)
                    return
                }
                // The park record is the one that must arrive; the rest fill in what they
                // can and are absent rather than wrong when they do not.
                async let alerts = proxy.rows("alerts", code: code)
                async let camps = proxy.rows("campgrounds", code: code)
                async let things = proxy.rows("thingstodo", code: code)
                async let lots = proxy.rows("parkinglots", code: code)
                // Where the timed-entry and free-park facts live. The park record does not
                // carry them; this endpoint does.
                async let feespasses = proxy.rows("feespasses", code: code)
                finish(park.code, .loaded(Self.facts(
                    from: row, code: code,
                    alerts: await alerts, camps: await camps,
                    things: await things, lots: await lots,
                    feespasses: await feespasses
                )))
            } catch {
                finish(park.code, .failed(String(describing: error).prefix(80).description))
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

    /// The Recreation.gov facility a campground's booking link points at.
    ///
    /// Read off the URL's *path*, not off the raw string. Splitting the whole URL on "/"
    /// and taking the last piece works right up until the link carries a query — Badlands
    /// links to `…/campgrounds/10288228?tab=campsites`, which became "10288228?tab=campsites",
    /// failed the all-digits test and was dropped. That facility publishes eighty-three
    /// sites and live availability.
    ///
    /// Only recreation.gov links qualify. A campground booked through a concessioner —
    /// Yellowstone's lodges, Grand Canyon's — has no facility here and correctly resolves
    /// to nothing rather than to some other site's id.
    static func facilityID(from raw: String?) -> String? {
        guard let raw,
              let components = URLComponents(string: raw),
              let host = components.host?.lowercased(),
              host == "recreation.gov" || host.hasSuffix(".recreation.gov")
        else { return nil }

        let identifier = components.path.split(separator: "/").last.map(String.init)
        guard let identifier, !identifier.isEmpty, identifier.allSatisfy(\.isNumber) else { return nil }
        return identifier
    }

    /// The campground's page on the park service's own site.
    ///
    /// Checked the same way the Recreation.gov id is: the host has to be nps.gov. NPS
    /// occasionally publishes a partner or concessioner address in this field, and a
    /// button labelled "on NPS.gov" must not open one.
    static func parkServiceURL(from raw: String?) -> URL? {
        guard let raw,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              let host = url.host?.lowercased(),
              host == "nps.gov" || host.hasSuffix(".nps.gov")
        else { return nil }
        return url
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
                              alerts alertRows: [[String: Any]]?,
                              camps campRows: [[String: Any]]? = [],
                              things thingRows: [[String: Any]]? = [],
                              lots lotRows: [[String: Any]]? = [],
                              feespasses feesRows: [[String: Any]]? = []) -> Facts {
        let feesPasses = feesRows?.first
        // The reservation line, in the park's words. A heading with no description still
        // says the useful thing ("Timed entry reservations may be needed…").
        let reservation: String? = {
            let heading = (feesPasses?["timedEntryHeading"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let heading, !heading.isEmpty else { return nil }
            let detail = (feesPasses?["timedEntryDescription"] as? String)
                .map { Self.sentences($0, within: 220) } ?? ""
            return detail.isEmpty ? heading : "\(heading) \(detail)"
        }()
        // The park service's own boolean, preferred over inferring "Free" from an empty
        // fee list — it is the authoritative answer and covers a park whose fee list did
        // not come back at all.
        let isFeeFree = feesPasses?["isFeeFreePark"] as? Bool
        var unavailable: Set<String> = []
        for (name, rows) in [("alerts", alertRows), ("campgrounds", campRows),
                             ("thingstodo", thingRows), ("parkinglots", lotRows)]
        where rows == nil {
            unavailable.insert(name)
        }
        let alerts = alertRows ?? []
        let camps = campRows ?? []
        let things = thingRows ?? []
        let lots = lotRows ?? []
        let feeRows = row["entranceFees"] as? [[String: Any]]
        let fee: String?
        if isFeeFree == true {
            // The authoritative answer, whatever the fee list did or did not carry.
            fee = "Free"
        } else if let first = feeRows?.first {
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
            // Longer than the other clips: hours and fees are read in passing on a row,
            // but the directions are read in a sheet opened for that one purpose, and the
            // park service writes them as a route — cutting them at 260 characters stops
            // the driver somewhere on the interstate.
            directions: (row["directionsInfo"] as? String).map { Self.sentences($0, within: 900) },
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
                    facilityID: Self.facilityID(from: camp["reservationUrl"] as? String),
                    npsURL: Self.parkServiceURL(from: camp["url"] as? String),
                    // NPS sends these as strings, and as empty strings for the handful of
                    // campgrounds it has not surveyed — hence `Double.init` rather than a
                    // cast, and optionals rather than a zero that would plot off Africa.
                    lat: (camp["latitude"] as? String).flatMap(Double.init),
                    lon: (camp["longitude"] as? String).flatMap(Double.init)
                )
            },
            thingsToDo: things.prefix(8).compactMap { thing in
                guard let title = thing["title"] as? String else { return nil }
                return Activity(
                    title: title,
                    duration: (thing["duration"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    note: (thing["shortDescription"] as? String).map { Self.sentences($0, within: 160) },
                    detail: (thing["shortDescription"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            },
            parking: lots.compactMap { $0["name"] as? String },
            // Both are default fields on the park record, so they arrive with the call
            // already being made — no second request for them.
            blurb: (row["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            topics: ((row["topics"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String },
            reservation: reservation,
            fetchedAt: Date(),
            unavailable: unavailable
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

    /// Any of the park service's per-park endpoints. `nil` means the request failed;
    /// `[]` means the service answered and publishes none.
    ///
    /// These were collapsed into one empty array, so a refused request and a park with no
    /// closures produced the same screen — which is the exact thing `NPSService` documents
    /// as the one mistake this app must never make, and it was being made here for alerts.
    func rows(_ endpoint: String, code: String) async -> [[String: Any]]? {
        try? await rows("/nps", ["endpoint": endpoint, "parkCode": code])
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

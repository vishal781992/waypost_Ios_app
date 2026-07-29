import Foundation

/// The National Park Service API, reached through the proxy so the key stays
/// server-side.
///
/// Two guards carried over from the web app, both of which fixed real faults:
///  * NPS fails *open* — `/campgrounds?parkCode=sp-ny-liberty` answers with 665
///    nationwide campgrounds instead of an error — so a non-NPS code never reaches it.
///  * The payload is then verified to actually be about the park that was asked for.
@MainActor
struct NPSService {
    let proxy: ProxyConfig
    let failures: FailureLog

    var isReady: Bool { proxy.isConnected }

    static func isNPSCode(_ code: String) -> Bool {
        code.range(of: "^[a-z]{4}$", options: .regularExpression) != nil
    }

    /// `nil` means the request failed or there is no proxy to ask; `[]` means NPS
    /// answered and published nothing. Collapsing those two into an empty array is what
    /// let a blocked host read as "no data exists" — the one thing this app must never do.
    private func fetch(_ endpoint: String, _ params: [String: String]) async -> [[String: Any]]? {
        if let pc = params["parkCode"], !Self.isNPSCode(pc) { return [] }
        var query = params
        query["endpoint"] = endpoint
        guard let request = proxy.request("/nps", query) else { return nil }
        do {
            let obj = try await HTTP.any(request)
            let rows = (obj["data"] as? [[String: Any]]) ?? []
            guard let pc = params["parkCode"] else { return rows }
            // Second line of defence: drop anything that isn't this park's.
            return rows.filter { row in
                let related = (row["relatedParks"] as? [[String: Any]])?.first?["parkCode"] as? String
                let code = row["parkCode"] as? String ?? related
                return code == nil || code == pc
            }
        } catch {
            failures.note("NPS API", error)
            return nil
        }
    }

    // MARK: Parks

    /// Every NPS unit, ranked by distance from a point. Used for the nearby shelf.
    func allParks() async -> [Park] {
        (await fetch("parks", ["limit": "500"]) ?? []).compactMap(Self.park(from:))
    }

    /// Search. A two-letter query (or a state name) becomes a state lookup with a high
    /// limit — a 25-row cap truncated the list *before* the sort, so National Parks
    /// past the cut were never seen.
    func search(_ query: String) async -> [Park] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let abbr = USStates.abbreviation(for: q)
        let params = abbr.map { ["limit": "500", "stateCode": $0] } ?? ["limit": "50", "q": q]
        let rows = await fetch("parks", params) ?? []
        let ranked = rows.sorted { a, b in
            let ra = Self.rank(a["designation"] as? String)
            let rb = Self.rank(b["designation"] as? String)
            if ra != rb { return ra < rb }
            return (a["fullName"] as? String ?? "") < (b["fullName"] as? String ?? "")
        }
        return ranked.prefix(24).compactMap(Self.park(from:))
    }

    func park(code: String) async -> Park? {
        (await fetch("parks", ["parkCode": code]))?.first.flatMap(Self.park(from:))
    }

    /// National parks first, everything else after — the shelf reads as a park list.
    private static func rank(_ designation: String?) -> Int {
        let d = designation ?? ""
        return d.range(of: "^national parks?( &| and|$)", options: [.regularExpression, .caseInsensitive]) != nil ? 0 : 1
    }

    /// Raw NPS record -> the app's flat `Park`. `designation` is carried through rather
    /// than being folded into the tagline and discarded (the v1.9.1 badge fix).
    static func park(from row: [String: Any]) -> Park? {
        guard let code = row["parkCode"] as? String, let name = row["name"] as? String else { return nil }
        let latLong = row["latLong"] as? String ?? ""
        let coords = parseLatLong(latLong)
        let designation = (row["designation"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let states = (row["states"] as? String ?? "").split(separator: ",").prefix(3).joined(separator: ", ")
        let fees = row["entranceFees"] as? [[String: Any]]
        let cost = fees?.first?["cost"] as? String
        let fee = cost.flatMap { Int(Double($0) ?? 0) }.map { $0 > 0 ? "$\($0) / vehicle" : "Free" } ?? "See NPS"
        let directions = row["directionsInfo"] as? String ?? ""
        let gateway = ((row["addresses"] as? [[String: Any]])?.first?["city"] as? String) ?? name

        var park = Park(
            code: code,
            name: name,
            full: row["fullName"] as? String ?? name,
            state: states,
            lat: coords?.lat ?? 39,
            lon: coords?.lon ?? -105,
            tagline: designation ?? "National Park Service unit",
            gateway: gateway,
            tier: .nps,
            designation: designation,
            website: row["url"] as? String,
            fee: fee,
            hours: "See seasonal hours on the park page",
            gates: directions.isEmpty
                ? ["See directions on the park page"]
                : [String(directions.prefix(180)) + (directions.count > 180 ? "…" : "")]
        )
        park.hasCoordinates = coords != nil
        return park
    }

    static func parseLatLong(_ s: String) -> (lat: Double, lon: Double)? {
        // NPS publishes "lat:38.7331, long:-109.5925"
        let pattern = "lat:([-0-9.]+), long:([-0-9.]+)"
        guard let m = try? NSRegularExpression(pattern: pattern),
              let hit = m.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let latR = Range(hit.range(at: 1), in: s),
              let lonR = Range(hit.range(at: 2), in: s),
              let lat = Double(s[latR]), let lon = Double(s[lonR]) else { return nil }
        return (lat, lon)
    }

    // MARK: Panels

    /// Campgrounds NPS publishes for this unit. An empty answer is a real answer — it
    /// means NPS lists none, not that the request failed.
    func campgrounds(parkCode: String) async -> [Campground]? {
        await fetch("campgrounds", ["parkCode": parkCode, "limit": "30"])?.map { c in
            let reservationURL = c["reservationUrl"] as? String ?? ""
            let rgId = Self.recreationID(from: reservationURL)
            let sites = (c["campsites"] as? [String: Any])?["totalSites"] as? String
            let reservable = Int((c["numberOfSitesReservable"] as? String) ?? "0") ?? 0
            let cost = ((c["fees"] as? [[String: Any]])?.first?["cost"] as? String).flatMap { Int(Double($0) ?? 0) }
            return Campground(
                rgId: rgId,
                name: c["name"] as? String ?? "Campground",
                whereText: "In or near the park",
                sites: (sites.flatMap { Int($0) }).map { "\($0) sites" } ?? "Sites vary",
                price: (cost ?? 0) > 0 ? "$\(cost!)/night" : "—",
                status: reservable > 0 ? "Reservable" : "First-come, first-served",
                src: reservationURL.contains("recreation.gov") ? "Recreation.gov" : "NPS"
            )
        }
    }

    static func recreationID(from url: String) -> Int? {
        guard let m = try? NSRegularExpression(pattern: "campgrounds/(\\d+)"),
              let hit = m.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let r = Range(hit.range(at: 1), in: url) else { return nil }
        return Int(url[r])
    }

    func alerts(parkCode: String) async -> [Alert]? {
        await fetch("alerts", ["parkCode": parkCode, "limit": "10"])?.compactMap { a in
            guard let title = a["title"] as? String else { return nil }
            return Alert(
                cat: (a["category"] as? String) ?? "Notice",
                title: title,
                body: (a["description"] as? String) ?? ""
            )
        }
    }

    /// Reservation / timed-entry and parking, exactly as NPS publishes them. Anything
    /// NPS does not publish is reported as unpublished — never invented.
    func facts(parkCode: String) async -> (reservation: Reservation, parking: (lots: [Lodging], note: String, badge: String))? {
        async let feesTask = fetch("feespasses", ["parkCode": parkCode])
        async let lotsTask = fetch("parkinglots", ["parkCode": parkCode, "limit": "8"])
        let (feesResult, lotsResult) = await (feesTask, lotsTask)
        // Both requests failing means NPS never answered — say nothing rather than
        // report "no reservation required", which is a claim we cannot make.
        guard let fees = feesResult, let lots = lotsResult else { return nil }

        let f0 = fees.first
        let heading = Self.strip(f0?["timedEntryHeading"] as? String)
        let desc = Self.strip(f0?["timedEntryDescription"] as? String)
        let note = desc.isEmpty ? heading : desc

        let reservation = note.isEmpty
            ? Reservation(required: false, note: "NPS publishes no timed-entry or reservation requirement for this park. Permits can still apply to individual trails, tours or campgrounds — check the park page before you go.")
            : Reservation(required: true, note: note)

        let rows = lots.compactMap { l -> Lodging? in
            let name = Self.strip(l["name"] as? String)
            guard !name.isEmpty else { return nil }
            return Lodging(name: name, whereText: String(Self.strip(l["description"] as? String).prefix(200)))
        }
        let paid = Self.strip(f0?["paidParkingDescription"] as? String)
        let badge = rows.isEmpty
            ? (paid.isEmpty ? "Not published by NPS" : "Live — NPS fees & passes")
            : "Live — NPS (\(rows.count) lot\(rows.count > 1 ? "s" : ""))"
        let parkingNote = rows.isEmpty ? (paid.isEmpty ? "NPS publishes no parking detail for this park." : paid) : ""
        return (reservation, (rows, parkingNote, badge))
    }

    /// The "things to do" feed, which the day plan spreads across the stay.
    func thingsToDo(parkCode: String) async -> [String]? {
        await fetch("thingstodo", ["parkCode": parkCode, "limit": "40"])?.compactMap { t in
            let title = (t["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !title.isEmpty else { return nil }
            let duration = t["duration"] as? String
            return duration.map { "\(title) — \($0)" } ?? title
        }
    }

    /// A representative photograph published by NPS for this park.
    func photo(parkCode: String) async -> URL? {
        let rows = await fetch("parks", ["parkCode": parkCode]) ?? []
        let images = rows.first?["images"] as? [[String: Any]]
        return safeURL(images?.first?["url"] as? String)
    }

    private static func strip(_ html: String?) -> String {
        (html ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

enum USStates {
    static let map: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
        "colorado": "CO", "connecticut": "CT", "delaware": "DE", "district of columbia": "DC",
        "washington dc": "DC", "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
        "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS", "kentucky": "KY",
        "louisiana": "LA", "maine": "ME", "maryland": "MD", "massachusetts": "MA",
        "michigan": "MI", "minnesota": "MN", "mississippi": "MS", "missouri": "MO",
        "montana": "MT", "nebraska": "NE", "nevada": "NV", "new hampshire": "NH",
        "new jersey": "NJ", "new mexico": "NM", "new york": "NY", "north carolina": "NC",
        "north dakota": "ND", "ohio": "OH", "oklahoma": "OK", "oregon": "OR",
        "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
        "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT",
        "virginia": "VA", "washington": "WA", "west virginia": "WV", "wisconsin": "WI",
        "wyoming": "WY", "puerto rico": "PR", "virgin islands": "VI", "guam": "GU",
        "american samoa": "AS",
    ]

    static func abbreviation(for term: String) -> String? {
        let t = term.trimmingCharacters(in: .whitespaces).lowercased()
        if t.count == 2, t.range(of: "^[a-z]{2}$", options: .regularExpression) != nil {
            return t.uppercased()
        }
        return map[t]
    }

    /// One design language on tile kickers: always the 2-letter code(s).
    static func kicker(_ states: String) -> String {
        states.split(separator: ",").prefix(3).map { part in
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.count == 2 { return t.uppercased() }
            return map[t.lowercased()] ?? t
        }.joined(separator: ", ")
    }
}

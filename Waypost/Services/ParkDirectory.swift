import Foundation
import MapKit

/// Finding a park that is not one of the eight the app ships with.
///
/// The catalogue screens were reading the curated library, which is why every search
/// answered with the same handful of parks. This is the live directory behind them.
/// It answers four questions, which are the four ways a person actually looks for a
/// park:
///
///  * **By name** — "arches", "great smoky"
///  * **By state** — "utah", "UT"
///  * **By city or place** — "moab", "denver", "flagstaff"
///  * **Near me** — from the device fix, or the loose IP city if that is refused
///
/// Two sources, in that order of preference:
///
///  1. **The National Park Service API**, through the proxy. Authoritative for NPS
///     units — the fee, the designation, the gateway town, the directions.
///  2. **OpenStreetMap** — Nominatim to turn words into a place, Overpass to find the
///     protected areas around it. No key, no proxy, so search works on a phone that has
///     never been given either. It also knows about state and county parks, which NPS
///     does not.
///
/// Whatever answers, the park carries the name of the source with it, and any field the
/// source did not publish stays empty and says so. A park found through OpenStreetMap
/// never shows an NPS fee, and neither of them ever shows an invented one.
@MainActor
@Observable
final class ParkDirectory {
    typealias Source = CatalogueSource

    struct Hit: Identifiable, Hashable {
        var park: CuratedPark
        var source: Source
        /// Miles from whatever the search was anchored to, when it was anchored at all.
        var miles: Int?
        var id: String { park.code }
    }

    enum Phase: Equatable {
        case idle
        case searching
        case ready
        /// Every source refused or failed. Not the same as "no parks are there".
        case unanswered(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var hits: [Hit] = []
    /// Which sources actually answered this search, for the line under the field.
    private(set) var answered: Set<Source> = []

    private var inFlight: Task<Void, Never>?
    private let failures = FailureLog()
    private let location = LocationService()

    private var nps: NPSService { NPSService(proxy: ProxyConfig(), failures: failures) }

    // MARK: Searching

    /// Types-ahead safe: each keystroke cancels the last search rather than racing it.
    func search(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespaces)
        inFlight?.cancel()
        guard query.count >= 2 else {
            hits = []; answered = []; phase = .idle
            return
        }

        phase = .searching
        inFlight = Task { [weak self] in
            guard let self else { return }
            // A short pause so a fast typist makes one request, not eight.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await run(query: query)
        }
    }

    /// Parks around a point. Used for "near me" and for the shelf on Discover.
    func near(lat: Double, lon: Double, radiusMiles: Int = 200) {
        inFlight?.cancel()
        phase = .searching
        inFlight = Task { [weak self] in
            guard let self else { return }
            let found = await overpassPlaces(lat: lat, lon: lon, radiusMiles: radiusMiles)
                .map { Hit(park: CuratedPark(osm: $0), source: $0.source) }
            guard !Task.isCancelled else { return }
            finish(found, anchor: (lat, lon))
        }
    }

    /// Where the phone is, then the parks around it.
    func nearMe(radiusMiles: Int = 200) {
        inFlight?.cancel()
        phase = .searching
        inFlight = Task { [weak self] in
            guard let self else { return }
            guard let fix = await location.currentFix() else {
                guard !Task.isCancelled else { return }
                phase = .unanswered("This iPhone did not give a location, and the fallback lookup did not answer either.")
                return
            }
            let found = await overpassPlaces(lat: fix.lat, lon: fix.lon, radiusMiles: radiusMiles)
                .map { Hit(park: CuratedPark(osm: $0), source: $0.source) }
            guard !Task.isCancelled else { return }
            finish(found, anchor: (fix.lat, fix.lon))
        }
    }

    /// Sources answer at very different speeds — Nominatim in about a second, a
    /// state-wide Overpass query in thirty to ninety. Waiting for the slowest before
    /// showing anything is why a search for Texas looked like it had failed. Each source
    /// now publishes as it lands, and the list fills in.
    /// Every source at once, and the screen updates whenever any of them lands.
    ///
    /// Running them in order cost the wait of all of them added together. They now run
    /// together, except for Nominatim's own terms: it rate-limits a caller that opens
    /// several connections at once and answers none of them, which is worse than asking
    /// twice in a row. So the terms are a chain, and the chain publishes after each one.
    private func run(query: String) async {
        answered = []
        building = []
        anchor = nil

        // A term searched a moment ago comes back instantly. People retype and backspace
        // far more than they type something new.
        if let cached = Self.cache[query.lowercased()] {
            hits = cached
            answered.insert(.openStreetMap)
            phase = .ready
        }

        let stateCode = USStates.abbreviation(for: query)

        // The list on the phone, first and instantly. Sixty-two parks, no network, no
        // wait — whatever the sources add after this is added to something already on
        // screen rather than to an empty page.
        let bundled = NationalParks.search(query)
        if !bundled.isEmpty {
            answered.insert(.onDevice)
            building = bundled.map { Hit(park: CuratedPark(bundled: $0), source: .onDevice) }
            publish(building, anchor: nil)
        }

        await withTaskGroup(of: Void.self) { group in
            // The quick chain. A state needs asking twice — "Texas" alone returns the
            // state polygon and no parks — and the first answer is on screen in about a
            // second, before the second is even sent.
            group.addTask { @MainActor in
                // Apple Maps answers in well under a second and does not rate-limit.
                // Nominatim does both the other way round — it refuses a second caller
                // outright with a 429, which is how a working search came to look empty.
                let terms = stateCode == nil
                    ? ["national parks near \(query)", "state parks near \(query)"]
                    : ["national parks in \(query)", "state parks in \(query)"]
                for term in terms {
                    if Task.isCancelled { return }
                    self.absorb(places: await self.appleParks(term), state: stateCode)
                }
                // Only if Apple had nothing is Nominatim worth the wait.
                if self.building.isEmpty, !Task.isCancelled {
                    self.absorb(places: await self.nominatim(query), state: stateCode)
                }
                if let anchor = self.anchor, stateCode == nil {
                    self.absorb(places: await self.overpassPlaces(lat: anchor.lat,
                                                                  lon: anchor.lon,
                                                                  radiusMiles: 150),
                                state: nil)
                }
            }

            // NPS in parallel rather than after it: when the proxy refuses, the refusal
            // costs nothing, because nothing is waiting behind it.
            if nps.isReady {
                group.addTask { @MainActor in
                    self.absorb(parks: await self.nps.search(query))
                }
            }

            // A state is somewhere the slow sweep can start on immediately — it needs
            // nothing geocoded first.
            if let stateCode {
                group.addTask { @MainActor in
                    self.absorb(places: await self.overpassPlacesInState(stateCode),
                                state: stateCode)
                }
            }
        }

        guard !Task.isCancelled else { return }
        finish(building, anchor: anchor)
        Self.cache[query.lowercased()] = hits
    }

    /// What the sources have handed over so far, and the point they are measured from.
    private var building: [Hit] = []
    private var anchor: (lat: Double, lon: Double)?

    private func absorb(places: [OSMPlace], state: String?) {
        for var place in places {
            // A park that is already in the list on the phone keeps that list's code, so
            // it resolves to the photograph already cached against it rather than being
            // looked up again as though it were a stranger.
            if let bundled = NationalParks.all.first(where: {
                $0.full.caseInsensitiveCompare(place.name) == .orderedSame
                    || $0.name.caseInsensitiveCompare(CuratedPark.shortName(place.name)) == .orderedSame
            }) {
                place.id = bundled.code
                if place.state.isEmpty { place.state = bundled.state }
            }
            // A row from another state is not an answer to "Texas".
            if let state, !place.state.isEmpty, place.state != state { continue }
            if place.isPark {
                building.append(Hit(park: CuratedPark(osm: place), source: place.source))
            } else if anchor == nil {
                anchor = (place.lat, place.lon)
            }
        }
        if anchor == nil, let first = building.first {
            anchor = (first.park.lat, first.park.lon)
        }
        publish(building, anchor: state == nil ? anchor : nil)
    }

    private func absorb(parks: [Park]) {
        guard !parks.isEmpty else { return }
        answered.insert(.nps)
        building += parks.map { Hit(park: CuratedPark(live: $0), source: .nps) }
        publish(building, anchor: anchor)
    }

    /// Searches already run this session. Small on purpose — a typing aid, not a database.
    private static var cache: [String: [Hit]] = [:] {
        didSet { if cache.count > 24 { cache.removeAll() } }
    }

    /// Results so far, on screen now, without declaring the search over.
    private func publish(_ found: [Hit], anchor: (lat: Double, lon: Double)?) {
        hits = Self.ordered(Self.deduped(found, anchor: anchor))
        // Parks are on screen, so the search has answered — the slower source is still
        // filling in behind it, which is not the same as still having nothing to show.
        if !hits.isEmpty { phase = .ready }
    }

    private func finish(_ found: [Hit], anchor: (lat: Double, lon: Double)?) {
        let deduped = Self.ordered(Self.deduped(found, anchor: anchor))
        hits = deduped
        if !deduped.isEmpty || !answered.isEmpty {
            phase = .ready
        } else if let why = failures.failures["protected areas (Overpass)"]
                    ?? failures.failures["place lookup (Nominatim)"]
                    ?? failures.failures.values.first {
            phase = .unanswered("No source answered — \(why).")
        } else {
            phase = .unanswered("No source answered.")
        }
    }

    /// One park can come back from more than one source under slightly different names.
    /// The first to arrive wins, and NPS is asked before Overpass for that reason.
    private static func deduped(_ found: [Hit], anchor: (lat: Double, lon: Double)?) -> [Hit] {
        var seen = Set<String>()
        var out: [Hit] = []
        for hit in found {
            let key = matchKey(hit.park.name)
            if seen.contains(key) { continue }
            seen.insert(key)
            var hit = hit
            if let anchor {
                hit.miles = Int(Geo.haversine(anchor, (hit.park.lat, hit.park.lon)).rounded())
            }
            out.append(hit)
        }
        return out
    }

    /// Overpass truncates arbitrarily, so the caps are high and the ordering is done here
    /// with the whole set in hand: national parks first, then monuments, then everything
    /// else — nearest first within a rank. A search for Utah that opens on a wildlife
    /// management area has technically answered and practically failed.
    private static func ordered(_ hits: [Hit]) -> [Hit] {
        hits.sorted { a, b in
            let ra = rank(a.park), rb = rank(b.park)
            if ra != rb { return ra < rb }
            if let ma = a.miles, let mb = b.miles, ma != mb { return ma < mb }
            return a.park.name < b.park.name
        }
    }

    /// What a person means by "park", in the order they mean it.
    private static func rank(_ park: CuratedPark) -> Int {
        let text = (park.full + " " + park.crowd).lowercased()
        if text.contains("national park") { return 0 }
        if text.contains("national monument") || text.contains("national preserve") { return 1 }
        if text.contains("national") { return 2 }
        if text.contains("state park") { return 3 }
        return 4
    }

    /// "Arches National Park" and "Arches NP" are the same park.
    private static func matchKey(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "national park and preserve", with: "")
            .replacingOccurrences(of: "national park", with: "")
            .replacingOccurrences(of: "national monument", with: "")
            .replacingOccurrences(of: "state park", with: "")
            .replacingOccurrences(of: " np", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: OpenStreetMap


    /// Parks by name, city or state, from Apple Maps.
    ///
    /// This is the fast half of the search: MapKit answers a natural-language query in a
    /// fraction of a second, needs no key and has no rate limit worth worrying about.
    /// Anything whose name does not carry a designation is dropped — "parks in Texas"
    /// otherwise returns car parks, trailer parks and the Texas Rangers.
    private func appleParks(_ term: String) async -> [OSMPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            answered.insert(.appleMaps)
            return response.mapItems.compactMap { item -> OSMPlace? in
                guard let name = item.name,
                      let designation = ParkDesignation.inName(name),
                      // "Western National Parks Store - Guadalupe Mountains" carries a
                      // designation in its name and is a gift shop. So do the visitor
                      // centres, ranger stations and campgrounds inside a park; the park
                      // is the thing being searched for, not its buildings.
                      !Self.isNotThePark(name) else { return nil }
                let placemark = item.placemark
                return OSMPlace(
                    id: "apple-\(name)-\(placemark.coordinate.latitude),\(placemark.coordinate.longitude)",
                    name: name,
                    lat: placemark.coordinate.latitude,
                    lon: placemark.coordinate.longitude,
                    state: placemark.administrativeArea.flatMap { USStates.abbreviation(for: $0) ?? $0 } ?? "",
                    designation: designation,
                    isPark: true,
                    website: item.url?.absoluteString,
                    source: .appleMaps
                )
            }
        } catch {
            failures.note("parks (Apple Maps)", error)
            return []
        }
    }

    /// Things named after a park that are not the park.
    private static func isNotThePark(_ name: String) -> Bool {
        let noise = ["store", "shop", "gift", "visitor center", "visitor centre",
                     "ranger station", "campground", "trading post", "museum",
                     "association", "conservancy", "headquarters", "lodge", "inn",
                     "hotel", "restaurant", "parking"]
        let lowered = name.lowercased()
        return noise.contains { lowered.contains($0) }
    }

    /// Places for a set of words. Nominatim asks for a real user agent and refuses
    /// anonymous callers, which is fair.
    private func nominatim(_ query: String) async -> [OSMPlace] {
        var c = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        c.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "jsonv2"),
            .init(name: "addressdetails", value: "1"),
            .init(name: "extratags", value: "1"),
            .init(name: "countrycodes", value: "us"),
            .init(name: "limit", value: "20"),
        ]
        guard let url = c.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25

        do {
            answered.insert(.openStreetMap)
            let rows = try await NominatimGate.shared.run { try await HTTP.array(request) }
            return rows.compactMap(OSMPlace.init(nominatim:))
        } catch {
            failures.note("place lookup (Nominatim)", error)
            return []
        }
    }

    /// What counts as a park, in OpenStreetMap's own vocabulary.
    ///
    /// `protect_class` looked like the right filter and is the wrong one: Grand Canyon
    /// National Park does not carry it, so a class filter drops precisely the parks
    /// anybody is searching for. `protection_title` is the tag mappers actually fill in,
    /// and it holds the designation verbatim.
    private static let designations =
        "National Park|National Monument|National Preserve|National Seashore" +
        "|National Lakeshore|National Recreation Area|National Historical Park" +
        "|State Park|State Recreation Area|Wilderness"

    /// The protected areas inside one state, as places.
    private func overpassPlacesInState(_ abbreviation: String) async -> [OSMPlace] {
        let query = """
        [out:json][timeout:80];
        area["ISO3166-2"="US-\(abbreviation)"][admin_level=4]->.a;
        (
          nwr["boundary"="national_park"]["name"](area.a);
          nwr["boundary"="protected_area"]["protection_title"~"\(Self.designations)",i](area.a);
        );
        out tags center 200;
        """
        return await overpassPlaces(query, state: abbreviation)
    }

    private func overpassPlaces(lat: Double, lon: Double, radiusMiles: Int) async -> [OSMPlace] {
        let metres = Int(Double(radiusMiles) * 1609.34)
        let query = """
        [out:json][timeout:80];
        (
          nwr["boundary"="national_park"]["name"](around:\(metres),\(lat),\(lon));
          nwr["boundary"="protected_area"]["protection_title"~"\(Self.designations)",i](around:\(metres),\(lat),\(lon));
        );
        out tags center 200;
        """
        return await overpassPlaces(query, state: nil)
    }

    /// The public Overpass servers are free and correspondingly busy — the main one
    /// answers 504 under load often enough that a single-host client reads as broken.
    /// The mirrors run the same database, so the first one that answers wins.
    private static let overpassHosts = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    private func overpassPlaces(_ query: String, state: String?) async -> [OSMPlace] {
        var lastError: Error?
        var answeredAtAll = false
        for host in Self.overpassHosts {
            guard let url = URL(string: host) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
                .data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            // A state-wide query genuinely takes half a minute on a public server. The
            // app's usual 15-second budget was cutting it off and reading the timeout as
            // "no parks in Utah", which is the confusion this codebase refuses to make.
            request.timeoutInterval = 90

            do {
                let obj = try await HTTP.any(request)
                let elements = obj["elements"] as? [[String: Any]] ?? []
                let places = elements.compactMap { OSMPlace(overpass: $0, state: state) }
                answeredAtAll = true
                // A mirror that is behind on its area index answers 200 with nothing in
                // it. That is indistinguishable from "no parks here" unless the next
                // mirror is asked, so an empty answer is not accepted as the answer.
                if places.isEmpty { continue }
                answered.insert(.openStreetMap)
                return places
            } catch {
                lastError = error
                continue
            }
        }
        if answeredAtAll {
            answered.insert(.openStreetMap)
        } else if let lastError {
            failures.note("protected areas (Overpass)", lastError)
        }
        return []
    }

    /// Both OSM services ask callers to identify themselves, and block the ones that don't.
    static let userAgent = "ParkHop/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1") (parkhop.us)"
}

// MARK: - One place, as OpenStreetMap has it

struct OSMPlace: Hashable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var state: String
    var designation: String?
    var isPark: Bool
    var website: String?
    /// Which map this came off. Apple Maps and OpenStreetMap know different things and
    /// the card says which one it is reading.
    var source: CatalogueSource = .openStreetMap

    init(id: String, name: String, lat: Double, lon: Double,
         state: String, designation: String?, isPark: Bool, website: String?,
         source: CatalogueSource = .openStreetMap) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.state = state
        self.designation = designation
        self.isPark = isPark
        self.website = website
        self.source = source
    }

    init?(nominatim row: [String: Any]) {
        guard let lat = Double(row["lat"] as? String ?? ""),
              let lon = Double(row["lon"] as? String ?? ""),
              let name = (row["name"] as? String) ?? (row["display_name"] as? String)
        else { return nil }

        let category = row["category"] as? String ?? row["class"] as? String ?? ""
        let type = row["type"] as? String ?? ""
        let address = row["address"] as? [String: Any] ?? [:]
        let extra = row["extratags"] as? [String: Any] ?? [:]

        self.id = "osm-" + String(describing: row["osm_id"] ?? UUID().uuidString)
        self.name = name.split(separator: ",").first.map(String.init) ?? name
        self.lat = lat
        self.lon = lon
        self.state = OSMPlace.stateCode(address["state"] as? String)
        self.designation = (extra["protection_title"] as? String)
            ?? OSMPlace.designation(inName: name)
        self.isPark = type == "national_park" || type == "protected_area" || type == "nature_reserve"
            || (category == "leisure" && type == "park")
            || (extra["protect_class"] != nil)
        self.website = extra["website"] as? String
    }

    init?(overpass element: [String: Any], state: String?) {
        let tags = element["tags"] as? [String: Any] ?? [:]
        guard let name = tags["name"] as? String, !name.isEmpty else { return nil }
        // Ways and relations carry their coordinates under `center`; nodes carry them flat.
        let centre = element["center"] as? [String: Any]
        guard let lat = (centre?["lat"] as? Double) ?? (element["lat"] as? Double),
              let lon = (centre?["lon"] as? Double) ?? (element["lon"] as? Double)
        else { return nil }

        self.id = "osm-" + String(describing: element["id"] ?? UUID().uuidString)
        self.name = name
        self.lat = lat
        self.lon = lon
        self.state = state ?? OSMPlace.stateCode(tags["addr:state"] as? String)
        // `boundary=national_park` is used for monuments, preserves and forests alike, so
        // it is not evidence that this is a national park. The title tag is; failing that,
        // the park's own name is; failing both, it stays a protected area.
        self.designation = (tags["protection_title"] as? String)
            ?? OSMPlace.designation(inName: name)
        self.isPark = true
        self.website = tags["website"] as? String
    }

    /// "Petrified Forest National Park" says what it is in its own name.
    static func designation(inName name: String) -> String? {
        for title in ["National Park and Preserve", "National Park", "National Monument",
                      "National Preserve", "National Seashore", "National Lakeshore",
                      "National Recreation Area", "National Historical Park",
                      "National Forest", "State Park", "State Recreation Area", "Wilderness"]
        where name.localizedCaseInsensitiveContains(title) {
            return title
        }
        return nil
    }

    private static func stateCode(_ name: String?) -> String {
        guard let name else { return "" }
        return USStates.abbreviation(for: name) ?? name
    }
}

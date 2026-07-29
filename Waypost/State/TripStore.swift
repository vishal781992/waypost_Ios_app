import Foundation
import Observation

enum AppView { case plan, trip }
enum TravelMode: String, Codable { case drive, fly }
enum Vehicle: String, Codable { case gas, ev }
enum ParkSource: String, Codable { case nps, state }

struct ParkFacts {
    var reservation: Reservation
    var parkingLots: [Lodging]
    var parkingNote: String
    var parkingBadge: String
}

/// Everything the app knows, and every fetch that fills it in.
///
/// One store rather than a view model per screen: the plan screen and the trip screen
/// are two renderings of the same trip, exactly as the web app's single component is.
@MainActor
@Observable
final class TripStore {

    // MARK: Services

    let failures = FailureLog()
    let proxy = ProxyConfig()
    let location = LocationService()

    private var nps: NPSService { NPSService(proxy: proxy, failures: failures) }
    private var weather: WeatherService { WeatherService(failures: failures) }
    private var routing: RoutingService { RoutingService(failures: failures) }
    private var overpass: OverpassService { OverpassService(failures: failures) }
    private var recreation: RecreationService { RecreationService(failures: failures) }
    private var proxied: ProxyServices { ProxyServices(proxy: proxy, failures: failures) }

    // MARK: Plan state

    var view: AppView = .plan
    var order: [String] = []
    var daysByPark: [String: Int] = [:]
    var start: Date = WPDate.today()
    var origin: City?
    var originQuery: String = ""
    var originSuggestions: [ProxyServices.Suggestion] = []
    var mode: TravelMode = .drive
    var vehicle: Vehicle = .ev
    var parkSource: ParkSource = .nps
    var query: String = ""
    var originNote: String = ""

    // MARK: Catalog

    private(set) var parksByCode: [String: Park] = Datasets.shared.seedParksByCode
    private(set) var nearbyCodes: [String] = []
    private(set) var searchResults: [Park] = []
    private(set) var isSearching = false
    private var locatedAt: (lat: Double, lon: Double)?
    private var nearbyLoaded = false

    // MARK: Live caches, all keyed so a date or route change refetches

    private(set) var forecastByKey: [String: WeatherDay] = [:]      // "code|iso"
    private(set) var normalsByKey: [String: WeatherDay] = [:]
    private(set) var campsByPark: [String: [Campground]] = [:]
    private(set) var availability: [String: AvailabilityLevel] = [:] // "code|campground|iso"
    private(set) var alertsByPark: [String: [Alert]] = [:]
    private(set) var factsByPark: [String: ParkFacts] = [:]
    private(set) var staysByPark: [String: [Lodging]] = [:]
    private(set) var routesByLeg: [String: RoutingService.Route] = [:]
    private(set) var chargersByLeg: [String: [String]] = [:]
    private(set) var fuelByPark: [String: [String]] = [:]
    private(set) var thingsToDoByPark: [String: [String]] = [:]
    private(set) var photoByPark: [String: URL] = [:]
    /// Which parks have data that came from a live source rather than the bundled
    /// curated record. A panel only claims to be live when its source actually answered.
    private(set) var campsAreLive: Set<String> = []
    private(set) var alertsAreLive: Set<String> = []
    private(set) var staysAreLive: Set<String> = []
    /// Parks whose NPS panels asked and got nothing back — a refusal, not an absence.
    private(set) var npsDidNotAnswer: Set<String> = []

    /// Tab selection per park, so scrolling between parks doesn't reset the others.
    var tabByPark: [String: ParkTab] = [:]

    private var searchTask: Task<Void, Never>?
    private var geocodeTask: Task<Void, Never>?
    /// Bumped whenever the trip changes; in-flight answers for an older trip are dropped.
    private var generation = 0

    // MARK: - Lifecycle

    func start() async {
        restore()
        await locate()
    }

    var originCity: City {
        origin ?? Datasets.shared.cities.first { $0.id == "den" }
            ?? City(id: "den", name: "Denver, CO", lat: 39.74, lon: -104.99, airport: "DEN")
    }

    func park(_ code: String) -> Park? { parksByCode[code] }

    // MARK: - Location and the nearby shelf

    func locate() async {
        guard let fix = await location.currentFix() else {
            let city = origin ?? Datasets.shared.cities.first
            if let city { await loadNearby(lat: city.lat, lon: city.lon) }
            return
        }
        if origin == nil {
            // An IP fix often lands on a township, so snap to the nearest real city
            // before showing it as the origin.
            let nearest = Datasets.shared.cities
                .map { ($0, Geo.haversine((fix.lat, fix.lon), ($0.lat, $0.lon))) }
                .min { $0.1 < $1.1 }
            if let nearest, nearest.1 <= 70 {
                setOrigin(nearest.0)
            } else if let cityName = fix.city {
                let name = fix.region.map { "\(cityName), \($0)" } ?? cityName
                setOrigin(City(id: "located", name: name, lat: fix.lat, lon: fix.lon, airport: nil))
            }
        }
        await loadNearby(lat: fix.lat, lon: fix.lon)
    }

    /// The six nearest parks. Deterministic: the same place gives the same shelf every
    /// launch, so nothing shifts under the user between sessions.
    func loadNearby(lat: Double, lon: Double) async {
        guard !nearbyLoaded else { return }
        locatedAt = (lat, lon)

        var ranked: [(park: Park, miles: Double)] = []
        switch parkSource {
        case .state:
            ranked = Datasets.shared.stateParks
                .map { (Self.statePark(from: $0), Geo.haversine((lat, lon), ($0.lat, $0.lon))) }
                .sorted { $0.1 < $1.1 }
        case .nps:
            guard nps.isReady else { return }   // no proxy: the shelf stays on seed parks
            ranked = await nps.allParks()
                .filter(\.hasCoordinates)
                .map { ($0, Geo.haversine((lat, lon), ($0.lat, $0.lon))) }
                .sorted { $0.1 < $1.1 }
        }

        guard !ranked.isEmpty else {
            // Keep the app usable when the registry is unreachable: the seed parks are
            // bundled and always work.
            if nearbyCodes.isEmpty { nearbyCodes = Datasets.shared.seedParks.map(\.code) }
            return
        }
        nearbyLoaded = true

        var codes: [String] = []
        for entry in ranked.prefix(6) {
            var park = entry.park
            park.distMi = Int(entry.miles.rounded())
            parksByCode[park.code] = park
            codes.append(park.code)
        }
        nearbyCodes = codes

        for code in codes {
            Task { await self.loadPhoto(code) }
        }
    }

    func setParkSource(_ source: ParkSource) {
        guard source != parkSource else { return }
        parkSource = source
        query = ""
        searchResults = []
        nearbyCodes = []
        nearbyLoaded = false
        if let at = locatedAt {
            Task { await self.loadNearby(lat: at.lat, lon: at.lon) }
        } else {
            Task { await self.locate() }
        }
    }

    static func statePark(from row: StateParkRow) -> Park {
        let slug = row.n.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let image = row.i.map {
            "https://commons.wikimedia.org/wiki/Special:FilePath/\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)?width=1000"
        }
        return Park(
            code: "sp-\(row.s.lowercased())-\(slug)",
            name: row.n.replacingOccurrences(of: " State Park.*$", with: "", options: .regularExpression),
            full: row.n,
            state: row.s,
            lat: row.lat,
            lon: row.lon,
            tagline: "State Park",
            gateway: row.n,
            tier: .state,
            designation: "State Park",
            website: row.w,
            wikiImage: image,
            fee: "See the park website",
            hours: "See the park website"
        )
    }

    // MARK: - Search

    func queryChanged(_ text: String) {
        query = text
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { searchResults = []; isSearching = false; return }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))     // one search per pause, not per keystroke
            guard let self, !Task.isCancelled else { return }
            self.isSearching = true
            let hits: [Park]
            switch self.parkSource {
            case .state:
                hits = Self.searchStateParks(trimmed)
            case .nps:
                hits = self.nps.isReady ? await self.nps.search(trimmed) : Self.searchSeedParks(trimmed)
            }
            guard !Task.isCancelled, self.query.trimmingCharacters(in: .whitespaces) == trimmed else { return }
            for park in hits where self.parksByCode[park.code] == nil {
                self.parksByCode[park.code] = park
            }
            self.searchResults = hits
            self.isSearching = false
        }
    }

    /// Runs entirely on the bundled dataset — no API call, no quota.
    private static func searchStateParks(_ term: String) -> [Park] {
        let needle = term.lowercased()
        let abbreviation = USStates.abbreviation(for: term)
        return Datasets.shared.stateParks
            .filter { row in
                if let abbreviation, row.s == abbreviation { return true }
                return row.n.lowercased().contains(needle)
            }
            .prefix(24)
            .map(statePark(from:))
    }

    /// Without a proxy there is no NPS registry to search, so the six bundled parks are
    /// all the app can honestly offer.
    private static func searchSeedParks(_ term: String) -> [Park] {
        let needle = term.lowercased()
        return Datasets.shared.seedParks.filter {
            $0.name.lowercased().contains(needle)
                || $0.full.lowercased().contains(needle)
                || $0.state.lowercased().contains(needle)
        }
    }

    /// What the plan screen lists: everything picked, then the nearby shelf or the
    /// current search hits. De-duplicated by code so a park can't appear twice.
    var catalog: [Park] {
        var seen = Set<String>()
        var rows: [Park] = []
        func add(_ park: Park?) {
            guard let park, !seen.contains(park.code) else { return }
            seen.insert(park.code)
            rows.append(park)
        }
        // Picks first: a search must never bury a park you already chose.
        order.forEach { add(park($0)) }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            nearbyCodes.forEach { add(park($0)) }
            if nearbyCodes.isEmpty { Datasets.shared.seedParks.forEach { add($0) } }
        } else {
            searchResults.forEach { add($0) }
        }
        return rows
    }

    var searchNote: String? {
        if isSearching { return "Searching the NPS registry…" }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty && searchResults.isEmpty {
            return "Nothing matches \"\(q)\" — try a park name or a state."
        }
        return nil
    }

    var sourceNote: String? {
        switch parkSource {
        case .state:
            return "State parks publish coordinates and a website nationwide — no hours, fees, alerts or campsite feed exists, so those panels will say so rather than guess."
        case .nps:
            return proxy.isConnected ? nil : "Connect the data proxy to search the full NPS registry. Without it the shelf is the six bundled parks."
        }
    }

    // MARK: - Picking

    func isPicked(_ code: String) -> Bool { order.contains(code) }

    func togglePark(_ code: String) {
        if let index = order.firstIndex(of: code) {
            order.remove(at: index)
            daysByPark[code] = nil
        } else {
            order.append(code)
            daysByPark[code] = daysByPark[code] ?? 2
            Task { await self.loadPhoto(code) }
        }
        persist()
    }

    func days(for code: String) -> Int { daysByPark[code] ?? 2 }

    func adjustDays(_ code: String, by delta: Int) {
        daysByPark[code] = max(1, min(14, days(for: code) + delta))
        persist()
    }

    func clearPicks() {
        order = []
        daysByPark = [:]
        persist()
    }

    func setStart(_ date: Date) {
        start = Calendar.current.startOfDay(for: date)
        // Every live answer is date-specific; drop them all rather than show yesterday's
        // weather under today's heading.
        forecastByKey = [:]
        normalsByKey = [:]
        availability = [:]
        staysByPark = [:]
        generation += 1
        persist()
    }

    func setOrigin(_ city: City) {
        origin = city
        originQuery = city.name
        originSuggestions = []
        originNote = "Routing from \(city.name)."
        routesByLeg = [:]
        chargersByLeg = [:]
        persist()
    }

    func originQueryChanged(_ text: String) {
        originQuery = text
        geocodeTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { originSuggestions = []; return }

        geocodeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            var hits = await self.proxied.geocode(trimmed)
            if hits.isEmpty {
                // No proxy (or nothing found) — fall back to the bundled cities, so
                // picking an origin always works offline.
                hits = Datasets.shared.cities
                    .filter { $0.name.lowercased().contains(trimmed.lowercased()) }
                    .map { ProxyServices.Suggestion(name: $0.name, lat: $0.lat, lon: $0.lon) }
            }
            guard !Task.isCancelled else { return }
            self.originSuggestions = hits
        }
    }

    func pickSuggestion(_ suggestion: ProxyServices.Suggestion) {
        setOrigin(City(id: "custom", name: suggestion.name, lat: suggestion.lat, lon: suggestion.lon, airport: nil))
    }

    // MARK: - Schedule

    var schedule: Schedule {
        let city = originCity
        var cursor = start
        var stops: [Stop] = []
        var previous = (key: city.id, lat: city.lat, lon: city.lon, name: city.shortName)

        for code in order {
            guard let park = park(code) else { continue }
            let stayDays = days(for: code)
            let leg = Geo.legBetween(fromKey: previous.key, fromLat: previous.lat, fromLon: previous.lon,
                                     toKey: park.code, toLat: park.lat, toLon: park.lon)
            let end = WPDate.addDays(cursor, stayDays - 1)
            stops.append(Stop(park: park, days: stayDays, start: cursor, end: end, leg: leg,
                              fromName: previous.name, legKey: "\(previous.key)|\(park.code)",
                              fromLat: previous.lat, fromLon: previous.lon))
            cursor = WPDate.addDays(end, 1)
            previous = (park.code, park.lat, park.lon, park.name)
        }

        var home: HomeLeg?
        if let last = stops.last {
            let leg = Geo.legBetween(fromKey: last.park.code, fromLat: last.park.lat, fromLon: last.park.lon,
                                     toKey: city.id, toLat: city.lat, toLon: city.lon)
            home = HomeLeg(leg: leg, date: WPDate.addDays(last.end, 1), fromName: last.park.name,
                           toName: city.shortName, legKey: "\(last.park.code)|\(city.id)",
                           fromLat: last.park.lat, fromLon: last.park.lon,
                           toLat: city.lat, toLon: city.lon)
        }

        let totalDays = stops.reduce(0) { $0 + $1.days }
        return Schedule(city: city, stops: stops, home: home,
                        end: WPDate.addDays(start, max(0, totalDays - 1)))
    }

    var totalDays: Int { schedule.stops.reduce(0) { $0 + $1.days } }

    /// Road miles, preferring the live OSRM number over the curated one.
    func miles(forLeg key: String, fallback: Int) -> Int {
        routesByLeg[key]?.miles ?? fallback
    }

    var totalMiles: Int {
        let s = schedule
        var sum = s.stops.reduce(0) { $0 + miles(forLeg: $1.legKey, fallback: $1.leg.mi) }
        if let home = s.home { sum += miles(forLeg: home.legKey, fallback: home.leg.mi) }
        return sum
    }

    // MARK: - Building the itinerary

    func buildTrip() {
        let s = schedule
        guard !s.stops.isEmpty else { return }
        for stop in s.stops where tabByPark[stop.park.code] == nil {
            tabByPark[stop.park.code] = .overview
        }
        view = .trip
        persist()
        Task { await self.fetchLive() }
    }

    func backToPlan() {
        view = .plan
        persist()
    }

    /// Every live source for the current trip, fired concurrently. Each cache is keyed
    /// by park and date, so re-entering an unchanged trip costs nothing and a changed
    /// date refetches exactly what moved.
    func fetchLive() async {
        let s = schedule
        generation += 1
        let gen = generation

        await withTaskGroup(of: Void.self) { group in
            for stop in s.stops {
                let park = stop.park
                let iso = WPDate.iso(stop.start)
                let checkout = WPDate.iso(stop.end)

                group.addTask { await self.loadWeather(park: park, iso: iso, gen: gen) }
                group.addTask { await self.loadCampgrounds(stop: stop, gen: gen) }
                group.addTask { await self.loadStays(park: park, checkIn: iso, checkOut: checkout, gen: gen) }
                group.addTask { await self.loadAlerts(park: park, gen: gen) }
                group.addTask { await self.loadFacts(park: park, gen: gen) }
                group.addTask { await self.loadThingsToDo(park: park, gen: gen) }
                group.addTask { await self.loadFuel(park: park, gen: gen) }
                group.addTask { await self.loadPhoto(park.code) }
                group.addTask {
                    await self.loadRoute(key: stop.legKey, fromLat: stop.fromLat, fromLon: stop.fromLon,
                                         toLat: park.lat, toLon: park.lon, gen: gen)
                }
            }
            if let home = s.home {
                group.addTask {
                    await self.loadRoute(key: home.legKey, fromLat: home.fromLat, fromLon: home.fromLon,
                                         toLat: home.toLat, toLon: home.toLon, gen: gen)
                }
            }
        }
    }

    // MARK: Individual loads

    private func loadWeather(park: Park, iso: String, gen: Int) async {
        let key = "\(park.code)|\(iso)"
        guard forecastByKey[key] == nil, normalsByKey[key] == nil else { return }

        if let forecast = await weather.forecast(lat: park.lat, lon: park.lon, iso: iso) {
            guard gen == generation else { return }
            forecastByKey[key] = forecast
            return
        }
        // Beyond the forecast horizon: real climate normals, labelled as averages.
        if let normals = await weather.normals(lat: park.lat, lon: park.lon, iso: iso) {
            guard gen == generation else { return }
            normalsByKey[key] = normals
        }
    }

    func weatherDay(for code: String, iso: String) -> WeatherDay? {
        forecastByKey["\(code)|\(iso)"] ?? normalsByKey["\(code)|\(iso)"]
    }

    private func loadCampgrounds(stop: Stop, gen: Int) async {
        let park = stop.park
        guard campsByPark[park.code] == nil else { return }

        var rows: [Campground] = []
        var live = false
        if park.tier != .state {
            if let answered = await nps.campgrounds(parkCode: park.code) {
                rows = answered
                live = true
            } else {
                npsDidNotAnswer.insert(park.code)
            }
        }
        // Radius search catches the USFS/BLM/state sites a park-scoped list misses, and
        // is the only campground source a state park has.
        let nearby = await proxied.campgroundsNearby(lat: park.lat, lon: park.lon)
        if !nearby.isEmpty { live = true }
        for row in nearby where !rows.contains(where: { $0.name == row.name }) {
            rows.append(row)
        }
        // Only when no source answered does the bundled record stand in — and the badge
        // then reads "Curated", never "Live".
        if rows.isEmpty && !live { rows = park.camping }
        guard gen == generation else { return }
        campsByPark[park.code] = rows
        if live { campsAreLive.insert(park.code) } else { campsAreLive.remove(park.code) }

        let nights = (0..<stop.days).map { WPDate.addDays(stop.start, $0) }
        for row in rows {
            let key = "\(park.code)|\(row.name)|\(WPDate.iso(stop.start))"
            guard availability[key] == nil else { continue }
            if let id = row.rgId {
                let level = await recreation.availability(campgroundID: id, nights: nights)
                guard gen == generation else { return }
                availability[key] = level
            } else {
                availability[key] = row.status.range(of: "first-come", options: .caseInsensitive) != nil
                    ? .firstCome : .unknown
            }
        }
    }

    func availability(park: String, campground: String, start: Date) -> AvailabilityLevel {
        availability["\(park)|\(campground)|\(WPDate.iso(start))"] ?? .unknown
    }

    private func loadStays(park: Park, checkIn: String, checkOut: String, gen: Int) async {
        guard staysByPark[park.code] == nil else { return }
        let live = await proxied.stays(lat: park.gatewayLat, lon: park.gatewayLon,
                                       checkIn: checkIn, checkOut: checkOut)
        guard gen == generation else { return }
        staysByPark[park.code] = live.isEmpty ? park.lodging : live
        if live.isEmpty { staysAreLive.remove(park.code) } else { staysAreLive.insert(park.code) }
    }

    private func loadAlerts(park: Park, gen: Int) async {
        guard alertsByPark[park.code] == nil, park.tier != .state else { return }
        guard let rows = await nps.alerts(parkCode: park.code) else {
            // NPS never answered. Leaving the cache empty keeps the panel saying so
            // rather than showing the bundled sample notices as if they were current.
            npsDidNotAnswer.insert(park.code)
            return
        }
        guard gen == generation else { return }
        alertsByPark[park.code] = rows
        if rows.isEmpty { alertsAreLive.remove(park.code) } else { alertsAreLive.insert(park.code) }
    }

    private func loadFacts(park: Park, gen: Int) async {
        guard factsByPark[park.code] == nil, park.tier != .state, nps.isReady else { return }
        guard let facts = await nps.facts(parkCode: park.code) else {
            npsDidNotAnswer.insert(park.code)
            return
        }
        guard gen == generation else { return }
        factsByPark[park.code] = ParkFacts(
            reservation: facts.reservation,
            parkingLots: facts.parking.lots,
            parkingNote: facts.parking.note,
            parkingBadge: facts.parking.badge
        )
    }

    private func loadThingsToDo(park: Park, gen: Int) async {
        guard thingsToDoByPark[park.code] == nil, park.tier != .state else { return }
        guard let rows = await nps.thingsToDo(parkCode: park.code) else {
            npsDidNotAnswer.insert(park.code)
            return
        }
        guard gen == generation, !rows.isEmpty else { return }
        thingsToDoByPark[park.code] = rows
    }

    private func loadFuel(park: Park, gen: Int) async {
        guard fuelByPark[park.code] == nil else { return }
        let rows = await overpass.fuelStations(lat: park.gatewayLat, lon: park.gatewayLon)
        guard gen == generation, !rows.isEmpty else { return }
        fuelByPark[park.code] = rows
    }

    private func loadRoute(key: String, fromLat: Double, fromLon: Double,
                           toLat: Double, toLon: Double, gen: Int) async {
        guard routesByLeg[key] == nil else { return }
        guard let route = await routing.route(fromLat: fromLat, fromLon: fromLon, toLat: toLat, toLon: toLon),
              gen == generation else { return }
        routesByLeg[key] = route

        // EV stops are looked up at the route's midpoint, so they sit near the line
        // rather than near either end.
        if vehicle == .ev, chargersByLeg[key] == nil, !route.coordinates.isEmpty {
            let mid = route.coordinates[route.coordinates.count / 2]
            let rows = await proxied.chargers(lat: mid.lat, lon: mid.lon, level: "dc", limit: 4, radius: 45)
            guard gen == generation, !rows.isEmpty else { return }
            chargersByLeg[key] = rows
        }
    }

    private func loadPhoto(_ code: String) async {
        guard photoByPark[code] == nil, let park = park(code) else { return }
        if park.tier == .state {
            if let url = safeURL(park.wikiImage) { photoByPark[code] = url }
            return
        }
        guard nps.isReady, let url = await nps.photo(parkCode: code) else { return }
        photoByPark[code] = url
    }

    // MARK: - Reset

    func reset() {
        order = []
        daysByPark = [:]
        tabByPark = [:]
        query = ""
        searchResults = []
        start = WPDate.today()
        origin = nil
        originQuery = ""
        originSuggestions = []
        originNote = ""
        mode = .drive
        vehicle = .ev
        parkSource = .nps
        view = .plan
        nearbyCodes = []
        nearbyLoaded = false
        parksByCode = Datasets.shared.seedParksByCode
        forecastByKey = [:]; normalsByKey = [:]; campsByPark = [:]; availability = [:]
        alertsByPark = [:]; factsByPark = [:]; staysByPark = [:]; routesByLeg = [:]
        chargersByLeg = [:]; fuelByPark = [:]; thingsToDoByPark = [:]; photoByPark = [:]
        campsAreLive = []; alertsAreLive = []; staysAreLive = []; npsDidNotAnswer = []
        failures.clear()
        generation += 1
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        Task { await self.locate() }
    }

    // MARK: - Persistence
    //
    // The same payload the web app keeps under `waypost-trip`, so a trip planned on the
    // phone reads the same as one planned in the browser.

    private static let persistenceKey = "waypost-trip"

    private struct Saved: Codable {
        var o: [String]
        var d: [String: Int]
        var s: String
        var c: SavedCity?
        var m: String
        var v: String
        var w: String
    }

    private struct SavedCity: Codable {
        var id: String
        var name: String
        var lat: Double
        var lon: Double
    }

    func persist() {
        let payload = Saved(
            o: order,
            d: daysByPark,
            s: WPDate.iso(start),
            c: origin.map { SavedCity(id: $0.id, name: $0.name, lat: $0.lat, lon: $0.lon) },
            m: mode.rawValue,
            v: vehicle.rawValue,
            w: view == .trip ? "trip" : "plan"
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              !saved.o.isEmpty else { return }
        order = saved.o
        daysByPark = saved.d
        start = WPDate.fromISO(saved.s) ?? WPDate.today()
        if let c = saved.c {
            origin = City(id: c.id, name: c.name, lat: c.lat, lon: c.lon, airport: nil)
            originQuery = c.name
        }
        mode = TravelMode(rawValue: saved.m) ?? .drive
        vehicle = Vehicle(rawValue: saved.v) ?? .ev

        // A park found through search isn't bundled — refetch it, and drop it from the
        // order if it no longer resolves rather than showing an empty section.
        let missing = order.filter { parksByCode[$0] == nil }
        if !missing.isEmpty {
            Task { await self.rehydrate(missing) }
        }
        if saved.w == "trip" {
            view = .trip
            Task { await self.fetchLive() }
        }
    }

    private func rehydrate(_ codes: [String]) async {
        for code in codes {
            if code.hasPrefix("sp-") {
                // State parks are bundled: rebuild from the local table.
                if let row = Datasets.shared.stateParks.first(where: { row in
                    Self.statePark(from: row).code == code
                }) {
                    parksByCode[code] = Self.statePark(from: row)
                    continue
                }
            }
            if nps.isReady, let park = await nps.park(code: code) {
                parksByCode[code] = park
            } else {
                order.removeAll { $0 == code }
                daysByPark[code] = nil
            }
        }
        persist()
    }
}

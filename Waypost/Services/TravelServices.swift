import Foundation

/// Real drive distance and time from OSRM's open routing server, plus a corridor
/// synthesised from the numbered highways actually driven.
@MainActor
struct RoutingService {
    let failures: FailureLog

    struct Route {
        var miles: Int
        var drive: String
        /// The same drive as a number. `drive` is rounded to five minutes and formatted
        /// for a label; anything that has to *compare* the drive — against a flight, say —
        /// needs it unparsed.
        var minutes: Int
        var corridor: String?
        /// Simplified geometry, for the map.
        var coordinates: [(lat: Double, lon: Double)]
    }

    func route(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) async -> Route? {
        let path = "\(fromLon),\(fromLat);\(toLon),\(toLat)"
        guard let url = URL(string: "https://router.project-osrm.org/route/v1/driving/\(path)?overview=simplified&geometries=geojson&steps=true") else { return nil }
        do {
            let obj = try await HTTP.any(url)
            guard let route = (obj["routes"] as? [[String: Any]])?.first,
                  let distance = route["distance"] as? Double,
                  let duration = route["duration"] as? Double else { return nil }

            let miles = Int((distance / 1609.34).rounded())
            var h = Int(duration / 3600)
            var m = Int(((duration.truncatingRemainder(dividingBy: 3600)) / 60 / 5).rounded()) * 5
            if m == 60 { h += 1; m = 0 }

            let legs = route["legs"] as? [[String: Any]] ?? []
            let steps = legs.flatMap { ($0["steps"] as? [[String: Any]]) ?? [] }
            var order: [String] = []
            var travelled: [String: Double] = [:]
            for step in steps {
                let ref = ((step["ref"] as? String) ?? "").split(separator: ";").first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard !ref.isEmpty else { continue }
                let label = ref.replacingOccurrences(of: " ", with: "-")
                if travelled[label] == nil { travelled[label] = 0; order.append(label) }
                travelled[label]? += (step["distance"] as? Double) ?? 0
            }
            // Roads driven more than ~10 miles; if none qualify, the four longest, kept
            // in the order they were driven so the corridor reads as a route.
            var sequence = order.filter { (travelled[$0] ?? 0) > 16093 }
            if sequence.isEmpty {
                sequence = order.sorted { (travelled[$0] ?? 0) > (travelled[$1] ?? 0) }
                    .prefix(4)
                    .sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            }
            let corridor = sequence.isEmpty ? nil : sequence.prefix(7).joined(separator: " → ")

            let geometry = (route["geometry"] as? [String: Any])?["coordinates"] as? [[Double]] ?? []
            let coords = geometry.compactMap { pair -> (lat: Double, lon: Double)? in
                pair.count == 2 ? (pair[1], pair[0]) : nil
            }

            return Route(miles: miles, drive: m > 0 ? "\(h) h \(m) m" : "\(h) h",
                         minutes: Int((duration / 60).rounded()),
                         corridor: corridor, coordinates: coords)
        } catch {
            failures.note("routing (OSRM)", error)
            return nil
        }
    }
}

/// Campsite availability from Recreation.gov.
///
/// Recreation.gov blocks most non-browser callers. When it refuses, the answer is
/// `.unknown` — the UI then says availability is not published. It never projects a
/// plausible-looking count; an earlier web version did exactly that and it was deleted.
@MainActor
struct RecreationService {
    let failures: FailureLog

    func availability(campgroundID: Int, nights: [Date]) async -> AvailabilityLevel {
        guard let firstNight = nights.first else { return .unknown }
        let monthStart = String(WPDate.iso(firstNight).prefix(8)) + "01T00:00:00.000Z"
        var c = URLComponents(string: "https://www.recreation.gov/api/camps/availability/campground/\(campgroundID)/month")!
        c.queryItems = [.init(name: "start_date", value: monthStart)]
        guard let url = c.url else { return .unknown }

        do {
            let obj = try await HTTP.any(url)
            guard let sites = obj["campsites"] as? [String: Any], !sites.isEmpty else { return .unknown }
            let keys = nights.map { WPDate.iso($0) + "T00:00:00Z" }
            var allNights = 0, someNights = 0
            for (_, raw) in sites {
                guard let site = raw as? [String: Any],
                      let availabilities = site["availabilities"] as? [String: String] else { continue }
                let states = keys.map { availabilities[$0] }
                if states.allSatisfy({ $0 == "Available" }) { allNights += 1 }
                else if states.contains(where: { $0 == "Available" }) { someNights += 1 }
            }
            if allNights > 0 { return .open(allNights) }
            if someNights > 0 { return .partial(someNights) }
            return .none
        } catch {
            // Not recorded as a failure: Recreation.gov refusing a direct call is its
            // documented behaviour, and the UI already says the data is unpublished.
            return .unknown
        }
    }
}

/// Petrol stations near the gateway, from OpenStreetMap via Overpass. Three mirrors are
/// tried because any one of them is regularly rate-limited.
@MainActor
struct OverpassService {
    let failures: FailureLog

    private static let mirrors = [
        "https://overpass-api.de",
        "https://overpass.kumi.systems",
        "https://maps.mail.ru/osm/tools/overpass",
    ]

    func fuelStations(lat: Double, lon: Double) async -> [String] {
        let query = "[out:json][timeout:10];(node[\"amenity\"=\"fuel\"][\"name\"](around:9000,\(lat),\(lon)););out tags 20;"
        for mirror in Self.mirrors {
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "\(mirror)/api/interpreter?data=\(encoded)") else { continue }
            do {
                let obj = try await HTTP.any(url)
                let elements = obj["elements"] as? [[String: Any]] ?? []
                var seen = Set<String>()
                let rows = elements.compactMap { el -> (mi: Double, text: String)? in
                    guard let tags = el["tags"] as? [String: Any],
                          let name = tags["name"] as? String, !seen.contains(name),
                          let elat = el["lat"] as? Double, let elon = el["lon"] as? Double else { return nil }
                    seen.insert(name)
                    let mi = Geo.haversine((lat, lon), (elat, elon))
                    let distance = mi < 0.95 ? String(format: "%.1f", mi) : "\(Int(mi.rounded()))"
                    return (mi, "\(name) — \(distance) mi")
                }
                .sorted { $0.mi < $1.mi }
                .prefix(4)
                .map(\.text)
                if rows.count >= 2 { return Array(rows) }
            } catch {
                continue
            }
        }
        failures.note("fuel (OpenStreetMap)", "no Overpass mirror answered")
        return []
    }
}

/// The proxy-backed sources: chargers (Open Charge Map), stays (Google Places),
/// campgrounds by radius (Recreation.gov / RIDB) and city geocoding.
@MainActor
struct ProxyServices {
    let proxy: ProxyConfig
    let failures: FailureLog

    struct Suggestion: Identifiable, Hashable {
        var name: String
        var lat: Double
        var lon: Double
        var id: String { "\(name)|\(lat)|\(lon)" }
    }

    func geocode(_ query: String) async -> [Suggestion] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 3,
              let request = proxy.request("/geocode", ["q": query]) else { return [] }
        do {
            let obj = try await HTTP.any(request)
            let rows = obj["results"] as? [[String: Any]] ?? []
            return rows.compactMap { r in
                guard let name = r["name"] as? String,
                      let lat = r["lat"] as? Double, let lon = r["lon"] as? Double else { return nil }
                return Suggestion(name: name, lat: lat, lon: lon)
            }
        } catch {
            failures.note("city lookup", error)
            return []
        }
    }

    func chargers(lat: Double, lon: Double, level: String, limit: Int, radius: Int) async -> [String] {
        guard let request = proxy.request("/chargers", [
            "lat": String(format: "%.4f", lat), "lon": String(format: "%.4f", lon),
            "level": level, "limit": String(limit), "radius": String(radius),
        ]) else { return [] }
        do {
            let obj = try await HTTP.any(request)
            guard (obj["available"] as? Bool) == true, let rows = obj["rows"] as? [[String: Any]] else { return [] }
            return rows.compactMap { $0["label"] as? String }
        } catch {
            failures.note("EV charging", error)
            return []
        }
    }

    /// Hotels near the gateway for the nights of the stay.
    func stays(lat: Double, lon: Double, checkIn: String, checkOut: String) async -> [Lodging] {
        guard let request = proxy.request("/hotels", [
            "lat": String(lat), "lon": String(lon), "checkin": checkIn, "checkout": checkOut,
        ]) else { return [] }
        do {
            let obj = try await HTTP.any(request)
            guard (obj["available"] as? Bool) == true, let rows = obj["rows"] as? [[String: Any]] else { return [] }
            return rows.compactMap { r in
                guard let name = r["name"] as? String else { return nil }
                return Lodging(
                    name: name,
                    whereText: r["sub"] as? String ?? r["address"] as? String,
                    price: r["price"] as? String ?? r["right"] as? String,
                    note: r["note"] as? String,
                    link: r["link"] as? String
                )
            }
        } catch {
            failures.note("stays (Google Places)", error)
            return []
        }
    }

    /// Campgrounds within a radius — catches the USFS/BLM/state sites a park-scoped NPS
    /// list misses, and is the only campground source a state park has.
    func campgroundsNearby(lat: Double, lon: Double, radiusMiles: Int = 50) async -> [Campground] {
        guard let request = proxy.request("/camps", [
            "lat": String(lat), "lon": String(lon), "radius": String(radiusMiles),
        ]) else { return [] }
        do {
            let obj = try await HTTP.any(request)
            guard (obj["available"] as? Bool) == true, let rows = obj["rows"] as? [[String: Any]] else { return [] }
            return rows.compactMap { r in
                guard let name = r["name"] as? String else { return nil }
                return Campground(
                    rgId: r["rgId"] as? Int,
                    name: name,
                    whereText: r["where"] as? String ?? "Near the park",
                    sites: r["sites"] as? String ?? "Sites vary",
                    price: r["price"] as? String ?? "—",
                    status: r["status"] as? String ?? "See Recreation.gov",
                    src: r["src"] as? String ?? "Recreation.gov"
                )
            }
        } catch {
            failures.note("campgrounds (Recreation.gov)", error)
            return []
        }
    }
}

/// Airports ranked from the OurAirports dataset — every US field with scheduled
/// commercial service. Distance is real; drive time is an estimate and is labelled as
/// one. There is no curated airport list, so no park can get a wrong "nearest".
enum AirportFinder {
    static func nearest(lat: Double, lon: Double, limit: Int = 12) -> [(airport: Airport, miles: Double)] {
        Datasets.shared.airports
            .map { ($0, Geo.haversine((lat, lon), ($0.lat, $0.lon)) * 1.25) }  // road ≈ straight × 1.25
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (airport: $0.0, miles: $0.1) }
    }

    /// The two rows the Overview tab shows: the closest field, plus the nearest large
    /// hub when that isn't the same airport.
    static func flyInOptions(lat: Double, lon: Double) -> [ParkAirport] {
        let ranked = nearest(lat: lat, lon: lon)
        guard let closest = ranked.first else { return [] }
        let hub = ranked.first { $0.airport.t == 1 }

        func row(_ entry: (airport: Airport, miles: Double)) -> ParkAirport {
            let hours = entry.miles / 55
            let h = Int(hours)
            let m = Int(((hours.truncatingRemainder(dividingBy: 1)) * 60 / 15).rounded()) * 15
            let drive = h > 0 ? "\(h) h\(m > 0 ? " \(m) m" : "")" : "\(max(15, m)) m"
            let note: String
            switch entry.airport.t {
            case 1: note = "Large hub — most nonstops, usually the best fares"
            case 2: note = "Regional airport — fewer flights, often dearer fares"
            default: note = "Small field — limited scheduled service"
            }
            let city = entry.airport.city.map { c in entry.airport.name.contains(c) ? "" : " (\(c))" } ?? ""
            return ParkAirport(
                code: entry.airport.code,
                name: entry.airport.name + city,
                drive: "≈ \(drive) drive · \(Int(entry.miles.rounded())) mi",
                note: note,
                best: false
            )
        }

        var rows = [row(closest)]
        if let hub, hub.airport.code != closest.airport.code { rows.append(row(hub)) }
        // The hub takes the badge only when it isn't a lot further than the closest field.
        let preferHub = hub != nil && closest.airport.t != 1 && hub!.miles < closest.miles * 1.6
        let badgeIndex = preferHub ? (rows.firstIndex { $0.code == hub!.airport.code } ?? 0) : 0
        rows[badgeIndex].best = true
        return rows
    }
}

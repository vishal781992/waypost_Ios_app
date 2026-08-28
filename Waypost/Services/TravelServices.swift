import Foundation
import MapKit

/// Real drive distance and time, plus a corridor of the numbered highways actually driven.
///
/// Two routers answer here, and which one is asked is the caller's decision rather than a
/// preference buried in here.
///
/// **Apple Maps** answers the handful of drives a reader actually looks at — the legs of a
/// trip, and the two ends of a flown one. Its estimate accounts for conditions rather than
/// only measuring the road, its geometry is the full shape rather than a simplification,
/// and — the reason this exists — its quota is the device's own. A thousand people using
/// this app do not share one allowance, which is exactly what they do on the alternative.
///
/// **OSRM's public demo server** answers the dozens of measurements taken to *rank* things
/// nobody has asked to see yet: which of twenty roadside units is the smallest detour, how
/// far the nearest ten parks are. That work arrives in bursts, and Apple throttles bursts —
/// `MKError.loadingThrottled` is a refusal this app already has to handle. It is also work
/// where an approximate answer is enough, because it only decides an order.
///
/// So the split is by shape of demand, not by which router is better: a few careful
/// measurements to Apple, many rough ones to the open server.
@MainActor
struct RoutingService {
    let failures: FailureLog

    /// Which router is asked.
    enum Preference {
        /// Apple Maps, with the open server behind it — for the drives a reader is shown.
        case apple
        /// The open server alone — for measurements taken by the dozen to sort candidates.
        case open
    }

    struct Route {
        var miles: Int
        var drive: String
        /// The same drive as a number. `drive` is rounded to five minutes and formatted
        /// for a label; anything that has to *compare* the drive — against a flight, say —
        /// needs it unparsed.
        var minutes: Int
        var corridor: String?
        /// The shape of the drive, at a couple of hundred points — for the map, and for
        /// working out what is near the road.
        var coordinates: [(lat: Double, lon: Double)]
    }

    /// One drive, measured.
    ///
    /// The default is `.open` on purpose: the callers that take measurements by the dozen
    /// are the ones that must not change, and a default they do not name cannot drift.
    func route(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double,
               preferring: Preference = .open) async -> Route? {
        guard preferring == .apple else {
            return await openRoute(fromLat: fromLat, fromLon: fromLon, toLat: toLat, toLon: toLon)
        }
        guard var route = await appleRoute(fromLat: fromLat, fromLon: fromLon,
                                           toLat: toLat, toLon: toLon) else {
            // Apple refused — throttled, or no road between the two points it will admit
            // to. The open server is the fallback rather than the leg going unmeasured.
            return await openRoute(fromLat: fromLat, fromLon: fromLon, toLat: toLat, toLon: toLon)
        }
        // Apple measured the drive but named no numbered road on it. That happens where
        // the instructions come back in a language this does not read, and on drives short
        // enough to be all local streets. The miles and the hours are Apple's either way;
        // only the corridor is worth a second request, and only when there is none.
        if route.corridor == nil {
            route.corridor = await openRoute(fromLat: fromLat, fromLon: fromLon,
                                             toLat: toLat, toLon: toLon)?.corridor
        }
        return route
    }

    // MARK: Apple Maps

    private func appleRoute(fromLat: Double, fromLon: Double,
                            toLat: Double, toLon: Double) async -> Route? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: fromLat, longitude: fromLon)))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: toLat, longitude: toLon)))
        request.transportType = .automobile
        // One route. Alternates cost the same request and nothing here reads them.
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            failures.ok("routing (Apple Maps)")
            // Apple answered, and the answer is that it knows no road between those two
            // points — a coastline, an island, a park pin dropped in backcountry. That is
            // not a failure and must not be filed as one, or the connections screen would
            // call Apple Maps down on a leg it answered perfectly well. The open server is
            // asked next in case it is less fussy.
            guard let route = response.routes.first else { return nil }

            // The roads driven, from the turn instructions. Apple gives no `ref` field, so
            // the designator is read out of the instruction itself — "Merge onto I-70 W" —
            // and the step's own distance says how far it was driven, which is the same
            // measurement the open server's corridor is built from.
            var order: [String] = []
            var travelled: [String: Double] = [:]
            for step in route.steps {
                guard let ref = Self.roadRef(step.instructions) else { continue }
                if travelled[ref] == nil { travelled[ref] = 0; order.append(ref) }
                travelled[ref]? += step.distance
            }
            var corridor = Self.corridor(order: order, travelled: travelled)
            // Nothing named in the instructions, but the route itself carries a name, and
            // where that name is a road number it is the road with most of the driving on
            // it. Only taken when it *is* a number: "Main St" is not a corridor.
            if corridor == nil, let ref = Self.roadRef(route.name) {
                corridor = ref
            }

            return Route(miles: Int((route.distance / 1609.34).rounded()),
                         drive: Self.label(seconds: route.expectedTravelTime),
                         minutes: Int((route.expectedTravelTime / 60).rounded()),
                         corridor: corridor,
                         coordinates: Self.thin(route.polyline))
        } catch {
            failures.note("routing (Apple Maps)", error)
            return nil
        }
    }

    /// The full polyline, cut down to about the density the open server returns.
    ///
    /// Apple hands back every vertex of the road — thousands of them on a day's drive.
    /// Everything downstream was written against `overview=simplified`, and one of them
    /// measures four hundred park units against every sampled point of the route, so
    /// handing it thirty times as many points would multiply that work by thirty for no
    /// better answer. Two hundred points is a comparable shape.
    private static func thin(_ line: MKPolyline) -> [(lat: Double, lon: Double)] {
        let count = line.pointCount
        guard count > 0 else { return [] }
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        line.getCoordinates(&points, range: NSRange(location: 0, length: count))

        let every = max(1, Int((Double(count) / 200).rounded(.up)))
        var out: [(lat: Double, lon: Double)] = []
        for (index, point) in points.enumerated() where index % every == 0 {
            out.append((point.latitude, point.longitude))
        }
        // The far end always, or a thinned route stops short of where it arrives.
        if let last = points.last, out.last?.lat != last.latitude || out.last?.lon != last.longitude {
            out.append((last.latitude, last.longitude))
        }
        return out
    }

    /// A US route designator inside a sentence — "I-70", "US-191", "UT-128".
    ///
    /// The hyphen is required on purpose. Without it the pattern matches a house number in
    /// a street name, and a corridor reading "N 12 → Main 9" is worse than no corridor at
    /// all. Missing a road named some other way costs nothing: the caller asks the open
    /// server for the corridor when this finds none.
    private static let roadPattern = try? NSRegularExpression(
        pattern: "\\b(?:I|[A-Z]{2})-\\d{1,3}[A-Z]?\\b")

    private static func roadRef(_ text: String) -> String? {
        guard let roadPattern = Self.roadPattern else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = roadPattern.firstMatch(in: text, range: whole),
              let found = Range(match.range, in: text) else { return nil }
        return String(text[found])
    }

    // MARK: OSRM

    private func openRoute(fromLat: Double, fromLon: Double,
                           toLat: Double, toLon: Double) async -> Route? {
        let path = "\(fromLon),\(fromLat);\(toLon),\(toLat)"
        guard let url = URL(string: "https://router.project-osrm.org/route/v1/driving/\(path)?overview=simplified&geometries=geojson&steps=true") else { return nil }
        do {
            let obj = try await HTTP.any(url)
            guard let route = (obj["routes"] as? [[String: Any]])?.first,
                  let distance = route["distance"] as? Double,
                  let duration = route["duration"] as? Double else { return nil }

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

            let geometry = (route["geometry"] as? [String: Any])?["coordinates"] as? [[Double]] ?? []
            let coords = geometry.compactMap { pair -> (lat: Double, lon: Double)? in
                pair.count == 2 ? (pair[1], pair[0]) : nil
            }

            return Route(miles: Int((distance / 1609.34).rounded()),
                         drive: Self.label(seconds: duration),
                         minutes: Int((duration / 60).rounded()),
                         corridor: Self.corridor(order: order, travelled: travelled),
                         coordinates: coords)
        } catch {
            failures.note("routing (OSRM)", error)
            return nil
        }
    }

    // MARK: Shared

    /// Seconds of driving, as a label rounded to five minutes.
    private static func label(seconds: Double) -> String {
        var h = Int(seconds / 3600)
        var m = Int(((seconds.truncatingRemainder(dividingBy: 3600)) / 60 / 5).rounded()) * 5
        if m == 60 { h += 1; m = 0 }
        return m > 0 ? "\(h) h \(m) m" : "\(h) h"
    }

    /// The corridor, from roads driven and how far each was driven.
    ///
    /// Roads driven more than ~10 miles; if none qualify, the four longest, kept in the
    /// order they were driven so the corridor reads as a route.
    private static func corridor(order: [String], travelled: [String: Double]) -> String? {
        var sequence = order.filter { (travelled[$0] ?? 0) > 16093 }
        if sequence.isEmpty {
            sequence = order.sorted { (travelled[$0] ?? 0) > (travelled[$1] ?? 0) }
                .prefix(4)
                .sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        }
        return sequence.isEmpty ? nil : sequence.prefix(7).joined(separator: " → ")
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

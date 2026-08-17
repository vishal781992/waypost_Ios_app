import Foundation

/// The drive between one park and the next, actually routed.
///
/// A trip the app composed used to show its parks in visiting order and nothing else —
/// no distance, no wheel time, no roads, and no first leg out of where the traveller
/// actually is. The parks were there; the travelling was not.
///
/// This routes it. Every leg is a real query to OSRM, which is open and needs no key, so
/// it works on a phone that has never been given the proxy. The first leg starts from the
/// origin the traveller chose for the trip; only a trip with no origin measures from the
/// device instead. Every phase says which of the two it used.
@MainActor
@Observable
final class TripRouting {
    struct Leg: Identifiable, Hashable {
        var from: String
        var to: String
        var miles: Int
        var drive: String
        /// The drive unrounded and unformatted, which is what the flight comparison needs.
        var minutes: Int = 0
        /// The numbered highways actually driven, e.g. "I-70 → US-191".
        var road: String
        /// The shape of the drive. OSRM returns it and this threw it away, so nothing
        /// downstream could ask what was *on* the route — only where it started and ended.
        var coordinates: [(lat: Double, lon: Double)] = []
        /// What flying this leg would cost against driving it — `nil` on a trip that never
        /// asked, `.drives(why)` on one that asked and was told no.
        var flight: FlightCompare.Verdict?
        var id: String { from + to }

        static func == (a: Leg, b: Leg) -> Bool { a.id == b.id && a.miles == b.miles }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }

        /// The flight, where there is one worth taking.
        var fly: FlyOption? {
            if case .flies(let option) = flight { return option }
            return nil
        }

        /// Why this leg is driven, on a trip that asked about flying it. `nil` when the
        /// trip never asked — a trip planned to drive says nothing about flights.
        var flyRefusal: String? {
            if case .drives(let why) = flight { return why }
            return nil
        }

        var curated: CuratedLeg {
            // `CuratedFly` and `FlyOption` are the same three strings under two names —
            // one is what the bundled table decodes to, the other what a leg carries.
            CuratedLeg(from: from, to: to, mi: miles, drive: drive, date: "", road: road, ev: [],
                       fly: fly.map { CuratedFly(via: $0.via, time: $0.time, note: $0.note) })
        }
    }

    /// Where the first leg actually started, so the screen can say so rather than
    /// implying every trip was measured from the phone.
    enum OriginSource: Equatable {
        /// The city the traveller picked for this trip.
        case chosen
        /// A precise fix from the device.
        case device
        /// A loose fix, so the first leg is only roughly placed.
        case approximate
    }

    enum Phase: Equatable {
        case idle
        case routing
        case routed(origin: String, source: OriginSource)
        /// OSRM did not answer. The trip still lists its parks; it just has no distances.
        case unrouted(String)
    }

    private(set) var legs: [String: [Leg]] = [:]
    private(set) var phase: [String: Phase] = [:]

    private let failures = FailureLog()
    private let location = LocationService.shared
    private var routing: RoutingService { RoutingService(failures: failures) }
    private var inFlight: Set<String> = []

    func legs(for trip: SavedTrip) -> [Leg] { legs[trip.id] ?? [] }
    func phase(for trip: SavedTrip) -> Phase { phase[trip.id] ?? .idle }

    /// Routes a trip once. Re-opening it costs nothing.
    func route(_ trip: SavedTrip, parks: [CuratedPark], origin originCity: TripOrigin?) {
        guard legs[trip.id] == nil, !inFlight.contains(trip.id), !parks.isEmpty else { return }
        inFlight.insert(trip.id)
        phase[trip.id] = .routing

        Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(trip.id) }

            // The origin the traveller chose is an instruction, not a fallback for a
            // refused permission. This asked the device first and read `originCity` only
            // when Core Location said nothing — so a trip planned from Dallas was routed
            // from wherever the phone happened to be, and the phase label reported that
            // city as though it had been chosen.
            let start: (name: String, lat: Double, lon: Double)?
            let source: OriginSource
            if let originCity {
                start = (originCity.shortName, originCity.lat, originCity.lon)
                source = .chosen

            } else if let fix = await location.currentFix() {
                start = (fix.city ?? (fix.precise ? "Where you are" : "Your area"), fix.lat, fix.lon)
                source = fix.precise ? .device : .approximate
            } else {
                start = nil
                source = .device
            }

            var built: [Leg] = []
            var previous = start.map { (name: $0.name, lat: $0.lat, lon: $0.lon) }
            // Absent on trips saved before the switch did anything, and those are drives.
            let comparesFlights = trip.flyWhenFaster ?? false

            for park in parks {
                guard let from = previous else { break }
                if let leg = await self.leg(from: from, toName: park.name, toLat: park.lat,
                                            toLon: park.lon, comparesFlights: comparesFlights) {
                    built.append(leg)
                }
                previous = (name: park.name, lat: park.lat, lon: park.lon)
            }
            // Home again, when the trip started somewhere with a name.
            if let start, let last = previous, last.name != start.name {
                if let leg = await self.leg(from: last, toName: start.name, toLat: start.lat,
                                            toLon: start.lon, comparesFlights: comparesFlights) {
                    built.append(leg)
                }
            }

            legs[trip.id] = built
            phase[trip.id] = built.isEmpty
                ? .unrouted("The routing service did not answer, so this trip has no distances yet.")
                : .routed(origin: start?.name ?? "the origin", source: source)
        }
    }

    /// The one leg the app was missing entirely: from where the traveller is standing to
    /// the first park of the trip. The seed trip already carries its own legs — Denver
    /// onwards — but none of them start from the person holding the phone.
    func routeApproach(_ trip: SavedTrip, to park: CuratedPark) {
        let key = trip.id + ":approach"
        guard legs[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        phase[key] = .routing

        Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(key) }

            guard let fix = await location.currentFix() else {
                phase[key] = .unrouted("This iPhone did not give a location, so the drive to the first park cannot be measured.")
                return
            }
            let name = fix.city ?? (fix.precise ? "Where you are" : "Your area")
            let built = await leg(from: (name, fix.lat, fix.lon),
                                  toName: park.name, toLat: park.lat, toLon: park.lon,
                                  comparesFlights: trip.flyWhenFaster ?? false)
            legs[key] = built.map { [$0] } ?? []
            phase[key] = built == nil
                ? .unrouted("The routing service did not answer, so the drive to the first park has no distance yet.")
                : .routed(origin: name, source: fix.precise ? .device : .approximate)
        }
    }

    func approach(for trip: SavedTrip) -> Leg? { legs[trip.id + ":approach"]?.first }
    func approachPhase(for trip: SavedTrip) -> Phase { phase[trip.id + ":approach"] ?? .idle }

    private func leg(from: (name: String, lat: Double, lon: Double),
                     toName: String, toLat: Double, toLon: Double,
                     comparesFlights: Bool) async -> Leg? {
        guard let route = await routing.route(fromLat: from.lat, fromLon: from.lon,
                                              toLat: toLat, toLon: toLon) else { return nil }
        return Leg(
            from: from.name,
            to: toName,
            miles: route.miles,
            drive: route.drive,
            minutes: route.minutes,
            // No corridor means OSRM returned no numbered roads, not that there are none.
            road: route.corridor ?? "Roads not named by the routing service",
            coordinates: route.coordinates,
            // Asked only of a trip that wants flights. A trip planned to drive is not
            // told which of its legs it could have flown.
            flight: comparesFlights
                ? FlightCompare.verdict(from: (from.lat, from.lon), to: (toLat, toLon),
                                        driveMinutes: route.minutes)
                : nil
        )
    }
}

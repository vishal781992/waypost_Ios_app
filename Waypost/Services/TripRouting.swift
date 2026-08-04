import Foundation

/// The drive between one park and the next, actually routed.
///
/// A trip the app composed used to show its parks in visiting order and nothing else —
/// no distance, no wheel time, no roads, and no first leg out of where the traveller
/// actually is. The parks were there; the travelling was not.
///
/// This routes it. Every leg is a real query to OSRM, which is open and needs no key, so
/// it works on a phone that has never been given the proxy. The first leg starts from
/// the device's own position when it will give one, because "how far is it from here" is
/// the question being asked; when location is refused it starts from the trip's origin
/// city instead, and says which of the two it used.
@MainActor
@Observable
final class TripRouting {
    struct Leg: Identifiable, Hashable {
        var from: String
        var to: String
        var miles: Int
        var drive: String
        /// The numbered highways actually driven, e.g. "I-70 → US-191".
        var road: String
        var id: String { from + to }

        var curated: CuratedLeg {
            CuratedLeg(from: from, to: to, mi: miles, drive: drive, date: "", road: road, ev: [], fly: nil)
        }
    }

    enum Phase: Equatable {
        case idle
        case routing
        case routed(origin: String, precise: Bool)
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
    func route(_ trip: SavedTrip, parks: [CuratedPark], originCity: CuratedCity?) {
        guard legs[trip.id] == nil, !inFlight.contains(trip.id), !parks.isEmpty else { return }
        inFlight.insert(trip.id)
        phase[trip.id] = .routing

        Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(trip.id) }

            // Where the traveller is, if the phone will say. This is the whole point of
            // the first leg, so it is worth waiting for.
            let fix = await location.currentFix()
            let start: (name: String, lat: Double, lon: Double)?
            let precise: Bool
            if let fix {
                let name = fix.city ?? (fix.precise ? "Where you are" : "Your area")
                start = (name, fix.lat, fix.lon)
                precise = fix.precise
            } else if let originCity {
                start = (originCity.shortName, originCity.lat, originCity.lon)
                precise = false
            } else {
                start = nil
                precise = false
            }

            var built: [Leg] = []
            var previous = start.map { (name: $0.name, lat: $0.lat, lon: $0.lon) }

            for park in parks {
                guard let from = previous else { break }
                if let leg = await self.leg(from: from, toName: park.name, toLat: park.lat, toLon: park.lon) {
                    built.append(leg)
                }
                previous = (name: park.name, lat: park.lat, lon: park.lon)
            }
            // Home again, when the trip started somewhere with a name.
            if let start, let last = previous, last.name != start.name {
                if let leg = await self.leg(from: last, toName: start.name, toLat: start.lat, toLon: start.lon) {
                    built.append(leg)
                }
            }

            legs[trip.id] = built
            phase[trip.id] = built.isEmpty
                ? .unrouted("The routing service did not answer, so this trip has no distances yet.")
                : .routed(origin: start?.name ?? "the origin", precise: precise)
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
                                  toName: park.name, toLat: park.lat, toLon: park.lon)
            legs[key] = built.map { [$0] } ?? []
            phase[key] = built == nil
                ? .unrouted("The routing service did not answer, so the drive to the first park has no distance yet.")
                : .routed(origin: name, precise: fix.precise)
        }
    }

    func approach(for trip: SavedTrip) -> Leg? { legs[trip.id + ":approach"]?.first }
    func approachPhase(for trip: SavedTrip) -> Phase { phase[trip.id + ":approach"] ?? .idle }

    private func leg(from: (name: String, lat: Double, lon: Double),
                     toName: String, toLat: Double, toLon: Double) async -> Leg? {
        guard let route = await routing.route(fromLat: from.lat, fromLon: from.lon,
                                              toLat: toLat, toLon: toLon) else { return nil }
        return Leg(
            from: from.name,
            to: toName,
            miles: route.miles,
            drive: route.drive,
            // No corridor means OSRM returned no numbered roads, not that there are none.
            road: route.corridor ?? "Roads not named by the routing service"
        )
    }
}

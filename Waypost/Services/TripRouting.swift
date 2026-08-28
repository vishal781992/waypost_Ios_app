import Foundation

/// The drive between one park and the next, actually routed.
///
/// A trip the app composed used to show its parks in visiting order and nothing else —
/// no distance, no wheel time, no roads, and no first leg out of where the traveller
/// actually is. The parks were there; the travelling was not.
///
/// This routes it. Every leg is a real query to Apple Maps, which needs no key and no
/// proxy, and whose allowance belongs to this phone rather than to the app — so a leg does
/// not get slower because other people are planning trips too. Apple's estimate also
/// accounts for conditions rather than only measuring the road. Where Apple declines, the
/// open routing server answers behind it, so a leg is measured either way.
///
/// The first leg starts from the origin the traveller chose for the trip; only a trip with
/// no origin measures from the device instead. Every phase says which of the two it used.
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
        /// The shape of the drive. The router returns it and this threw it away, so
        /// nothing downstream could ask what was *on* the route — only where it started
        /// and ended.
        var coordinates: [(lat: Double, lon: Double)] = []
        /// What flying this leg would cost against driving it — `nil` on a trip that never
        /// asked, `.drives(why)` on one that asked and was told no.
        var flight: FlightCompare.Verdict?
        /// The shape of a flown leg. `nil` on one that is driven, which is most of them.
        var flightPath: FlightPath?
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

        /// Where this leg ends, for a reader.
        ///
        /// A flown leg ends at the arrival airport. The drive on from there is a leg of its
        /// own now, so naming the park here would give the trip two rows that both arrive
        /// at the same place and no way to tell which was which.
        var arrivesAt: String {
            guard let path = flightPath, path.fromAirport != nil else { return to }
            return path.arrival.code
        }

        /// Where this leg actually begins, for a reader.
        ///
        /// The mirror of `arrivesAt`, and it was missing for as long as the drive it names
        /// was. A flown leg begins at the airport it takes off from; the drive to that
        /// airport is a leg of its own, so keeping the park's name here would give the trip
        /// two rows that both set out from the same place and no way to tell them apart —
        /// exactly the fault `arrivesAt` was written to stop at the other end.
        var departsFrom: String {
            guard let path = flightPath, path.toAirport != nil else { return from }
            return path.departure.code
        }

        /// The drive from the arrival airport to the park, as a leg in its own right.
        ///
        /// This is the point of the whole exercise. Salt Lake City to Yellowstone is 327
        /// miles and the better part of six hours, and it was living inside a sheet that
        /// also declared there was no roadside on a flown leg. It is a drive like any
        /// other: there is fuel and charging along it, there are monuments worth turning
        /// off for, and there is a list somebody hands to Maps at the end.
        ///
        /// So it is a `Leg` rather than a special case, and it gets all of that by being
        /// one — `LegStops` asks for stops on anything whose `fly` is nil, and this carries
        /// the arrival drive's own geometry for them to be measured along.
        /// The drive from where this leg starts to the airport it flies out of, as a leg
        /// in its own right.
        ///
        /// The counterpart to `arrivalDrive`, and its absence was a real hole: a trip
        /// announced that it flew out of Miami without ever saying how Miami was reached.
        /// `FlightPath` has measured this drive the whole time — the header's "mi by road"
        /// has been counting it, and the leg's own sheet has been printing it — so the
        /// distance was on the screen twice while the row that would explain it was
        /// nowhere. Twenty-six miles out of Biscayne; three hundred and thirty from Big
        /// Bend to El Paso, which is most of a day nobody was told about.
        var departureDrive: Leg? {
            guard let path = flightPath, let drive = path.toAirport else { return nil }
            return Leg(from: from,
                       to: path.departure.code,
                       miles: drive.miles,
                       drive: drive.drive,
                       minutes: drive.minutes,
                       road: drive.road,
                       coordinates: drive.coordinates,
                       flight: nil,
                       flightPath: nil)
        }

        var arrivalDrive: Leg? {
            guard let path = flightPath, let drive = path.fromAirport else { return nil }
            return Leg(from: path.arrival.code,
                       to: to,
                       miles: drive.miles,
                       drive: drive.drive,
                       minutes: drive.minutes,
                       road: drive.road,
                       coordinates: drive.coordinates,
                       // Nothing to compare and nothing to draw: this *is* the driving.
                       flight: nil,
                       flightPath: nil)
        }

        var curated: CuratedLeg {
            // `CuratedFly` and `FlyOption` are the same three strings under two names —
            // one is what the bundled table decodes to, the other what a leg carries.
            CuratedLeg(from: departsFrom, to: arrivesAt, mi: miles, drive: drive, date: "", road: road, ev: [],
                       fly: fly.map { CuratedFly(via: $0.via, time: $0.time, note: $0.note) })
        }
    }

    /// A flown leg, as three stretches rather than one.
    ///
    /// Flying a leg is never only a flight: it is a drive to an airport, the flight, and a
    /// longer drive from the far airport to the park. `FlightCompare` already counts all
    /// three to reach its verdict — that is what makes it a door-to-door comparison — and
    /// the map drew one road across the lot, as though the whole thing were driven.
    ///
    /// The two drives are routed here, properly, because they are not small. Salt Lake City
    /// to Yellowstone is 327 miles and the better part of six hours; a straight line laid
    /// across it would be the same lie the trip line was telling before.
    struct FlightPath {
        var departure: FlyAirport
        var arrival: FlyAirport
        /// Where the traveller sets out, and the park at the far end. Kept so a drive the
        /// router declined to answer can still be drawn as the provisional straight line
        /// the app already uses for exactly that, rather than not drawn at all.
        var origin: (lat: Double, lon: Double)
        var destination: (lat: Double, lon: Double)
        /// The two drives, as the router measured them. `nil` when it did not answer.
        var toAirport: AirportDrive?
        var fromAirport: AirportDrive?

        /// The driving a flown leg actually involves.
        ///
        /// Not `Leg.miles`, which is the drive from the origin city to the park — the one
        /// the traveller is being told *not* to take. A flown leg's real mileage is the two
        /// ends, and on Chicago to Yellowstone that is a twelve-mile run to Midway and 327
        /// miles out of Salt Lake City, not the 1,470 the notional drive would have been.
        var drivenMiles: Int { (toAirport?.miles ?? 0) + (fromAirport?.miles ?? 0) }

        /// Below this, the drive to the airport is not worth drawing.
        ///
        /// Set out from Chicago and Midway is eleven miles away — at the size these plates
        /// are drawn, a stub too short to read as anything but a nick in the line. The arc
        /// starts at the origin pin instead, which is where the traveller is anyway.
        static let shortestStub = 25.0

        var drawsOriginStub: Bool {
            Geo.haversine(origin, (departure.lat, departure.lon)) >= Self.shortestStub
        }
        var drawsArrivalStub: Bool {
            Geo.haversine((arrival.lat, arrival.lon), destination) >= Self.shortestStub
        }
    }

    /// One of the two drives a flight involves, measured rather than modelled.
    ///
    /// `FlightCompare` counts both to reach its verdict, but as straight-line miles over an
    /// assumed 55mph — good enough to decide between a flight and a drive, and not good
    /// enough to print. These are the router's own numbers for the same two stretches.
    struct AirportDrive {
        var miles: Int
        var drive: String
        var minutes: Int
        /// The numbered roads actually driven.
        var road: String
        var coordinates: [(lat: Double, lon: Double)]

        init(_ route: RoutingService.Route) {
            miles = route.miles
            drive = route.drive
            minutes = route.minutes
            road = route.corridor ?? "Roads not named by the routing service"
            coordinates = route.coordinates
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
        /// Neither router answered. The trip still lists its parks; it just has no
        /// distances.
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
                                              toLat: toLat, toLon: toLon,
                                              preferring: .apple) else { return nil }

        // Asked only of a trip that wants flights. A trip planned to drive is not told
        // which of its legs it could have flown.
        let verdict = comparesFlights
            ? FlightCompare.verdict(from: (from.lat, from.lon), to: (toLat, toLon),
                                    driveMinutes: route.minutes)
            : nil

        // Both drives at once. Sequentially this is two round trips added to a leg that
        // has already waited for one, and the card is on screen while it waits.
        var path: FlightPath?
        if case .flies(let option) = verdict, let departure = option.from, let arrival = option.to {
            async let toHub = routing.route(fromLat: from.lat, fromLon: from.lon,
                                            toLat: departure.lat, toLon: departure.lon,
                                            preferring: .apple)
            async let fromHub = routing.route(fromLat: arrival.lat, fromLon: arrival.lon,
                                              toLat: toLat, toLon: toLon,
                                              preferring: .apple)
            path = FlightPath(
                departure: departure,
                arrival: arrival,
                origin: (from.lat, from.lon),
                destination: (toLat, toLon),
                toAirport: await toHub.map(AirportDrive.init),
                fromAirport: await fromHub.map(AirportDrive.init)
            )
        }

        return Leg(
            from: from.name,
            to: toName,
            miles: route.miles,
            drive: route.drive,
            minutes: route.minutes,
            // No corridor means neither router named a numbered road, not that there
            // are none on the drive.
            road: route.corridor ?? "Roads not named by the routing service",
            coordinates: route.coordinates,
            flight: verdict,
            flightPath: path
        )
    }
}

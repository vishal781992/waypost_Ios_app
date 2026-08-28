import Foundation

/// What there is to do on each day of a trip — the driving days and the days in a park.
///
/// The Days tab said "day plans are written when the trip is composed online", which was
/// true and useless: nothing composes them and nothing ever would. Everything needed is
/// already being fetched for other screens. A driving day is a leg with a route geometry;
/// the park service publishes every unit it runs and what there is to do inside each one.
///
/// Two rules the whole thing is built on:
///
/// - A stop on a driving day is only offered once the detour has been *measured* — routed
///   through the stop and compared against the same drive without it. "Near the road" on a
///   map can be an hour up a valley with no way across.
/// - A park day's list is the park service's own, in the park service's own order. NPS
///   publishes no rating and no visit count, so nothing here claims to be ranked by
///   popularity; ordering by anything invented would be worse than ordering by nothing.
@MainActor
@Observable
final class TripDays {
    static let shared = TripDays()

    /// A stop worth making on the way, and what it costs to make it.
    struct Stop: Identifiable, Hashable {
        var name: String
        var designation: String
        var place: String
        var lat: Double
        var lon: Double
        /// Minutes added to the day's drive by going via here, measured.
        var diversion: Int
        var id: String { name + place }

        var diversionLine: String {
            if diversion <= 0 { return "on the way" }
            let hours = diversion / 60
            let rest = diversion % 60
            let time = hours == 0 ? "\(rest) min" : (rest == 0 ? "\(hours) h" : "\(hours) h \(rest)")
            return "+\(time) on the drive"
        }
    }

    /// Something to do inside a park, as the park service describes it.
    struct Doing: Identifiable, Hashable {
        var title: String
        var duration: String?
        var note: String?
        var id: String { title }
    }

    enum Kind: Hashable {
        /// A travelling day, and which leg of the trip it is. `fly` is set only where the
        /// trip asked for flights and flying this leg actually beat driving it — the day
        /// is then spent in airports rather than on the road, which is a different day.
        case travel(from: String, to: String, miles: Int, drive: String, fly: FlyOption?)
        /// A day in a park: which one, and which of its days this is.
        case park(code: String, name: String, number: Int, of: Int)
    }

    /// What the end of an arrival day is.
    ///
    /// A drive that finishes at half past two and one that finishes at half past six are
    /// not the same day, and the trip used to describe them identically. The park is named
    /// in both cases because the sentence is about that park's afternoon.
    enum Arrival: Hashable {
        /// Enough of the day is left to go in.
        case park(String)
        /// Too late for the gate: find the bed, and start in the morning.
        case settle(String)
    }

    struct Day: Identifiable, Hashable {
        var index: Int
        var date: Date?
        var kind: Kind
        var stops: [Stop] = []
        var doings: [Doing] = []
        /// Why there is nothing to do listed, when there is nothing. "Nobody answered" and
        /// "this park publishes none" are different sentences and only one of them is a
        /// statement about the park.
        var doingsNote: String?
        /// Which leg of the trip this day belongs to, on a travelling day.
        ///
        /// A leg is no longer one day, so "the nth travelling day" and "the nth leg" have
        /// stopped being the same sentence. Anything that wants a leg's day — the weather
        /// column on the route, for one — asks by leg rather than by counting.
        var leg: Int?
        /// Which day of that leg this is, and how many it takes.
        var part: Int = 1
        var parts: Int = 1
        /// When the day sets off and when it gets in. Absent on a trip whose dates do not
        /// parse: the hours are still known, the calendar is not.
        var departs: Date?
        var arrives: Date?
        /// Set on the last day of a leg that ends at a park.
        var arrival: Arrival?
        var id: Int { index }

        var dateLabel: String {
            guard let date else { return "Day \(index)" }
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }

        /// What the arrival is worth saying, where there is a time to say it with.
        var arrivalLine: String? {
            guard let arrival else { return nil }
            let time = arrives.map { $0.formatted(date: .omitted, time: .shortened) }
            switch arrival {
            case .park(let name):
                return time.map { "Arrive \($0) — enough of the day left for \(name)." }
                    ?? "Gets in with enough of the day left for \(name)."
            case .settle(let name):
                return time.map { "Arrive \($0) — too late for \(name). Find the bed; the park starts in the morning." }
                    ?? "Gets in too late for \(name). The park starts in the morning."
            }
        }
    }

    enum State: Equatable {
        case idle
        case building
        case ready([Day])
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    /// Stops worth a detour, by leg — so the leg's own sheet can offer the same list the
    /// day-by-day plan does without measuring every detour a second time.
    private(set) var legStops: [String: [Stop]] = [:]
    private var legTasks: Set<String> = []

    private let failures = FailureLog()

    private init() {}

    func state(for trip: SavedTrip) -> State { states[trip.id] ?? .idle }

    /// How far off a leg a stop may sit before it stops being "on the way".
    private static let diversionCap = 120

    /// How many candidates get their detour measured per leg. Each costs two OSRM
    /// requests, so this is the one number that decides how long a trip takes to plan.
    private static let measured = 4

    func build(_ trip: SavedTrip, parks: [CuratedPark], legs: [TripRouting.Leg]) {
        switch state(for: trip) {
        case .idle, .failed: break
        default: return
        }
        // Nothing to lay out until the roads are known: the legs carry the geometry the
        // stops are chosen from, and the day count itself comes from the parks.
        guard !parks.isEmpty, !legs.isEmpty else { return }
        states[trip.id] = .building

        Task { [weak self] in
            guard let self else { return }
            let days = await self.compose(trip, parks: parks, legs: legs)
            states[trip.id] = days.isEmpty
                ? .failed("This trip has no days to lay out yet.")
                : .ready(days)
        }
    }

    // MARK: Composing

    /// How many days `compose` is about to lay out, and which of them are driven.
    ///
    /// It mirrors the loop below exactly, and lives directly above it for that reason: it
    /// exists so the days tab can hold the rows that are coming while the build runs, and
    /// a shape that disagreed with what arrived would be worse than no shape at all.
    ///
    /// Nothing here is asked of anybody. The count falls out of the parks, the legs the
    /// router already returned and the nights the trip was saved with — all of it in hand
    /// before `build` is called. Given no legs it returns nothing, which is the honest
    /// answer while the roads are still being measured: until they land, the number of
    /// days really is unknown.
    static func plannedShape(_ trip: SavedTrip, parks: [CuratedPark],
                             legs: [TripRouting.Leg]) -> [Bool] {
        guard !parks.isEmpty, !legs.isEmpty else { return [] }
        var isTravel: [Bool] = []
        for (position, park) in parks.enumerated() {
            if position < legs.count {
                isTravel.append(contentsOf: Array(repeating: true, count: travelDays(of: legs[position])))
            }
            for _ in 0 ..< max(1, trip.days?[park.code] ?? 2) { isTravel.append(false) }
        }
        if legs.count > parks.count, let home = legs.last {
            isTravel.append(contentsOf: Array(repeating: true, count: travelDays(of: home)))
        }
        return isTravel
    }

    /// How many days one leg takes.
    ///
    /// The one number `compose` and `plannedShape` must agree on, so both ask this rather
    /// than each working it out. A leg used to be a day whatever it was; it is now however
    /// many eight-hour days its hours divide into.
    static func travelDays(of leg: TripRouting.Leg) -> Int {
        leg.fly == nil ? TripClock.days(forDriving: leg.minutes) : (flightSplits(leg) ? 2 : 1)
    }

    /// Whether the drive on from the far airport is a day of its own.
    ///
    /// A flying day absorbs a lot: airports at both ends, the flight, and the hire car.
    /// Forty minutes to Biscayne goes on the back of it. The better part of six hours from
    /// Salt Lake City to Yellowstone does not.
    ///
    /// Measured against the router's own figure for that drive where there is one, and
    /// against the flight comparison's estimate where there is not — never both, because
    /// the estimate is already counted inside the door-to-door total.
    static func flightSplits(_ leg: TripRouting.Leg) -> Bool {
        guard let fly = leg.fly, let doorToDoor = fly.doorToDoorMinutes else { return false }
        let toGate = doorToDoor - (fly.fromAirportMinutes ?? 0)
        guard toGate > 0 else { return false }
        return toGate + driveOnMinutes(leg) > Int((TripPace.standard.flyingDayHours * 60).rounded())
    }

    /// The drive from the far airport, as it is actually spent.
    static func driveOnMinutes(_ leg: TripRouting.Leg) -> Int {
        if let drive = leg.arrivalDrive { return TripClock.elapsedMinutes(driving: drive.minutes) }
        return leg.fly?.fromAirportMinutes ?? 0
    }

    private func compose(_ trip: SavedTrip, parks: [CuratedPark], legs: [TripRouting.Leg]) async -> [Day] {
        var days: [Day] = []
        var cursor = trip.startDate
        var index = 1

        func advance() {
            cursor = cursor.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
            index += 1
        }

        for (position, park) in parks.enumerated() {
            // The drive to this park. The first leg starts at the origin; the rest run
            // park to park — and each takes however many days its hours divide into.
            if position < legs.count {
                let laid = await travelling(legs[position], position: position, arrivingAt: park,
                                            from: cursor, index: index, first: days.isEmpty)
                days += laid
                for _ in laid { advance() }
            }

            let nights = max(1, trip.days?[park.code] ?? 2)
            let (doings, note) = await self.doings(for: park, count: nights * 2)
            for number in 1...nights {
                // The park's own list, split across its days rather than repeated on each:
                // two a day, in the order the park service gives them.
                let slice = Array(doings.dropFirst((number - 1) * 2).prefix(2))
                days.append(Day(index: index,
                                date: cursor,
                                kind: .park(code: park.code, name: park.name,
                                            number: number, of: nights),
                                doings: slice,
                                doingsNote: slice.isEmpty ? note : nil))
                advance()
            }
        }

        // The drive home, where the router has measured one. No park at the far end, so
        // no arrival line: nobody needs telling that they got home after four.
        if legs.count > parks.count, let home = legs.last {
            let laid = await travelling(home, position: parks.count, arrivingAt: nil,
                                        from: cursor, index: index, first: days.isEmpty)
            days += laid
            for _ in laid { advance() }
        }
        return days
    }

    /// One leg, as the days it actually takes.
    ///
    /// A driven leg is cut by `TripClock` into eight-hour days. A flown one is a day —
    /// airports, flight and hire car — unless the drive at the far end will not fit on the
    /// back of it, in which case that drive becomes a day of its own and gets everything a
    /// driven day gets, stops included.
    private func travelling(_ leg: TripRouting.Leg, position: Int, arrivingAt park: CuratedPark?,
                            from cursor: Date?, index: Int, first: Bool) async -> [Day] {
        var out: [Day] = []
        var day = cursor
        var number = index

        /// What the far end of the last day of this leg is, where it ends at a park.
        ///
        /// Nothing without a time to say it with. A trip whose dates will not parse still
        /// knows how many days its drives take; what it does not know is what hour any of
        /// them ends at, and "too late for the park" would be an invented value.
        func arrival(at instant: Date?) -> Arrival? {
            guard let park, let instant else { return nil }
            return TripClock.reachesPark(by: instant) ? .park(park.name) : .settle(park.name)
        }

        func nextDay() {
            day = day.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
            number += 1
        }

        if let fly = leg.fly {
            let splits = Self.flightSplits(leg)
            let driveOn = Self.driveOnMinutes(leg)
            let toGate = (fly.doorToDoorMinutes ?? 0) - (fly.fromAirportMinutes ?? 0)
            // Where the hire car is not a day of its own it is still part of this one.
            let spent = splits ? toGate : max(0, toGate + driveOn)
            let departs = day.map { TripClock.departure(on: $0, first: first) }
            // No clock on a flight the bundled table only describes in prose: the day is
            // still a day, and the hour it lands is not something to make up.
            let arrives = fly.doorToDoorMinutes == nil
                ? nil
                : departs.map { $0.addingTimeInterval(TimeInterval(spent * 60)) }

            out.append(Day(index: number,
                           date: day,
                           kind: .travel(from: leg.from, to: leg.to,
                                         miles: leg.miles, drive: leg.drive, fly: fly),
                           // Nothing is on the way when the way is an aeroplane, and
                           // measuring four detours nobody can take is four routing
                           // requests spent on a day that is not driven.
                           leg: position, part: 1, parts: splits ? 2 : 1,
                           departs: departs, arrives: arrives,
                           arrival: splits ? nil : arrival(at: arrives)))

            if splits, let drive = leg.arrivalDrive {
                nextDay()
                let leaves = day.map { TripClock.departure(on: $0, first: false) }
                let lands = leaves.map { $0.addingTimeInterval(TimeInterval(driveOn * 60)) }
                out.append(Day(index: number,
                               date: day,
                               kind: .travel(from: drive.from, to: drive.to,
                                             miles: drive.miles, drive: drive.drive, fly: nil),
                               stops: await stops(on: drive),
                               leg: position, part: 2, parts: 2,
                               departs: leaves, arrives: lands,
                               arrival: arrival(at: lands)))
            }
            return out
        }

        let span = TripClock.split(driving: leg.minutes, miles: leg.miles,
                                   startingOn: day, first: first)
        let perDay = Self.spread(await stops(on: leg), across: span.parts, along: leg.coordinates)
        for part in span.parts {
            out.append(Day(index: number,
                           date: day,
                           kind: .travel(from: leg.from, to: leg.to,
                                         miles: part.miles,
                                         drive: TripClock.clock(part.minutes), fly: nil),
                           stops: perDay[part.number - 1],
                           leg: position, part: part.number, parts: part.of,
                           departs: part.departs, arrives: part.arrives,
                           arrival: part.isLast ? arrival(at: part.arrives) : nil))
            nextDay()
        }
        return out
    }

    /// The leg's stops, given to the day that actually passes them.
    ///
    /// Divided by distance along the route: a place nine hundred miles into a three-day
    /// drive belongs to day two, and repeating all four of them on all three days would
    /// say the opposite. Distance rather than hours is an approximation — the days are cut
    /// by time, and an hour of interstate is not an hour of mountain road — but it is the
    /// one of the two the geometry can answer, and it is right about the day far more
    /// often than it is wrong about a boundary.
    private static func spread(_ stops: [Stop], across parts: [TripClock.DayPart],
                               along coordinates: [(lat: Double, lon: Double)]) -> [[Stop]] {
        var out = Array(repeating: [Stop](), count: max(1, parts.count))
        guard !stops.isEmpty else { return out }
        guard parts.count > 1, coordinates.count > 1 else {
            out[0] = stops
            return out
        }

        // How far along the drive each vertex of the route is.
        var run: [Double] = [0]
        run.reserveCapacity(coordinates.count)
        for point in 1 ..< coordinates.count {
            run.append(run[point - 1] + Geo.haversine(coordinates[point - 1], coordinates[point]))
        }
        guard let total = run.last, total > 0 else {
            out[0] = stops
            return out
        }

        // Where each day ends, as a fraction of the whole drive.
        let miles = parts.map { Double(max(0, $0.miles)) }
        let whole = miles.reduce(0, +)
        var bounds: [Double] = []
        var carried = 0.0
        for mile in miles {
            carried += mile
            bounds.append(whole > 0 ? carried / whole : 1)
        }

        for stop in stops {
            let nearest = (0 ..< coordinates.count).min {
                Geo.haversine(coordinates[$0], (stop.lat, stop.lon))
                    < Geo.haversine(coordinates[$1], (stop.lat, stop.lon))
            } ?? 0
            let fraction = run[nearest] / total
            let index = bounds.firstIndex { fraction <= $0 + 0.0001 } ?? (parts.count - 1)
            out[index].append(stop)
        }
        return out
    }

    /// Asks for one leg's stops on their own. Runs once per leg; the answer is kept.
    func loadStops(for leg: TripRouting.Leg) {
        guard legStops[leg.id] == nil, !legTasks.contains(leg.id) else { return }
        legTasks.insert(leg.id)
        Task { [weak self] in
            guard let self else { return }
            let found = await self.stops(on: leg)
            legStops[leg.id] = found
            legTasks.remove(leg.id)
        }
    }

    /// Whether a leg's stops are still being measured, as against having none.
    func isMeasuring(_ leg: TripRouting.Leg) -> Bool { legTasks.contains(leg.id) }

    // MARK: Stops on a driving day

    private func stops(on leg: TripRouting.Leg) async -> [Stop] {
        guard leg.coordinates.count > 1 else { return [] }
        let register = await NearbyUnits.shared.serviceUnits()
        guard !register.isEmpty else { return [] }

        // A cheap filter first: anything within forty miles of a point on the route is
        // worth measuring. Routing all four hundred units would be four hundred round
        // trips. The geometry a leg carries is thinned to a couple of hundred points, so
        // on a thousand-mile leg they are far apart — sampling every sixth rather than
        // every twelfth keeps the corridor from having holes a whole state wide.
        let samples = Self.sample(leg.coordinates, every: 6)
        let near = register.compactMap { unit -> (Park, Double)? in
            let closest = samples
                .map { Geo.haversine(($0.lat, $0.lon), (unit.lat, unit.lon)) }
                .min() ?? .greatestFiniteMagnitude
            return closest <= 40 ? (unit, closest) : nil
        }
        .sorted { $0.1 < $1.1 }
        .prefix(Self.measured)

        guard !near.isEmpty,
              let start = leg.coordinates.first, let end = leg.coordinates.last else { return [] }

        let routing = RoutingService(failures: failures)
        let direct = await routing.route(fromLat: start.lat, fromLon: start.lon,
                                         toLat: end.lat, toLon: end.lon)
        guard let direct, let baseline = Self.minutes(direct.drive) else { return [] }

        // Measured one candidate at a time, two requests each, with one retry.
        //
        // These go to OSRM's public demo server, which throttles — and the app now asks it
        // for a great deal: the trip's own legs, ten drives on every park's Nearby tab, and
        // this. Fired all at once the later ones come back empty, and an empty answer here
        // is indistinguishable from "nothing is near this road", so the section silently
        // vanished on a trip where it had just listed four places.
        var out: [Stop] = []
        for (unit, _) in near {
            guard let a = await Self.routeWithRetry(routing, from: start, to: (unit.lat, unit.lon)),
                  let b = await Self.routeWithRetry(routing, from: (unit.lat, unit.lon), to: end),
                  let one = Self.minutes(a.drive), let two = Self.minutes(b.drive) else { continue }
            let diversion = (one + two) - baseline
            // A negative or absurd answer means the router has snapped something to the
            // wrong way; a stop nobody can measure is not offered.
            guard diversion >= -5, diversion <= Self.diversionCap else { continue }
            out.append(Stop(name: unit.full.isEmpty ? unit.name : unit.full,
                            designation: unit.designation ?? "National Park Service unit",
                            place: USState.spellOut(unit.state),
                            lat: unit.lat, lon: unit.lon,
                            diversion: max(0, diversion)))
        }
        let sorted = out.sorted { $0.diversion < $1.diversion }
        legStops[leg.id] = sorted
        return sorted
    }

    /// One routing request, tried twice. A throttled server answers nil, and the second
    /// ask a moment later usually lands.
    private static func routeWithRetry(_ routing: RoutingService,
                                       from: (lat: Double, lon: Double),
                                       to: (lat: Double, lon: Double)) async -> RoutingService.Route? {
        if let first = await routing.route(fromLat: from.lat, fromLon: from.lon,
                                           toLat: to.lat, toLon: to.lon) {
            return first
        }
        try? await Task.sleep(for: .milliseconds(400))
        return await routing.route(fromLat: from.lat, fromLon: from.lon,
                                   toLat: to.lat, toLon: to.lon)
    }

    /// Every nth point of the route, so the proximity test is cheap.
    private static func sample(_ points: [(lat: Double, lon: Double)], every: Int) -> [(lat: Double, lon: Double)] {
        guard every > 1 else { return points }
        return points.enumerated().compactMap { $0.offset % every == 0 ? $0.element : nil }
    }

    // MARK: Things to do in a park

    private func doings(for park: CuratedPark, count: Int) async -> ([Doing], String?) {
        let settled = await ParkFacts.shared.settled(for: park)
        guard case .loaded(let facts) = settled else {
            switch settled {
            case .notCovered:
                return ([], "The park service does not cover \(park.name), so it publishes nothing to do here.")
            case .failed:
                return ([], "The park service did not answer when asked what there is to do at \(park.name).")
            default:
                return ([], "Still asking the park service what there is to do at \(park.name).")
            }
        }
        // Walking first: a day in a park is mostly asking "what should I walk", and the
        // park service's list mixes trails with ranger talks and bookshops. Everything
        // else keeps its place behind them rather than being thrown away.
        let all = facts.thingsToDo
        let walks = all.filter { Self.isWalk($0.title + " " + ($0.note ?? "")) }
        let rest = all.filter { !Self.isWalk($0.title + " " + ($0.note ?? "")) }
        let picked = (walks + rest).prefix(count).map {
            Doing(title: $0.title, duration: $0.duration, note: $0.detail ?? $0.note)
        }
        return (picked, picked.isEmpty
                ? "The park service answered for \(park.name) but published nothing to do."
                : nil)
    }

    private static func isWalk(_ text: String) -> Bool {
        let s = text.lowercased()
        return ["trail", "hike", "hiking", "walk", "loop", "summit", "climb"]
            .contains { s.contains($0) }
    }

    /// OSRM's own phrasing — "5 h 10 m", "48 m" — back into minutes.
    nonisolated private static func minutes(_ drive: String) -> Int? {
        let numbers = drive.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
        guard !numbers.isEmpty else { return nil }
        if drive.lowercased().contains("h") {
            return (numbers.first ?? 0) * 60 + (numbers.count > 1 ? numbers[1] : 0)
        }
        return numbers.first
    }
}

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
        var id: Int { index }

        var dateLabel: String {
            guard let date else { return "Day \(index)" }
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
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
            // park to park.
            if position < legs.count {
                let leg = legs[position]
                days.append(Day(index: index,
                                date: cursor,
                                kind: .travel(from: leg.from, to: leg.to,
                                              miles: leg.miles, drive: leg.drive, fly: leg.fly),
                                // Nothing is on the way when the way is an aeroplane, and
                                // measuring four detours nobody can take is four routing
                                // requests spent on a day that is not driven.
                                stops: leg.fly == nil ? await stops(on: leg) : []))
                advance()
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

        // The drive home, where the router has measured one.
        if legs.count > parks.count, let home = legs.last {
            days.append(Day(index: index,
                            date: cursor,
                            kind: .travel(from: home.from, to: home.to,
                                          miles: home.miles, drive: home.drive, fly: home.fly),
                            stops: home.fly == nil ? await stops(on: home) : []))
        }
        return days
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
        // trips. The geometry OSRM returns is simplified, so on a thousand-mile leg its
        // points are far apart — sampling every sixth rather than every twelfth keeps the
        // corridor from having holes a whole state wide.
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

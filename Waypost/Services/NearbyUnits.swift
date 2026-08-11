import Foundation

/// What else is worth a day from one park: the park service's other units, and the state
/// parks around it.
///
/// The Nearby tab used to read a written-down list of passport stops for the eight parks in
/// `curated.json` — one row for Yellowstone, nothing at all for the other fifty-five. The
/// park service publishes every unit it runs, with a designation and a coordinate, and the
/// state-park table has been on the phone all along; between them there is an answer for
/// any park in the country.
///
/// National parks are deliberately absent. This tab is about what is *beyond* the big park
/// somebody has already opened — monuments, historic sites, memorials, battlefields,
/// seashores — and a second national park an hour away is a trip of its own, not a
/// afternoon out of this one.
///
/// Distances are straight-line, and the ones near enough to matter are then driven: OSRM
/// answers with the real road time for the closest handful, because "70 miles" over a
/// mountain range and "70 miles" down an interstate are not the same afternoon.
@MainActor
@Observable
final class NearbyUnits {
    static let shared = NearbyUnits()

    struct Unit: Identifiable, Hashable {
        var name: String
        /// "National Monument", "State Park".
        var designation: String
        /// The state, in words.
        var place: String
        var lat: Double
        var lon: Double
        /// Straight-line, always known.
        var miles: Int
        /// Road minutes, for the ones close enough to have been asked about.
        var minutes: Int?
        var isStatePark: Bool

        var id: String { name + "|" + place }

        /// The window the tab is built around: near enough to go and be back.
        ///
        /// An hour to an hour and a half is the shape of an afternoon — far enough to be
        /// somewhere else, close enough that going does not cost the day. Only ever true
        /// of a unit whose drive has actually been measured; a straight-line guess would
        /// put a place across a lake in the window.
        var isAfternoon: Bool {
            guard let minutes else { return false }
            return (55...95).contains(minutes)
        }

        /// How far, in the terms a reader plans in.
        var distanceLine: String {
            guard let minutes else { return "\(miles) mi" }
            let hours = minutes / 60
            let rest = minutes % 60
            let drive = hours == 0 ? "\(rest) min" : (rest == 0 ? "\(hours) h" : "\(hours) h \(rest)")
            return "\(miles) mi · \(drive)"
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case ready([Unit])
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    private let failures = FailureLog()

    /// The park service's whole register, fetched once per launch and shared by every
    /// park screen. It is one request for five hundred rows; asking again for each park
    /// would be the same list five times over.
    private var register: [Park]?
    private var registerTask: Task<[Park], Never>?

    private init() {}

    func state(for park: CuratedPark) -> State { states[park.code] ?? .idle }

    /// How many of the nearest get their drive measured. Ten OSRM requests is a second or
    /// so on a good connection and the rest of the list still reads, with miles alone.
    private static let routed = 10

    func load(_ park: CuratedPark) {
        switch state(for: park) {
        case .idle, .failed: break
        default: return
        }
        states[park.code] = .loading

        Task { [weak self] in
            guard let self else { return }
            let units = await self.gather(park)
            guard !units.isEmpty else {
                states[park.code] = .failed("The park service did not answer when asked what else is near \(park.name).")
                return
            }
            states[park.code] = .ready(units)
        }
    }

    // MARK: Gathering

    private func gather(_ park: CuratedPark) async -> [Unit] {
        let here = (lat: park.lat, lon: park.lon)

        // Everything the park service runs that is not a national park.
        let serviceUnits = await self.units()
            .filter { !Self.isNationalPark($0.designation) }
            // Trails are not a place you drive to. A National Historic Trail runs two
            // thousand miles and the register gives it one coordinate somewhere along its
            // length, so it arrived here as "California, 169 miles away" — a row that is
            // neither true nor useful.
            .filter { !Self.isTrail($0.designation) }
            .filter { $0.name.lowercased() != park.name.lowercased() }
            .map { unit -> Unit in
                Unit(name: unit.full.isEmpty ? unit.name : unit.full,
                     designation: unit.designation ?? "National Park Service unit",
                     place: USState.spellOut(unit.state),
                     lat: unit.lat, lon: unit.lon,
                     miles: Int(Geo.haversine(here, (unit.lat, unit.lon)).rounded()),
                     minutes: nil,
                     isStatePark: false)
            }

        // The state parks on the phone, which need no network at all.
        let stateParks = Datasets.shared.stateParks.map { row -> Unit in
            Unit(name: row.n,
                 designation: "State Park",
                 place: USState.spellOut(row.s),
                 lat: row.lat, lon: row.lon,
                 miles: Int(Geo.haversine(here, (row.lat, row.lon)).rounded()),
                 minutes: nil,
                 isStatePark: true)
        }

        // Kept per source, not from the merged list. There are three thousand state parks
        // and four hundred other park-service units, so a single "nearest forty" is forty
        // state parks in every state with a decent system — the monuments and historic
        // sites this tab exists to surface never survived the cut.
        //
        // No distance cap either: a park in the Great Basin has nothing within fifty miles
        // and the nearest thing is still the answer. The list is ordered, so what is far is
        // simply further down.
        let nearestService = serviceUnits.sorted { $0.miles < $1.miles }.prefix(20)
        let nearestState = stateParks.sorted { $0.miles < $1.miles }.prefix(20)

        var seen = Set<String>()
        var all = (Array(nearestService) + Array(nearestState))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.miles < $1.miles }

        // The close ones, driven — the nearest few of each kind rather than the nearest few
        // overall, for the same reason the list itself is kept per source. Concurrently:
        // ten sequential round trips to OSRM is ten seconds, and the answer is wanted while
        // the reader is still on the page.
        let routing = RoutingService(failures: failures)
        let head = Array(all.filter { !$0.isStatePark }.prefix(Self.routed / 2))
            + Array(all.filter(\.isStatePark).prefix(Self.routed / 2))
        let driven: [String: Int] = await withTaskGroup(of: (String, Int?).self) { group in
            for unit in head {
                group.addTask {
                    let route = await routing.route(fromLat: here.lat, fromLon: here.lon,
                                                    toLat: unit.lat, toLon: unit.lon)
                    return (unit.id, route.map { Self.minutes(from: $0.drive) } ?? nil)
                }
            }
            var out: [String: Int] = [:]
            for await (id, minutes) in group {
                if let minutes { out[id] = minutes }
            }
            return out
        }

        for index in all.indices {
            guard let minutes = driven[all[index].id] else { continue }
            // A sanity check on the router, not on the road. A park's coordinate is often
            // the middle of its backcountry, and OSRM will snap that to whatever way is
            // nearest — sometimes a trail — and answer with twelve hours for a hundred
            // miles. Below about twelve miles an hour the number is measuring something
            // other than a drive, and the row is better off saying only how far it is.
            let impliedMPH = Double(all[index].miles) / (Double(minutes) / 60)
            guard minutes > 0, impliedMPH >= 12 else { continue }
            all[index].minutes = minutes
        }
        // Measured drives first, in time order; then everything that was only measured as
        // the crow flies. Mixing the two orders would put a 40-mile mountain crossing above
        // an 80-mile motorway run and call it nearer.
        return all.sorted { a, b in
            switch (a.minutes, b.minutes) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.miles < b.miles
            }
        }
    }

    /// The park service's units that are somewhere you can drive to — no national parks,
    /// no trails. Shared with the trip planner, which chooses stops on a driving day from
    /// the same list.
    func serviceUnits() async -> [Park] {
        await units()
            .filter { !Self.isNationalPark($0.designation) }
            .filter { !Self.isTrail($0.designation) }
    }

    /// The register, fetched once and then held.
    private func units() async -> [Park] {
        if let register { return register }
        if let registerTask { return await registerTask.value }
        let task = Task { await NPSService(proxy: ProxyConfig(), failures: failures).allParks() }
        registerTask = task
        let rows = await task.value
        register = rows
        registerTask = nil
        return rows
    }

    /// "National Park", "National Park & Preserve" — the thing this tab is *not* about.
    private static func isNationalPark(_ designation: String?) -> Bool {
        guard let designation else { return false }
        return designation.range(of: "^national park", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A trail is a line, and the register gives it a point.
    private static func isTrail(_ designation: String?) -> Bool {
        designation?.localizedCaseInsensitiveContains("trail") ?? false
    }

    /// OSRM's own phrasing — "5 h 10 m", "48 m" — back into minutes.
    nonisolated private static func minutes(from drive: String) -> Int? {
        let numbers = drive.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
        guard !numbers.isEmpty else { return nil }
        if drive.lowercased().contains("h") {
            let hours = numbers.first ?? 0
            let rest = numbers.count > 1 ? numbers[1] : 0
            return hours * 60 + rest
        }
        return numbers.first
    }
}

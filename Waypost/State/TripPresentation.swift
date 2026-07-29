import Foundation

/// The six panels on a park. Overview, Weather and Camping & stay are built; the last
/// three are named here because the tab bar is part of the design, and each says what it
/// is waiting on rather than pretending to be empty.
enum ParkTab: String, CaseIterable, Identifiable {
    case overview, weather, stay, plan, stamps, know
    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .weather: return "Weather"
        case .stay: return "Camping & stay"
        case .plan: return "Day plan"
        case .stamps: return "Passport stamps"
        case .know: return "Know before you go"
        }
    }
}

struct Stat: Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

/// One travel leg, resolved against whatever live data has landed.
struct LegPresentation: Identifiable {
    var key: String
    var kicker: String
    var dateText: String
    var fromName: String
    var toName: String
    var miles: Int
    var drive: String
    var roadBadge: String
    var roadIsLive: Bool
    var route: String
    var chargers: [String]
    var showChargers: Bool
    var chargeBadge: String
    var chargersLive: Bool
    var flyAvailable: Bool
    var flyVia: String
    var flyTime: String
    var flyNote: String
    var driveRecommended: Bool
    var flyRecommended: Bool
    var driveCaveat: String?
    var flightSearchURL: URL?
    var id: String { key }
}

enum TimelineEntry: Identifiable {
    case leg(LegPresentation)
    case park(Stop)

    var id: String {
        switch self {
        case .leg(let l): return "leg:" + l.key
        case .park(let s): return "park:" + s.park.code
        }
    }
}

extension TripStore {

    // MARK: Headline

    var routeLine: String {
        let s = schedule
        var parts = [s.city.shortName]
        parts += s.stops.map(\.park.name)
        if s.home != nil { parts.append(s.city.shortName) }
        return parts.joined(separator: " → ")
    }

    var tripDates: String {
        let s = schedule
        var text = "\(WPDate.short(start)) – \(WPDate.short(s.end))"
        if let home = s.home { text += " · home \(WPDate.short(home.date))" }
        return text
    }

    var dateSummary: String {
        guard !order.isEmpty else { return "Pick parks to see the span." }
        return "\(WPDate.short(start)) through \(WPDate.short(schedule.end)) — \(totalDays) days in the parks."
    }

    var buildHint: String {
        guard !order.isEmpty else { return "Pick at least one park above." }
        return "\(order.count) park\(order.count > 1 ? "s" : "") · \(totalDays) days · from \(originCity.name)"
    }

    var liveNote: String {
        guard proxy.isConnected else {
            return "Connect the data proxy to pull live NPS records, alerts, stays and chargers. Weather, routing and the map are live without it."
        }
        if failures.failures["NPS API"] != nil {
            return "The proxy refused this app's requests, so the NPS-backed panels are blank. It allowlists browser origins — add \(ProxyConfig.clientOrigin) to ALLOWED_ORIGINS to switch them on."
        }
        return "Live NPS records, alerts and stays enabled."
    }

    var stats: [Stat] {
        let s = schedule
        var rows = [
            Stat(label: "Parks", value: String(s.stops.count)),
            Stat(label: "Days afield", value: String(totalDays)),
            Stat(label: "Miles by road", value: totalMiles.formatted(.number)),
            Stat(label: "Preference",
                 value: (mode == .fly ? "Fly when faster" : "Drive") + (vehicle == .ev ? " · EV" : "")),
        ]
        if let cost = budget { rows.append(Stat(label: "Est. cost", value: "$\(cost.total.formatted(.number))")) }
        return rows
    }

    // MARK: Rough budget
    //
    // Planning figures, and the line under the stats says so. Entry fees come from the
    // park record, camp nights from the campground prices actually returned, fuel from
    // the road miles — nothing here is a stand-in for a price we could have looked up.

    struct Budget {
        var fees: Int
        var camping: Int
        var fuel: Int
        var total: Int
    }

    var budget: Budget? {
        let s = schedule
        guard !s.stops.isEmpty else { return nil }

        func dollars(in text: String) -> Int? {
            guard let m = try? NSRegularExpression(pattern: "\\$(\\d+)"),
                  let hit = m.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(hit.range(at: 1), in: text) else { return nil }
            return Int(text[r])
        }

        let fees = s.stops.reduce(0) { $0 + (dollars(in: $1.park.fee) ?? 30) }
        let camping = s.stops.reduce(0.0) { running, stop in
            let list = campsByPark[stop.park.code] ?? stop.park.camping
            let prices = list.compactMap { dollars(in: $0.price) }
            let nightly = prices.isEmpty ? 30.0 : Double(prices.reduce(0, +)) / Double(prices.count)
            return running + nightly * Double(stop.days)
        }
        let miles = Double(totalMiles)
        // EV: ~0.30 kWh/mi at ~$0.42/kWh on DC fast. Petrol: 24 mpg at $3.65/gal.
        let fuel = vehicle == .ev ? miles * 0.30 * 0.42 : miles / 24 * 3.65
        let total = Int(((Double(fees) + camping + fuel) / 10).rounded()) * 10
        return Budget(fees: fees, camping: Int(camping.rounded()), fuel: Int(fuel.rounded()), total: total)
    }

    var budgetLine: String? {
        guard let b = budget else { return nil }
        return "Entry fees $\(b.fees) · \(totalDays) camp nights ≈ $\(b.camping) · \(vehicle == .ev ? "charging" : "gas") ≈ $\(b.fuel) — rough planning figures, lodging not included."
    }

    // MARK: Field notes (feasibility checks)

    var warnings: [String] {
        let s = schedule
        guard !s.stops.isEmpty else { return [] }
        var notes: [String] = []

        // A shorter visiting order, if one exists worth the reshuffle.
        let picked = order.compactMap { park($0) }
        if picked.count >= 3 && picked.count <= 6 {
            func tourMiles(_ parks: [Park]) -> Double {
                var previous = (s.city.lat, s.city.lon)
                var sum = 0.0
                for p in parks {
                    sum += Geo.haversine(previous, (p.lat, p.lon)) * 1.28
                    previous = (p.lat, p.lon)
                }
                return sum + Geo.haversine(previous, (s.city.lat, s.city.lon)) * 1.28
            }
            let current = tourMiles(picked)
            var best: [Park]?
            var bestMiles = current
            for candidate in Self.permutations(picked) {
                let m = tourMiles(candidate)
                if m < bestMiles { bestMiles = m; best = candidate }
            }
            if let best, current - bestMiles > 80, bestMiles < current * 0.88 {
                let saved = Int(((current - bestMiles) / 10).rounded()) * 10
                notes.append("Visiting in the order \(best.map(\.name).joined(separator: " → ")) would trim roughly \(saved) miles of driving.")
            }
        }

        var legs: [(from: String, to: String, key: String, leg: Leg)] = s.stops.map {
            ($0.fromName, $0.park.name, $0.legKey, $0.leg)
        }
        if let home = s.home { legs.append((home.fromName, home.toName, home.legKey, home.leg)) }

        for l in legs {
            let mi = miles(forLeg: l.key, fallback: l.leg.mi)
            guard mi > 420 else { continue }
            let hasFlight = (l.leg.fly?.via).map { $0 != "—" && !$0.isEmpty } ?? false
            let tail = hasFlight ? "; the flight option earns its keep here." : "."
            notes.append("\(l.from) → \(l.to) is a long haul (~\(mi) mi) — start at dawn or split it with an overnight" + tail)
        }
        return Array(notes.prefix(3))
    }

    private static func permutations(_ parks: [Park]) -> [[Park]] {
        guard parks.count > 1 else { return [parks] }
        return parks.indices.flatMap { i -> [[Park]] in
            var rest = parks
            let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    // MARK: Timeline

    var timeline: [TimelineEntry] {
        let s = schedule
        var entries: [TimelineEntry] = []
        for (index, stop) in s.stops.enumerated() {
            entries.append(.leg(legPresentation(
                index: index, key: stop.legKey, leg: stop.leg, date: stop.start,
                from: stop.fromName, to: stop.park.name, homeward: false
            )))
            entries.append(.park(stop))
        }
        if let home = s.home {
            entries.append(.leg(legPresentation(
                index: s.stops.count, key: home.legKey, leg: home.leg, date: home.date,
                from: home.fromName, to: home.toName, homeward: true
            )))
        }
        return entries
    }

    private static let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

    static func numeral(_ index: Int) -> String {
        roman[safe: index] ?? String(index + 1)
    }

    private func legPresentation(index: Int, key: String, leg: Leg, date: Date,
                                 from: String, to: String, homeward: Bool) -> LegPresentation {
        let live = routesByLeg[key]
        let miles = live?.miles ?? leg.mi
        let drive = live?.drive ?? leg.drive
        let driveHours = Self.hours(from: drive) ?? Double(miles) / 60

        let curatedFly = (leg.fly?.via).map { $0 != "—" && !$0.isEmpty } ?? false && !leg.estimated
        // Recommend on real drive time; the Drive/Fly toggle only shifts how much faster
        // flying has to be before it wins.
        let flyRecommended: Bool = {
            guard curatedFly else { return false }
            return mode == .fly ? (driveHours >= 4 || miles >= 250) : (driveHours >= 6.5 || miles >= 450)
        }()
        let longHaul = driveHours >= 8 || miles >= 600
        // With no air option, don't endorse a marathon drive — flag it instead.
        let driveRecommended = curatedFly ? !flyRecommended : !longHaul
        let caveatTail = leg.estimated ? " (a searched park, off the main corridors)." : "."
        let caveat: String? = (!curatedFly && longHaul)
            ? "A \(Int(driveHours.rounded()))-hour drive — flying is very likely faster. No flight schedule for this route" + caveatTail
            : nil
        var searchURL: URLComponents? = caveat == nil ? nil : URLComponents(string: "https://www.google.com/travel/flights")
        searchURL?.queryItems = [URLQueryItem(name: "q", value: "flights from \(from) to \(to)")]

        let routeText: String = {
            if let corridor = live?.corridor { return corridor }
            if leg.reversed {
                let head = leg.route.split(whereSeparator: { $0 == "," || $0 == "—" }).first.map(String.init) ?? leg.route
                return "Reverse of the outbound — \(head.trimmingCharacters(in: .whitespaces)) corridor, opposite direction"
            }
            return leg.route + (leg.estimated ? " — estimated" : "")
        }()

        let liveChargers = chargersByLeg[key] ?? []
        let flyVia: String = {
            guard curatedFly, let fly = leg.fly else { return "" }
            return leg.reversed
                ? fly.via.components(separatedBy: " → ").reversed().joined(separator: " → ")
                : fly.via
        }()

        return LegPresentation(
            key: key,
            kicker: homeward ? "Leg \(Self.numeral(index)) — the way home" : "Leg \(Self.numeral(index)) — travel",
            dateText: WPDate.short(date),
            fromName: from,
            toName: to,
            miles: miles,
            drive: drive,
            roadBadge: live != nil ? "Live — OSRM" : (leg.estimated ? "Estimated" : "Curated route"),
            roadIsLive: live != nil,
            route: routeText,
            chargers: liveChargers.isEmpty ? leg.chargers : liveChargers,
            showChargers: vehicle == .ev,
            chargeBadge: liveChargers.isEmpty ? "Curated corridor stops" : "Live — near the route",
            chargersLive: !liveChargers.isEmpty,
            flyAvailable: curatedFly,
            flyVia: flyVia,
            flyTime: curatedFly ? (leg.fly?.time ?? "") : "",
            flyNote: curatedFly ? (leg.fly?.note ?? "") : "",
            driveRecommended: driveRecommended,
            flyRecommended: flyRecommended,
            driveCaveat: caveat,
            flightSearchURL: searchURL?.url
        )
    }

    /// "5 h 40" / "40 m" -> hours.
    static func hours(from text: String) -> Double? {
        if let m = try? NSRegularExpression(pattern: "(\\d+)\\s*h(?:\\s*(\\d+))?"),
           let hit = m.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let hr = Range(hit.range(at: 1), in: text), let h = Double(text[hr]) {
            if let mr = Range(hit.range(at: 2), in: text), let mins = Double(text[mr]) {
                return h + mins / 60
            }
            return h
        }
        if let m = try? NSRegularExpression(pattern: "(\\d+)\\s*m"),
           let hit = m.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(hit.range(at: 1), in: text), let mins = Double(text[r]) {
            return mins / 60
        }
        return nil
    }

    // MARK: Panel data

    /// Fly-in airports: the live ranking from the OurAirports table, or the curated rows
    /// a seed park carries.
    func flyInAirports(for park: Park) -> [ParkAirport] {
        park.airports.isEmpty
            ? AirportFinder.flyInOptions(lat: park.lat, lon: park.lon)
            : park.airports
    }

    func reservation(for park: Park) -> Reservation? {
        if let live = factsByPark[park.code]?.reservation { return live }
        // No live answer: the bundled note if this park carries one, otherwise nothing.
        // "No reservation required" is a claim, and an unanswered request cannot make it.
        return park.reservation
    }

    func parking(for park: Park) -> (lots: [Lodging], note: String, badge: String) {
        if let facts = factsByPark[park.code] {
            return (facts.parkingLots, facts.parkingNote, facts.parkingBadge)
        }
        if park.tier == .state {
            return ([], "No nationwide feed publishes parking for state parks — check the park website.", "Not published")
        }
        if npsRefused(park) {
            return ([], "NPS did not answer, so nothing is shown here. That is not the same as NPS publishing no parking detail.",
                    proxy.isConnected ? "Source did not answer" : "Needs the proxy")
        }
        return ([], park.parking, park.parking.isEmpty ? "Not published" : "Curated")
    }

    func fuel(for park: Park) -> (gas: [String], fast: [String], slow: [String], badge: String) {
        if let live = fuelByPark[park.code], !live.isEmpty {
            return (live, park.fuel.fast, park.fuel.slow, "Live — OpenStreetMap")
        }
        let curated = park.fuel
        let empty = curated.gas.isEmpty && curated.fast.isEmpty && curated.slow.isEmpty
        return (curated.gas, curated.fast, curated.slow, empty ? "Not published" : "Curated")
    }

    /// The day plan: the NPS "things to do" feed spread across the actual stay, or the
    /// curated day plans a seed park carries.
    func dayPlans(for stop: Stop) -> [DayPlan] {
        let park = stop.park
        if !park.days.isEmpty {
            var plans = Array(park.days.prefix(stop.days))
            if plans.count < stop.days, let flex = park.flex {
                plans += Array(repeating: flex, count: stop.days - plans.count)
            }
            return plans
        }
        guard let activities = thingsToDoByPark[park.code], !activities.isEmpty else { return [] }
        let perDay = max(1, activities.count / max(1, stop.days))
        return (0..<stop.days).map { day in
            let slice = activities.dropFirst(day * perDay).prefix(perDay)
            return DayPlan(
                title: "Day \(day + 1) in \(park.name)",
                items: slice.map { DayPlanItem(time: "—", text: $0) }
            )
        }
    }

    func campgroundBadge(for park: Park) -> String {
        if npsDidNotAnswer.contains(park.code) && !campsAreLive.contains(park.code) {
            return proxy.isConnected ? "Source did not answer" : "Needs the proxy"
        }
        guard let rows = campsByPark[park.code] else { return "Loading…" }
        if campsAreLive.contains(park.code) { return "Live — NPS & Recreation.gov" }
        if rows.isEmpty { return park.tier == .state ? "No nationwide feed" : "None published" }
        return "Curated — bundled record"
    }

    func stayBadge(for park: Park) -> String {
        guard let rows = staysByPark[park.code] else { return "Loading…" }
        if staysAreLive.contains(park.code) { return "Live — Google Places" }
        if rows.isEmpty { return proxy.isConnected ? "None published" : "Needs the proxy" }
        return "Curated — bundled record"
    }

    /// True only when a live source answered for this panel. The dot on the tab is a
    /// claim about provenance, so it is never lit by a bundled record.
    func isLive(_ tab: ParkTab, for stop: Stop) -> Bool {
        let code = stop.park.code
        switch tab {
        case .weather: return weatherDay(for: code, iso: WPDate.iso(stop.start)) != nil
        case .stay: return campsAreLive.contains(code) || staysAreLive.contains(code)
        case .know: return alertsAreLive.contains(code)
        case .overview: return factsByPark[code] != nil
        case .plan: return !(thingsToDoByPark[code] ?? []).isEmpty
        case .stamps: return false
        }
    }

    /// Whether the NPS panels for this park are blank because NPS refused, rather than
    /// because it publishes nothing.
    func npsRefused(_ park: Park) -> Bool {
        park.tier != .state && npsDidNotAnswer.contains(park.code)
    }
}

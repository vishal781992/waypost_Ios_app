import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - The facts

/// One candidate park, with every number already computed from real coordinates before
/// the model is ever asked anything. The model is given these and nothing else.
struct NearbyCandidate: Identifiable, Hashable {
    var park: CuratedPark
    /// Great-circle miles from where you are.
    var straightLineMiles: Double
    /// Road miles, estimated from the straight line — and labelled as an estimate.
    var roadMiles: Int
    /// Hours behind the wheel, estimated at highway speed.
    var driveHours: Double

    /// The forecast at the park for today, once one has answered.
    ///
    /// The prompt has always had a line for this and it has never once been filled: the
    /// candidates are built straight off the bundled tables, where `CuratedPark.wx` is
    /// `.unpublished`, so the branch that adds the forecast was unreachable. The model has
    /// been writing about the weather of parks it was told nothing about.
    var today: WeatherDay?
    /// Tomorrow's, fetched only when today is too far gone to set out — see
    /// `NearbyBriefing.Clock`.
    var tomorrow: WeatherDay?
    /// This month's visitor count against the park's own busiest month, 0...1. Bundled, so
    /// it costs nothing and works with no signal.
    var busyShare: Double?
    /// The month this park is busiest in, in words.
    var busiestMonth: String?
    /// Whether the traveller has already stood in this park — stamped it, saved it, or
    /// written it into a trip.
    var isVisited = false
    /// What today's roads are costing over a clear one. Only ever set on the park the
    /// brief leads with — see `NearbyBriefing.delayForLead`.
    var delay: TravelDelay?

    var id: String { park.code }

    var driveLabel: String {
        let hours = Int(driveHours)
        let minutes = Int((driveHours - Double(hours)) * 60 / 5) * 5
        if hours == 0 { return "\(max(15, minutes)) min" }
        return minutes > 0 ? "\(hours) h \(minutes) m" : "\(hours) h"
    }

    /// The line the app shows whether or not the model ever answers.
    ///
    /// The temperatures are printed only once a forecast has answered. They used to come
    /// off the bundled record — one August day, written down once for eight parks — so a
    /// card read "76°/40°" in February.
    var factLine: String {
        // Apple's time where it was asked for, the app's estimate otherwise. The two are
        // not the same claim, and `delayLine` is what says which one this is.
        let measured = "\(roadMiles) mi · \(delay?.driveLabel ?? driveLabel)"
        // This used to read `park.wx`, which on a candidate built from the bundled tables
        // is always `.unpublished` — so the temperatures never once printed. It is the
        // fetched forecast now, and a park whose forecast did not answer still shows none.
        guard let today else { return measured }
        return "\(measured) · \(today.hi)°/\(today.lo)°"
    }

    /// The roads, where they were asked about. Nil on every park but the recommended one.
    var delayLine: String? { delay?.line }

    /// Exactly what the model is told about this park. Nothing here is invented and
    /// nothing here is written down: the distance is measured, the forecast is fetched.
    ///
    /// The fee, the opening hours, the reservation rule and the current alert used to be
    /// passed in from `curated.json`. Every one of them is the kind of fact that changes
    /// without the app being rebuilt, and handing a stale one to a model that then writes
    /// it into a confident sentence is the worst version of getting it wrong. The park
    /// service answers for all of them on the park's own screen.
    var promptFacts: String {
        var lines = [
            "\(park.name) (\(park.full))",
            "  region: \(park.region), state: \(park.state), gateway town: \(park.gw)",
            "  distance: \(roadMiles) road miles, about \(driveLabel) of driving",
            "  what it is: \(park.tag)",
        ]
        // Weather and crowds reach the model as words, never as figures.
        //
        // It is forbidden to write a number and the guard drops any sentence carrying a
        // digit, so handing it "high 84F" gives it something it cannot use and might leak.
        // A band it can actually write with — "hot", "at its busiest" — is both safer and
        // the thing a person wanted said out loud.
        if let today { lines.append(Self.weatherLine("today", today)) }
        if let tomorrow { lines.append(Self.weatherLine("tomorrow", tomorrow)) }
        if let crowds = crowdLabel {
            lines.append("  crowds: \(crowds)")
        }
        if let delay {
            lines.append("  roads: \(delay.band)")
        }
        if isVisited {
            lines.append("  the traveller has already been to this one")
        }
        return lines.joined(separator: "\n")
    }

    /// How busy this month is for this park, in words rather than a share.
    var crowdLabel: String? {
        guard let busyShare else { return nil }
        let peak = busiestMonth.map { " — its busiest is \($0)" } ?? ""
        switch busyShare {
        case 0.85...:    return "this is about the busiest month of its year"
        case 0.60..<0.85: return "busy, though short of its peak\(peak)"
        case 0.35..<0.60: return "middling for this park\(peak)"
        default:          return "one of its quieter months\(peak)"
        }
    }

    /// One weather line, in words. Nil when the forecast did not answer — which is not
    /// the same as "mild", and gets nothing said about it.
    static func weatherLine(_ when: String, _ day: WeatherDay) -> String {
        let band = warmth(day)
        if let sky = sky(day) {
            return "  " + when + " at the park: " + band + ", " + sky
        }
        return "  " + when + " at the park: " + band
    }

    /// A temperature in words. There is no band for "unknown" — a park with no forecast
    /// has no `WeatherDay` at all, and gets no line rather than a hedged one.
    static func warmth(_ day: WeatherDay) -> String {
        switch day.hi {
        case 95...:      return "very hot"
        case 82..<95:    return "hot"
        case 68..<82:    return "warm"
        case 52..<68:    return "mild"
        case 36..<52:    return "cold"
        default:         return "freezing"
        }
    }

    /// What the sky is doing, when a source said. Digits are stripped: `shortForecast`
    /// carries things like "20 percent chance", and a number reaching the model is a
    /// number that can reach the screen.
    static func sky(_ day: WeatherDay) -> String? {
        guard let text = day.shortForecast?.lowercased(),
              text.rangeOfCharacter(from: .decimalDigits) == nil,
              !text.isEmpty else { return nil }
        return text
    }
}

/// What the drive costs today, as against the same road on a quiet night.
///
/// Apple predicts travel time for the hour you say you are leaving, so the difference
/// between "leaving now" and "leaving at three tomorrow morning" is the traffic rather
/// than the route. No single request returns both, which is why this holds two.
///
/// It is a prediction, not a measurement, and the wording says so wherever it is printed.
struct TravelDelay: Hashable {
    /// Apple's estimate for setting out now.
    var nowSeconds: TimeInterval
    /// The same road at an hour with nothing on it.
    var clearSeconds: TimeInterval
    var checkedAt: Date

    var minutesLost: Int { max(0, Int(((nowSeconds - clearSeconds) / 60).rounded())) }

    /// Below this the difference is inside the noise of a prediction, and saying anything
    /// about it would be dressing up a rounding error as advice.
    var isWorthSaying: Bool { minutesLost >= 15 }

    /// Apple's drive time for leaving now, which is a better number than the app's own
    /// estimate from straight-line miles at a flat speed.
    var driveLabel: String {
        let hours = Int(nowSeconds) / 3600
        let minutes = (Int(nowSeconds) % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) m" : "\(minutes) m"
    }

    /// For the screen. The app prints the figure; the model never does.
    var line: String {
        isWorthSaying
            ? "\(driveLabel) leaving now — about \(minutesLost) min more than a clear road"
            : "\(driveLabel) leaving now, roads about as they usually are"
    }

    /// For the model, in words, because it may not write a figure.
    var band: String {
        switch minutesLost {
        case 45...: return "the roads are badly against them today — the drive is much longer than usual"
        case 25..<45: return "traffic is adding a fair bit to the drive today"
        case 15..<25: return "traffic is adding a little to the drive today"
        default: return "the roads are running about as they usually do"
        }
    }
}

// MARK: - The brief

/// What the model returns. Each entry is checked against the candidate list before it is
/// shown, so a park the model invented cannot reach the screen.
struct NearbyBrief: Hashable {
    var headline: String
    var notes: [(park: String, why: String)]

    static func == (lhs: NearbyBrief, rhs: NearbyBrief) -> Bool {
        lhs.headline == rhs.headline && lhs.notes.map(\.park) == rhs.notes.map(\.park)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(headline)
        hasher.combine(notes.map(\.park))
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedParkNote {
    @Guide(description: "The park's name, copied exactly from the list you were given.")
    var park: String

    @Guide(description: "One sentence on what visiting it is like right now, using only the facts given. No distances, temperatures, fees or hours other than the ones supplied.")
    var why: String
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedBrief {
    @Guide(description: "One sentence naming which park is the better use of today and why, in the voice of a field guide. No superlatives you cannot support from the facts.")
    var headline: String

    @Guide(description: "One note per park, in the order the parks were listed.", .count(1...4))
    var notes: [GeneratedParkNote]
}
#endif

// MARK: - The service

/// Writes the "near you" brief on the phone itself, with Apple's on-device model.
///
/// Two rules shape this:
///
///  * **The model gets no facts of its own.** Distances are measured from coordinates
///    here; conditions, fees and alerts come from the field library. The prompt says so,
///    and every park it names is matched back against the candidate list before it is
///    shown — a park the model invents is dropped rather than displayed.
///  * **The list works without it.** The ranked parks and their numbers render whether
///    the model answers, refuses, or is missing from the device entirely. The prose is an
///    addition to the facts, never a replacement for them.
///
/// Nothing leaves the phone: there is no network call in this file.
@MainActor
@Observable
final class NearbyBriefing {

    enum State {
        case idle
        case locating
        case thinking
        case ready(NearbyBrief)
        /// The model cannot run here — the reason is shown, and the facts still are.
        case unavailable(String)
        case failed(String)
    }

    /// What the clock says about setting out, worked out once per run.
    ///
    /// The prompt used to open with the words "It is August." — written down, in the
    /// source, all year round. A brief about what to do *today* was being composed by a
    /// model that had been told the wrong month for eleven months of every year, and had
    /// no idea whether it was breakfast or dusk.
    struct Clock {
        var now: Date
        /// "Tuesday morning", "Saturday afternoon" — what the traveller would say.
        var phrase: String
        var month: String
        /// True when setting out now would land at the gate with the day gone.
        var tooLateToday: Bool
        /// The hour arriving at the lead park would put on the clock, if they left now.
        var arrivalHour: Int
    }

    private(set) var state: State = .idle
    private(set) var candidates: [NearbyCandidate] = []
    private(set) var placeName: String?
    private(set) var clock: Clock?
    /// The park the brief should lead with, and why it is not simply the nearest.
    ///
    /// Nil when the nearest is the answer, which is the usual case. Set when the nearest
    /// has already been visited — the brief then leads with the next one and says so,
    /// because silently reordering a list the traveller can count is worse than not
    /// reordering it.
    private(set) var leadSwapReason: String?

    private let location = LocationService.shared
    private let library = CuratedLibrary.shared

    /// Whether the device can write a brief at all. Checked before anything is offered,
    /// so the button never promises something this iPhone cannot do.
    var modelAvailability: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This iPhone does not run Apple Intelligence, so the brief is the ranked list alone."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings and Waypost can write this brief on the phone."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading its model. The ranked list is ready now."
            case .unavailable(let other):
                return "Apple Intelligence is unavailable on this iPhone (\(other))."
            }
        }
        return "The on-device model needs iOS 26."
        #else
        return "This build was made without the on-device model."
        #endif
    }

    // MARK: Running it

    /// - Parameter visited: the parks the traveller has already been to, by code. Used to
    ///   move a park they have stood in off the top of the brief — and to say so.
    func run(visited: Set<String> = []) async {
        state = .locating
        candidates = []
        clock = nil
        leadSwapReason = nil

        guard let fix = await location.currentFix() else {
            state = .failed("Location is off, so there is nothing to measure from. Turn it on in Settings and try again.")
            return
        }
        placeName = fix.city.map { city in fix.region.map { "\(city), \($0)" } ?? city }

        var ranked = rank(from: fix.lat, lon: fix.lon)
        guard !ranked.isEmpty else {
            state = .failed("No national or state park is within 120 miles of here. Search Explore for somewhere further afield.")
            return
        }

        for index in ranked.indices {
            ranked[index].isVisited = visited.contains(ranked[index].park.code)
            if let profile = Visitation.profile(for: ranked[index].park) {
                let month = Calendar.current.component(.month, from: Date()) - 1
                ranked[index].busyShare = profile.share(month)
                ranked[index].busiestMonth = Visitation.monthName(profile.peakIndex)
            }
        }

        // Which one to lead with. The order stays measured — the list is nearest first and
        // the reader can count the miles — but a park somebody has already stood in is a
        // poor answer to "where should I go today", so the brief leads with the next one
        // along and names the swap. Silently reordering a ranked list is the one thing
        // worse than not reordering it.
        if let first = ranked.first, first.isVisited,
           let next = ranked.first(where: { !$0.isVisited }) {
            leadSwapReason = "You have already been to \(first.park.name), so this leads with \(next.park.name) instead."
        }

        let lead = ranked.first(where: { !$0.isVisited }) ?? ranked[0]
        let reading = readClock(leadDriveHours: lead.driveHours)
        clock = reading

        state = .thinking
        var enriched = await withWeather(ranked, wantsTomorrow: reading.tooLateToday)

        // Traffic, for the one park being recommended, and only when the brief is about
        // today. A leaving-now estimate says nothing about tomorrow morning — the same
        // rule the leg sheet already follows — and asking for every candidate would be
        // eight route requests to answer a question about one of them.
        if !reading.tooLateToday,
           let index = enriched.firstIndex(where: { $0.park.code == lead.park.code }) {
            enriched[index].delay = await Self.delayForLead(
                from: (fix.lat, fix.lon),
                to: (enriched[index].park.lat, enriched[index].park.lon)
            )
        }
        candidates = enriched

        if let reason = modelAvailability {
            state = .unavailable(reason)
            return
        }
        await generate()
    }

    /// What the drive to the recommended park is costing today.
    ///
    /// Two predictions of the same road: one for setting out now, one for three tomorrow
    /// morning, which is as clear as a road gets. The difference is the traffic. Either
    /// request failing gives up rather than guessing — a park with no answer here simply
    /// keeps the app's own estimate and says nothing about the roads.
    private static func delayForLead(from: (lat: Double, lon: Double),
                                     to: (lat: Double, lon: Double)) async -> TravelDelay? {
        var quiet = Calendar.current.dateComponents(
            [.year, .month, .day], from: Date().addingTimeInterval(86_400))
        quiet.hour = 3
        guard let clearHour = Calendar.current.date(from: quiet) else { return nil }

        guard let leavingNow = await LegStops.traffic(from: from, to: to),
              let clearRoad = await LegStops.traffic(from: from, to: to, departing: clearHour)
        else { return nil }

        return TravelDelay(nowSeconds: leavingNow.seconds,
                           clearSeconds: clearRoad.seconds,
                           checkedAt: leavingNow.checkedAt)
    }

    /// Today's forecast for each park, and tomorrow's when today is already spent.
    ///
    /// Concurrently, and never fatally: a park whose forecast does not answer keeps its
    /// distance and its crowds and simply has nothing said about its weather, which is the
    /// same rule the rest of the app follows. Tomorrow is fetched only when it is going to
    /// be used — in the morning that halves the requests for a line nobody would read.
    private func withWeather(_ ranked: [NearbyCandidate], wantsTomorrow: Bool) async -> [NearbyCandidate] {
        let failures = FailureLog()
        let weather = WeatherService(failures: failures)
        let today = WPDate.iso(Date())
        let tomorrow = WPDate.iso(Date().addingTimeInterval(86_400))

        return await withTaskGroup(of: (Int, WeatherDay?, WeatherDay?).self) { group in
            for (index, candidate) in ranked.enumerated() {
                group.addTask { @MainActor in
                    let now = await weather.forecast(lat: candidate.park.lat,
                                                     lon: candidate.park.lon, iso: today)
                    var next: WeatherDay?
                    if wantsTomorrow {
                        next = await weather.forecast(lat: candidate.park.lat,
                                                      lon: candidate.park.lon, iso: tomorrow)
                    }
                    return (index, now, next)
                }
            }
            var out = ranked
            for await (index, now, next) in group {
                out[index].today = now
                out[index].tomorrow = next
            }
            return out
        }
    }

    /// Past this hour at the gate, the day is spent — the visitor centre is closing and
    /// what is left is the drive home in the dark. Setting out is tomorrow's job.
    private static let dayIsSpentAfter = 16

    /// Reads the clock against the drive the traveller would actually make.
    private func readClock(leadDriveHours: Double) -> Clock {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let arrival = hour + Int(leadDriveHours.rounded())

        let part: String
        switch hour {
        case ..<12: part = "morning"
        case 12..<17: part = "afternoon"
        default: part = "evening"
        }

        return Clock(
            now: now,
            phrase: "\(now.formatted(.dateTime.weekday(.wide))) \(part)",
            month: now.formatted(.dateTime.month(.wide)),
            // Evening is always too late, whatever the drive: nobody sets out for a park
            // after dark. Otherwise it depends on when they would actually arrive.
            tooLateToday: hour >= 17 || arrival >= Self.dayIsSpentAfter,
            arrivalHour: arrival
        )
    }

    /// How far a park can be and still count as "near you". A day's drive is more than
    /// this; a morning's is about this.
    private static let radiusMiles: Double = 120

    /// The parks actually within reach, nearest first — not a fixed shelf.
    ///
    /// This ranked `library.orderedParks`, the eight the app ships with, with no distance
    /// limit at all — so it showed the same eight from anywhere in the country, four of
    /// them however far away. Now it measures every national park in the country and keeps
    /// those inside the radius; and only when none is within reach does it fall back to the
    /// state parks, because a national park is the better recommendation where there is one.
    private func rank(from lat: Double, lon: Double) -> [NearbyCandidate] {
        func candidate(_ park: CuratedPark, _ miles: Double) -> NearbyCandidate {
            let road = Int((miles * 1.24 / 5).rounded()) * 5
            return NearbyCandidate(park: park, straightLineMiles: miles,
                                   roadMiles: road, driveHours: Double(road) / 57)
        }

        let national = NationalParks.all
            .map { ($0, Geo.haversine((lat, lon), ($0.lat, $0.lon))) }
            .filter { $0.1 <= Self.radiusMiles }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map { candidate(CuratedPark(bundled: $0.0), $0.1) }
        if !national.isEmpty { return national }

        // No national park within reach: the nearest state parks instead.
        return Datasets.shared.stateParks
            .map { ($0, Geo.haversine((lat, lon), ($0.lat, $0.lon))) }
            .filter { $0.1 <= Self.radiusMiles }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map { candidate(CuratedPark(stateRow: $0.0), $0.1) }
    }

    private func generate() async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            state = .unavailable("The on-device model needs iOS 26.")
            return
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: prompt(),
                generating: GeneratedBrief.self,
                options: GenerationOptions(temperature: 0.6)
            )
            state = .ready(validate(response.content))
        } catch {
            state = .failed("The on-device model did not finish: \(error.localizedDescription). The ranked list stands on its own.")
        }
        #else
        state = .unavailable("This build was made without the on-device model.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static var instructions: Instructions {
        Instructions {
            """
            You are the field desk of ParkHop, a national-park trip planner. You write \
            short, plain, unhurried briefs for someone deciding where to drive today.

            Rules you must not break:
            - NEVER WRITE A NUMBER. No distances, no temperatures, no prices, no times, no \
              hours, no digits of any kind, and no numbers spelled as words. The figures \
              are printed beside your words by the app; your job is the reading of them, \
              not the repeating.
            - Never compare two parks by how far or how hot they are. The app has already \
              ranked them; if you say which is nearer you will get it wrong.
            - Use ONLY the facts given. Never invent a park, trail, road, closure or rule.
            - Name parks exactly as they are written in the facts.
            - No exclamation marks and no marketing language — no "breathtaking", no \
              "must-see". Write the way a ranger answers a question at the desk.
            - Say plainly when a park needs a reservation or carries a warning. That is \
              the useful part.
            - If you are told the day is already too far gone to set out, say so and say \
              the word "tomorrow". Do not pretend the afternoon is a morning.
            - If you are told the traveller has already been somewhere, and the brief \
              leads with a different park because of it, say that out loud. Never quietly \
              drop a park they can see on the list.
            - Weather, crowds and roads are given to you as words, not figures. Use the \
              words. Where a park has no forecast, say nothing about its weather rather \
              than guessing at it.
            - Where you are told the roads are against them today, say so — it is the \
              difference between setting out now and setting out after lunch, and it is \
              the kind of thing a ranger would mention.
            """
        }
    }

    @available(iOS 26.0, *)
    private func prompt() -> String {
        let place = placeName.map { "The traveller is near \($0)." } ?? "The traveller's town is not known."
        let facts = candidates.map(\.promptFacts).joined(separator: "\n\n")
        let nearest = candidates.first?.park.name ?? ""
        let lead = candidates.first(where: { !$0.isVisited }) ?? candidates.first

        var when = "It is not known what time it is."
        if let clock {
            when = "It is \(clock.phrase), in \(clock.month)."
            if clock.tooLateToday {
                when += " Setting out now would reach the gate with the day already gone, "
                    + "so this brief is about GOING TOMORROW. Say so, and use tomorrow's "
                    + "weather rather than today's."
            } else {
                when += " There is enough of the day left to set out now."
            }
        }

        var swap = ""
        if let leadSwapReason, let lead {
            swap = "\n\n\(leadSwapReason) Lead the headline with \(lead.park.name) and say "
                + "plainly that the nearer one is somewhere they have already been. Still "
                + "write a note for every park on the list, including that one."
        }

        return """
        \(place) \(when)

        These are the parks within reach, ALREADY RANKED nearest first, with everything \
        Waypost knows about them:

        \(facts)

        \(nearest) is the closest.\(swap)

        Write the headline about whichever park is the better use of \
        \(clock?.tooLateToday == true ? "tomorrow" : "today"), and one note per park in \
        the order given. Remember: no numbers, and no claims about which is nearer or \
        hotter — those are printed for you.
        """
    }

    /// The guard, and the reason this feature is safe to ship.
    ///
    /// Asked to compare two parks whose real distances it had been given, the model
    /// wrote that the farther one was "175 miles closer" and that a park with timed
    /// entry "does not require a permit". Both were confident, both were wrong, and in
    /// an app whose one rule is never to show an invented value, that is fatal.
    ///
    /// So the model is forbidden to write numbers, and anything numeric it writes anyway
    /// is dropped here rather than shown. A note naming a park that is not on the
    /// shortlist is dropped too, and the order is forced back to the measured ranking.
    @available(iOS 26.0, *)
    private func validate(_ generated: GeneratedBrief) -> NearbyBrief {
        var notes: [(park: String, why: String)] = []
        for (rank, candidate) in candidates.enumerated() {
            guard let match = generated.notes.first(where: {
                $0.park.localizedCaseInsensitiveContains(candidate.park.name)
                    || candidate.park.full.localizedCaseInsensitiveContains($0.park)
            }) else { continue }
            guard Self.isFactuallyInert(match.why),
                  Self.agreesWithRanking(match.why, rank: rank) else { continue }
            notes.append((candidate.park.name, match.why))
        }

        let headline = Self.isFactuallyInert(generated.headline) && mentionsAShortlistedPark(generated.headline)
            ? generated.headline
            : fallbackHeadline
        return NearbyBrief(headline: headline, notes: notes)
    }

    /// True when a sentence makes no *quantified* claim. Digits are the tell: "175 miles
    /// closer" is the failure mode, and no sentence the model is asked for needs a
    /// number in it.
    private static func isFactuallyInert(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .decimalDigits) == nil
    }

    /// Unquantified comparisons are allowed — "the closest of the four" is useful and
    /// the app told the model the order. What is not allowed is a comparison that
    /// contradicts that order, so each note is checked against the rank it belongs to.
    private static func agreesWithRanking(_ text: String, rank: Int) -> Bool {
        let lower = text.lowercased()
        let claimsNearest = ["closest", "nearest", "shortest drive", "closer than"]
            .contains { lower.contains($0) }
        let claimsFurthest = ["farthest", "furthest", "farther", "further", "longest drive"]
            .contains { lower.contains($0) }

        if rank == 0 && claimsFurthest { return false }
        if rank > 0 && claimsNearest { return false }
        return true
    }

    private func mentionsAShortlistedPark(_ text: String) -> Bool {
        candidates.contains { text.localizedCaseInsensitiveContains($0.park.name) }
    }

    /// Written by the app, from the measured ranking, when the model's headline fails
    /// the check. It says only what the arithmetic supports.
    private var fallbackHeadline: String {
        guard let nearest = candidates.first else { return "Nothing within reach today." }
        let lead = candidates.first(where: { !$0.isVisited }) ?? nearest
        if leadSwapReason != nil {
            return "\(nearest.park.name) you have already seen — \(lead.park.name) is the next shortest drive."
        }
        if clock?.tooLateToday == true {
            return "\(lead.park.name) is the shortest drive from here, and today is too far gone to start it."
        }
        return "\(lead.park.name) is the shortest drive from here."
    }
    #endif
}

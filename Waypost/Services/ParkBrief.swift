import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "AI Overview": what to know before planning a trip to one park, written on the phone.
///
/// Same two rules as the nearby briefing. The model gets no facts of its own — the fee, the
/// reservation requirement and the forecast are gathered here from NPS, Apple Maps and the
/// weather services, and the exact figures are printed by the app beside the prose, never by
/// the model. And the facts stand without it: where Apple Intelligence cannot run, the same
/// four points are composed from the fields plainly, so every device gets the substance.
///
/// It answers four things: reservations, fees, how busy to expect it, and the one attraction
/// worth the drive.
@MainActor
@Observable
final class ParkBrief {
    static let shared = ParkBrief()

    /// The measured facts, gathered before a word is written. These are the truth; the brief
    /// is a reading of them.
    struct Facts: Hashable {
        var parkName: String
        var designation: String
        /// "Free", "$30 · Entrance - Private Vehicle", or nil when not known.
        var fee: String?
        /// The timed-entry / reservation line from NPS, or nil where there is none.
        var reservation: String?
        /// What the app can say about crowds: a real signal, not a guess.
        var busyness: String
        /// Candidate attractions — NPS things to do, and the park's own tagline.
        var attractions: [String]
        /// A word, not a number: "warm", "cold", "mild", or "" when unknown.
        var weatherWord: String
        var monthName: String
    }

    /// The four sentences, ready to render, however they were produced.
    struct Brief: Hashable {
        var reservations: String
        var fees: String
        var busyness: String
        var highlight: String
        /// True when a language model wrote it; false when composed from the facts.
        var byModel: Bool
    }

    enum State: Equatable {
        case idle
        case gathering
        case ready(Brief)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    private init() {}

    func state(for park: CuratedPark) -> State { states[park.code] ?? .idle }

    /// Whether the device can write prose at all. The facts render either way.
    var modelAvailability: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return nil }
            return "This iPhone does not run Apple Intelligence, so the overview is composed from the facts rather than written."
        }
        return "The on-device model needs iOS 26; the overview is composed from the facts."
        #else
        return "This build has no on-device model; the overview is composed from the facts."
        #endif
    }

    func load(_ park: CuratedPark, date: Date?) {
        switch state(for: park) {
        case .idle, .failed: break
        default: return
        }
        states[park.code] = .gathering

        Task { [weak self] in
            guard let self else { return }
            let facts = await Self.gather(park, date: date)
            let brief = await Self.write(facts)
            states[park.code] = .ready(brief)
        }
    }

    // MARK: Gathering the facts

    private static func gather(_ park: CuratedPark, date: Date?) async -> Facts {
        let when = date ?? Date()
        let month = when.formatted(.dateTime.month(.wide))

        // NPS: fee and reservation, if they have arrived. The overview does not block on
        // them — it reads whatever is loaded and says so where a piece is missing.
        var fee: String?
        var reservation: String?
        var things: [String] = []
        if case .loaded(let f) = ParkFacts.shared.state(for: park) {
            fee = f.fee
            reservation = f.reservation
            things = f.thingsToDo.prefix(6).map(\.title)
        }

        // Weather as a word. The number is the weather panel's job; this only needs the
        // shape of the day to say whether to start early or pack a layer.
        let forecast = await WeatherService(failures: FailureLog())
            .forecast(lat: park.lat, lon: park.lon, iso: WPDate.iso(when))
        let weatherWord = forecast.map { day -> String in
            switch day.hi {
            case 85...: return "hot"
            case 70..<85: return "warm"
            case 50..<70: return "mild"
            default: return "cold"
            }
        } ?? ""

        // Busyness, inferred honestly. A park that runs timed entry is managing crowds;
        // the warm months are its peak. Anything softer than that, this does not claim.
        let peak = ["May", "June", "July", "August", "September"].contains(month)
        let busyness: String
        if reservation != nil {
            busyness = peak
                ? "Busy — it runs timed entry, and \(month) is peak season."
                : "It runs timed entry in the busy months; \(month) is quieter."
        } else if peak {
            busyness = "\(month) is the busy season for most parks; arrive early."
        } else {
            busyness = "\(month) is outside the peak months, so expect it quieter."
        }

        // The tagline names the marquee draw ("Tundra above the treeline…"); the NPS
        // things-to-do are the actionable list. Tagline first, so the composed fallback —
        // which has no judgement — leads with the real headline rather than whichever
        // activity NPS happened to list first.
        var attractions: [String] = []
        if !park.tag.isEmpty { attractions.append(park.tag) }
        attractions += things

        return Facts(
            parkName: park.name,
            designation: park.designationLabel,
            fee: fee,
            reservation: reservation,
            busyness: busyness,
            attractions: attractions,
            weatherWord: weatherWord,
            monthName: month
        )
    }

    // MARK: Writing it

    private static func write(_ facts: Facts) async -> Brief {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            if let brief = await model(facts) { return brief }
        }
        #endif
        return compose(facts)
    }

    /// The composed fallback: the same four points, in plain sentences, from the fields.
    /// Every device gets this; only the prose of the model is missing.
    private static func compose(_ facts: Facts) -> Brief {
        let reservations = facts.reservation.map { Self.sentence($0) }
            ?? "No timed-entry reservation is listed for \(facts.parkName)."
        // No amount here — the exact figure is the chip beside this line, so repeating it
        // reads as a stutter.
        let fees: String
        switch facts.fee {
        case "Free": fees = "Entry is free."
        case .some: fees = "There is an entrance fee to enter."
        case nil: fees = "The entrance fee is not published; check with the park."
        }
        let highlight = facts.attractions.first.map {
            let phrase = $0.first!.isUppercase && $0.contains(" ") ? $0 : $0.lowercased()
            return "The big draw is \(phrase.hasPrefix("The ") ? String(phrase.dropFirst(4)) : phrase)."
        } ?? "\(facts.parkName) is a \(facts.designation.lowercased())."
        return Brief(reservations: reservations, fees: fees,
                     busyness: facts.busyness, highlight: highlight, byModel: false)
    }

    private static func sentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasSuffix(".") ? t : t + "."
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func model(_ facts: Facts) async -> Brief? {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt(facts),
                generating: GeneratedBrief.self,
                options: GenerationOptions(temperature: 0.5)
            )
            let c = response.content
            // Numbers are the app's to print, not the model's. If it slipped one in, the
            // composed version — which uses the real figures — stands in for that line.
            let composed = compose(facts)
            return Brief(
                reservations: Self.hasDigit(c.reservations) ? composed.reservations : sentence(c.reservations),
                fees: Self.hasDigit(c.fees) ? composed.fees : sentence(c.fees),
                busyness: sentence(c.busyness),
                highlight: sentence(c.highlight),
                byModel: true
            )
        } catch {
            return nil
        }
    }

    private static func hasDigit(_ s: String) -> Bool { s.contains(where: \.isNumber) }

    @available(iOS 26.0, *)
    private static var instructions: Instructions {
        Instructions {
            """
            You are the field desk of ParkHop, a national-park trip planner. You write a \
            short, plain overview for someone deciding whether to plan a trip to one park.

            Rules you must not break:
            - NEVER WRITE A NUMBER. No prices, temperatures, dates, times or hours, and no \
              numbers spelled as words. The figures are printed beside your words by the \
              app; your job is the reading of them.
            - Use ONLY the facts given. Never invent a trail, a rule, a fee or a closure.
            - Name the park exactly as written.
            - No exclamation marks and no marketing words — no "breathtaking", no "must-see". \
              Write the way a ranger answers a question at the desk.
            - One sentence per field. Say plainly whether a reservation is needed and whether \
              entry is free, because that is the useful part.
            """
        }
    }

    @available(iOS 26.0, *)
    private static func prompt(_ facts: Facts) -> String {
        let feeFact = facts.fee.map { "Entry: \($0)." } ?? "Entry fee: not published."
        let resFact = facts.reservation.map { "Reservation: \($0)" } ?? "Reservation: none listed."
        let weather = facts.weatherWord.isEmpty ? "" : "The day is \(facts.weatherWord). "
        let attractions = facts.attractions.isEmpty
            ? "No specific attractions were listed."
            : "Things to do here: " + facts.attractions.prefix(6).joined(separator: "; ") + "."
        return """
        Write the AI overview for \(facts.parkName), a \(facts.designation). It is \
        \(facts.monthName). \(weather)Here is everything ParkHop knows:

        \(feeFact)
        \(resFact)
        Busyness (already worked out for you, restate in your own words): \(facts.busyness)
        \(attractions)

        Write four short sentences, one for each field:
        - reservations: whether a timed-entry reservation is needed.
        - fees: whether entry is free or paid (no amount — it is printed for you).
        - busyness: how busy to expect it and when to arrive.
        - highlight: the single biggest attraction worth the drive, chosen from the things \
          to do above.
        Remember: not one number, anywhere.
        """
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedBrief {
    @Guide(description: "One sentence: whether a timed-entry reservation is needed. No numbers.")
    var reservations: String
    @Guide(description: "One sentence: whether entry is free or paid. Never state an amount.")
    var fees: String
    @Guide(description: "One sentence: how busy to expect the park and when to arrive. No numbers.")
    var busyness: String
    @Guide(description: "One sentence naming the single biggest attraction, chosen from the things to do given.")
    var highlight: String
}
#endif

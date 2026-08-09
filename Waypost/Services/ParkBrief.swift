import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "AI Overview": what to know before planning a trip to one park, written on the phone.
///
/// Same two rules as the nearby briefing. The model gets no facts of its own — the alerts,
/// the reservation requirement and the park service's description are gathered here from
/// NPS, and the exact figures are printed by the app beside the prose, never by the model.
/// And the facts stand without it: where Apple Intelligence cannot run, the same points are
/// composed from the fields plainly, so every device gets the substance.
///
/// It answers three things: what the park is warning about, whether a reservation is needed,
/// and why the place was set aside.
///
/// It used to answer fees and busyness too. The fee is printed at the top of the same screen
/// and the hours beside it, so the overview was restating what the reader had just passed;
/// and busyness was inferred from nothing better than the month, which made it true of every
/// park in the country in August and therefore worth nothing about this one.
@MainActor
@Observable
final class ParkBrief {
    static let shared = ParkBrief()

    /// The measured facts, gathered before a word is written. These are the truth; the brief
    /// is a reading of them.
    struct Facts: Hashable {
        var parkName: String
        var designation: String
        /// The timed-entry / reservation line from NPS, or nil where there is none.
        var reservation: String?
        /// What the park is posting right now — closures, fire, road work.
        var alerts: [CuratedAlert]
        /// True when the park service refused the alerts request, which is a different
        /// answer from a park that has none posted, and must never be reported as one.
        var alertsUnavailable: Bool
        /// The park service's own description of the place, and the topics it files the
        /// park under. The raw material for "why it matters" — long and written for a web
        /// page, which is why the model's job is to cut it to a sentence.
        var blurb: String?
        var topics: [String]
    }

    /// The three sentences, ready to render, however they were produced.
    struct Brief: Hashable {
        var reservations: String
        /// What the park is warning about, in one line — the alerts are listed in full on
        /// the Overview tab, so this is the glance that says whether to go and read them.
        var warnings: String
        /// Why this place was set aside — a reading of the park service's own description.
        ///
        /// This replaced a "worth the drive" line that named the biggest attraction from
        /// the things-to-do list. That list is ordered by whatever NPS put first, not by
        /// importance, so the line tended to nominate a visitor centre or a ranger talk as
        /// the reason to drive a day to get somewhere.
        var significance: String
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
        // NPS, if it has arrived. The overview does not block on it — it reads whatever is
        // loaded and says so where a piece is missing.
        //
        // Nothing here is fetched: dropping the fee and busyness lines took the forecast
        // request with them, because nothing left in the brief reads the weather.
        var reservation: String?
        var blurb: String?
        var topics: [String] = []
        var alerts: [CuratedAlert] = []
        var alertsUnavailable = false
        if case .loaded(let f) = ParkFacts.shared.state(for: park) {
            reservation = f.reservation
            blurb = f.blurb
            topics = Array(f.topics.prefix(6))
            // Same precedence the park screen uses: what the park is posting now, ahead of
            // the bundled alerts, which are editorial rather than current.
            alerts = f.alerts.isEmpty ? park.alerts : f.alerts
            alertsUnavailable = f.unavailable.contains("alerts") && alerts.isEmpty
        } else {
            alerts = park.alerts
        }

        return Facts(
            parkName: park.name,
            designation: park.designationLabel,
            reservation: reservation,
            alerts: alerts,
            alertsUnavailable: alertsUnavailable,
            blurb: blurb,
            topics: topics
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

    /// The composed fallback: the same points, in plain sentences, from the fields.
    /// Every device gets this; only the prose of the model is missing.
    private static func compose(_ facts: Facts) -> Brief {
        let reservations = facts.reservation.map { Self.sentence($0) }
            ?? "No timed-entry reservation is listed for \(facts.parkName)."
        // Without a model, the park service's own opening sentence is the honest answer —
        // it is already a description of what the place is, just written at web length.
        let significance = Self.firstSentence(facts.blurb)
            ?? topicSentence(facts)
            ?? "\(facts.parkName) is a \(facts.designation.lowercased())."
        return Brief(reservations: reservations, warnings: warnings(facts),
                     significance: significance, byModel: false)
    }

    /// The alerts in one line, written by the app rather than the model.
    ///
    /// This one is composed even when a model is available, and deliberately: a closure or
    /// a flash-flood notice is the one thing on this screen where a paraphrase that reads
    /// nicely but drops a word is worse than no sentence at all. The count sends the reader
    /// to the full list on the Overview tab, and the most serious alert is named in the
    /// park's own words.
    private static func warnings(_ facts: Facts) -> String {
        guard !facts.alerts.isEmpty else {
            // "Nobody answered" and "there is nothing" are not the same sentence, and the
            // difference matters most for exactly this field.
            return facts.alertsUnavailable
                ? "The park service did not answer when asked for alerts — check the park's own page before you travel."
                : "No alerts are posted for \(facts.parkName) right now."
        }

        let worst = facts.alerts.min { rank($0.cat) < rank($1.cat) } ?? facts.alerts[0]
        let headline = sentence(worst.title)
        guard facts.alerts.count > 1 else { return headline }

        // What the rest of them *are*, not merely how many. "Five more alerts are posted"
        // reads the same whether they are five closures or five car-park notices, and the
        // reader has to open the list to find out which.
        var rest = facts.alerts
        if let lead = rest.firstIndex(where: { $0.title == worst.title && $0.cat == worst.cat }) {
            rest.remove(at: lead)
        }
        // Spelled out in steps: as one chain of grouping, mapping and sorting it was past
        // what the type-checker would take in a single expression.
        let groups: [String: [CuratedAlert]] = Dictionary(grouping: rest) {
            normalisedCategory($0.cat)
        }
        let categories: [String] = groups.keys.sorted { rank($0) < rank($1) }
        let counted: [String] = categories.map { category in
            let count = groups[category]?.count ?? 0
            return "\(count) \(noun(for: category, plural: count != 1))"
        }

        return "\(headline) Also posted: \(list(counted))."
    }

    /// The park service's categories, as the app spells them.
    private static func normalisedCategory(_ raw: String) -> String {
        switch raw.lowercased() {
        case "danger": return "danger"
        case "park closure", "closure": return "park closure"
        case "caution": return "caution"
        case "information", "": return "information"
        default: return raw.lowercased()
        }
    }

    private static func noun(for category: String, plural: Bool) -> String {
        let singular: String
        switch category {
        case "danger": return plural ? "dangers" : "danger"
        case "park closure": singular = "closure"
        case "caution": singular = "caution"
        case "information": singular = "information notice"
        default: singular = "\(category) notice"
        }
        return plural ? singular + "s" : singular
    }

    /// "2 closures, 3 cautions and 1 information notice".
    private static func list(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        }
    }

    /// Which alert to lead with. The park service's own categories, most serious first.
    private static func rank(_ category: String) -> Int {
        switch category.lowercased() {
        case "danger": return 0
        case "park closure": return 1
        case "caution": return 2
        default: return 3
        }
    }

    /// "Set aside for its volcanoes and wilderness." — the fallback's fallback, for a park
    /// whose description did not arrive but whose topics did.
    private static func topicSentence(_ facts: Facts) -> String? {
        let topics = facts.topics.prefix(3).map { $0.lowercased() }
        guard !topics.isEmpty else { return nil }
        let list: String
        switch topics.count {
        case 1: list = topics[0]
        case 2: list = "\(topics[0]) and \(topics[1])"
        default: list = "\(topics[0]), \(topics[1]) and \(topics[2])"
        }
        return "\(facts.parkName) is known for its \(list)."
    }

    /// The first sentence of a paragraph, kept whole. Cuts on ". " rather than any full
    /// stop so "St. Mary" and "Mt. Rainier" do not end the sentence early.
    private static func firstSentence(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        guard let end = text.range(of: ". ") else { return sentence(text) }
        return sentence(String(text[text.startIndex..<end.lowerBound]))
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
                // Always the app's own sentence, never the model's. See `warnings`.
                warnings: composed.warnings,
                // A significance the model wrote without being given the park service's
                // description would be its own recollection of the park — the one thing
                // this whole class exists to avoid. No description, no model sentence.
                significance: facts.blurb == nil ? composed.significance : sentence(c.significance),
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
            - One sentence per field. Say plainly whether a reservation is needed, because \
              that is the useful part.
            - For significance, you are SHORTENING the park service's own description, not \
              recalling anything you know about the park. If the description does not say \
              why the place matters, say only what it does say. Nothing from memory.
            """
        }
    }

    @available(iOS 26.0, *)
    private static func prompt(_ facts: Facts) -> String {
        let resFact = facts.reservation.map { "Reservation: \($0)" } ?? "Reservation: none listed."
        let blurb = facts.blurb.map { "The park service describes it this way: \($0)" }
            ?? "The park service's description did not load."
        let topics = facts.topics.isEmpty
            ? ""
            : "The park service files it under: " + facts.topics.joined(separator: ", ") + ".\n"
        return """
        Write the AI overview for \(facts.parkName), a \(facts.designation). Here is \
        everything ParkHop knows:

        \(resFact)
        \(topics)\(blurb)

        Write two short sentences, one for each field:
        - reservations: whether a timed-entry reservation is needed.
        - significance: why this place was set aside — what makes it worth protecting. \
          Cut the park service's description down to ONE short sentence a traveller can \
          read at a glance. Use only what that description and those topics say.
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
    @Guide(description: "One short sentence on why this place was set aside, shortened from the park service's own description. Nothing from memory. No numbers.")
    var significance: String
}
#endif

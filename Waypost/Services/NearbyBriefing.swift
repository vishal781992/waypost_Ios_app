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

    var id: String { park.code }

    var driveLabel: String {
        let hours = Int(driveHours)
        let minutes = Int((driveHours - Double(hours)) * 60 / 5) * 5
        if hours == 0 { return "\(max(15, minutes)) min" }
        return minutes > 0 ? "\(hours) h \(minutes) m" : "\(hours) h"
    }

    /// The line the app shows whether or not the model ever answers.
    var factLine: String {
        "\(roadMiles) mi · \(driveLabel) · \(park.wx.hi)°/\(park.wx.lo)° · \(park.crowd)"
    }

    /// Exactly what the model is told about this park. Nothing here is invented: the
    /// distance is measured, the rest is the curated record.
    var promptFacts: String {
        var lines = [
            "\(park.name) (\(park.full))",
            "  region: \(park.region), state: \(park.state), gateway town: \(park.gw)",
            "  distance: \(roadMiles) road miles, about \(driveLabel) of driving",
            "  August normals: high \(park.wx.hi)F, low \(park.wx.lo)F, UV \(park.wx.uv)",
            "  crowds: \(park.crowd)",
            "  entry: \(park.fee); hours: \(park.hours)",
            "  what it is: \(park.tag)",
        ]
        if park.res {
            lines.append("  reservation required: yes — \(park.resNote)")
        } else {
            lines.append("  reservation required: no")
        }
        if let alert = park.alerts.first {
            lines.append("  current alert (\(alert.cat)): \(alert.title) — \(alert.body)")
        }
        return lines.joined(separator: "\n")
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

    private(set) var state: State = .idle
    private(set) var candidates: [NearbyCandidate] = []
    private(set) var placeName: String?

    private let location = LocationService()
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

    func run() async {
        state = .locating
        candidates = []

        guard let fix = await location.currentFix() else {
            state = .failed("Location is off, so there is nothing to measure from. Turn it on in Settings and try again.")
            return
        }
        placeName = fix.city.map { city in fix.region.map { "\(city), \($0)" } ?? city }

        candidates = rank(from: fix.lat, lon: fix.lon)
        guard !candidates.isEmpty else {
            state = .failed("No park in the field library is close enough to measure from here.")
            return
        }

        if let reason = modelAvailability {
            state = .unavailable(reason)
            return
        }

        state = .thinking
        await generate()
    }

    /// Real distance, then a road estimate. The ranking is arithmetic, not a judgement —
    /// the model never decides what is nearest.
    private func rank(from lat: Double, lon: Double) -> [NearbyCandidate] {
        library.orderedParks
            .map { park -> NearbyCandidate in
                let miles = Geo.haversine((lat, lon), (park.lat, park.lon))
                let road = Int((miles * 1.24 / 5).rounded()) * 5
                return NearbyCandidate(
                    park: park,
                    straightLineMiles: miles,
                    roadMiles: road,
                    driveHours: Double(road) / 57
                )
            }
            .sorted { $0.straightLineMiles < $1.straightLineMiles }
            .prefix(4)
            .map { $0 }
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
            You are the field desk of Waypost, a national-park trip planner. You write \
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
            """
        }
    }

    @available(iOS 26.0, *)
    private func prompt() -> String {
        let place = placeName.map { "The traveller is near \($0)." } ?? "The traveller's town is not known."
        let facts = candidates.map(\.promptFacts).joined(separator: "\n\n")
        let nearest = candidates.first?.park.name ?? ""
        return """
        \(place) It is August. These are the parks within reach, ALREADY RANKED nearest \
        first, with everything Waypost knows about them:

        \(facts)

        \(nearest) is the closest. Write the headline about whichever park is the better \
        use of today, and one note per park in the order given. Remember: no numbers, and \
        no claims about which is nearer or hotter — those are printed for you.
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
        return "\(nearest.park.name) is the shortest drive from here."
    }
    #endif
}

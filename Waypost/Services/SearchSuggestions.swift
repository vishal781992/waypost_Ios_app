import Foundation

/// What you might mean, offered while you are still typing it.
///
/// The search itself is slow by nature — a state-wide query to a public Overpass server
/// takes the better part of a minute — so typing two letters and waiting is a poor deal.
/// Suggestions close that gap: they are cheap, they arrive immediately, and picking one
/// runs the real search with a term the sources will actually recognise ("TX" rather than
/// "te", "Moab" rather than "moa").
///
/// Three kinds, in the order they are useful:
///
///  * **States**, matched locally against the fifty names. No network, no wait.
///  * **Parks**, from the eight the app ships with and from whatever the last search
///    found — again local.
///  * **Places**, from Nominatim, which knows every town in the country. This is the one
///    that costs a request, so it is debounced and asked once the typing settles.
@MainActor
@Observable
final class SearchSuggestions {
    struct Suggestion: Identifiable, Hashable {
        enum Kind: String {
            case state, place, park

            var glyph: String {
                switch self {
                case .state: return "map"
                case .place: return "building.2"
                case .park: return "tree"
                }
            }
        }

        var kind: Kind
        var title: String
        var subtitle: String
        /// What to actually search for when this is picked.
        var query: String
        var id: String { kind.rawValue + title + subtitle }
    }

    private(set) var items: [Suggestion] = []

    private var inFlight: Task<Void, Never>?
    private let failures = FailureLog()
    private let library = CuratedLibrary.shared

    /// Extra names to match against — the parks the live directory has already found.
    var knownParks: [(name: String, state: String)] = []

    func clear() {
        inFlight?.cancel()
        items = []
    }

    func update(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        inFlight?.cancel()

        guard text.count >= 2 else {
            items = []
            return
        }

        // The local matches are on screen before the keystroke has finished registering.
        items = local(text)

        inFlight = Task { [weak self] in
            guard let self else { return }
            // Nominatim asks callers not to hammer it, and a person types faster than
            // any search is worth running.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            let places = await self.places(text)
            guard !Task.isCancelled else { return }
            // Local matches stay on top: a state is almost always what "te" means.
            let existing = Set(self.items.map { $0.title.lowercased() })
            self.items += places.filter { !existing.contains($0.title.lowercased()) }
        }
    }

    // MARK: The instant half

    private func local(_ text: String) -> [Suggestion] {
        let needle = text.lowercased()
        var out: [Suggestion] = []

        // States, by name and by postal code — "te" finds Tennessee and Texas, "tx" finds
        // Texas outright.
        for (name, code) in USStates.map where name.hasPrefix(needle) || code.lowercased() == needle {
            out.append(Suggestion(kind: .state,
                                  title: name.capitalized(with: .current),
                                  subtitle: "State · \(code)",
                                  query: name))
        }
        out.sort { $0.title < $1.title }

        // Every national park in the country, from the list on the phone.
        var parks: [Suggestion] = NationalParks.search(text)
            .prefix(5)
            .map { Suggestion(kind: .park, title: $0.name,
                              subtitle: "\($0.designation) · \($0.state)",
                              query: $0.full) }

        // Then the eight the app carries in full, and the last search's finds.
        parks += library.orderedParks
            .filter { $0.name.lowercased().contains(needle) || $0.full.lowercased().contains(needle) }
            .map { Suggestion(kind: .park, title: $0.name,
                              subtitle: "\($0.designationLabel) · \($0.state)",
                              query: $0.name) }
            .filter { suggestion in !parks.contains { $0.title == suggestion.title } }

        let already = Set(parks.map { $0.title.lowercased() })
        parks += knownParks
            .filter { $0.name.lowercased().contains(needle) && !already.contains($0.name.lowercased()) }
            .prefix(4)
            .map { Suggestion(kind: .park, title: $0.name,
                              subtitle: $0.state.isEmpty ? "Park" : "Park · \($0.state)",
                              query: $0.name) }

        return Array((out.prefix(4) + parks.prefix(4)))
    }

    // MARK: The half that costs a request

    private func places(_ text: String) async -> [Suggestion] {
        var c = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        c.queryItems = [
            .init(name: "q", value: text),
            .init(name: "format", value: "jsonv2"),
            .init(name: "addressdetails", value: "1"),
            .init(name: "countrycodes", value: "us"),
            .init(name: "limit", value: "8"),
        ]
        guard let url = c.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(ParkDirectory.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let rows = try await NominatimGate.shared.run { try await HTTP.array(request) }
            return rows.compactMap { row -> Suggestion? in
                let type = row["type"] as? String ?? ""
                let category = (row["category"] as? String) ?? (row["class"] as? String) ?? ""
                guard let name = row["name"] as? String, !name.isEmpty else { return nil }

                let address = row["address"] as? [String: Any] ?? [:]
                let state = (address["state"] as? String).map { USStates.abbreviation(for: $0) ?? $0 } ?? ""

                // Towns and cities are suggestions; a park found here is one too. A
                // county boundary or a road is not what anybody meant.
                let isPlace = category == "place"
                    && ["city", "town", "village", "hamlet", "municipality"].contains(type)
                let isPark = type == "national_park" || type == "protected_area" || type == "nature_reserve"
                guard isPlace || isPark else { return nil }

                return Suggestion(
                    kind: isPark ? .park : .place,
                    title: name,
                    subtitle: isPark
                        ? (state.isEmpty ? "Park" : "Park · \(state)")
                        : (state.isEmpty ? type.capitalized : "\(type.capitalized) · \(state)"),
                    query: state.isEmpty ? name : "\(name), \(state)"
                )
            }
            .prefix(6)
            .map { $0 }
        } catch {
            failures.note("suggestions (Nominatim)", error)
            return []
        }
    }
}

import MapKit

/// The city a trip sets out from, found by typing it.
///
/// The builder used to offer six cities out of `curated.json` — Denver, Salt Lake City,
/// Las Vegas, Phoenix, Seattle, Chicago — so a trip could not be planned from anywhere
/// else at all. Choosing one of the six was the only way to answer "from where".
///
/// `MKLocalSearchCompleter` rather than Nominatim: completions keep up with the typing,
/// need no key on a free developer account, and do not queue behind the park search at
/// `NominatimGate`'s one-request-per-1.1-seconds door.
@MainActor
@Observable
final class CitySearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Match: Identifiable, Hashable {
        /// "Dallas"
        var city: String
        /// "TX"
        var state: String
        var id: String { city + "|" + state }

        /// Held so the pick can be resolved to coordinates; a completion carries none.
        fileprivate var completion: MKLocalSearchCompletion?

        static func == (a: Match, b: Match) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var matches: [Match] = []
    private(set) var isResolving = false

    private let completer = MKLocalSearchCompleter()
    private static let codes = Set(USStates.map.values)

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Centred on the country rather than on the phone, so two letters typed in Denver
        // do not rank Colorado above everywhere else.
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 60)
        )
    }

    /// Two characters is the point at which a completion is worth showing.
    func update(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            clear()
            return
        }
        completer.queryFragment = text
    }

    func clear() {
        matches = []
        completer.cancel()
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.absorb(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.matches = [] }
    }

    private func absorb(_ results: [MKLocalSearchCompletion]) {
        var seen = Set<String>()
        matches = results
            .compactMap(Self.match(from:))
            .filter { seen.insert($0.id).inserted }
            .prefix(6)
            .map { $0 }
    }

    /// "Dallas, TX, United States" is a city. "2100 Ross Ave, Dallas, TX" is a street in
    /// one, which is not what "setting out from" is asking for.
    private static func match(from completion: MKLocalSearchCompletion) -> Match? {
        let whole = completion.subtitle.isEmpty
            ? completion.title
            : "\(completion.title), \(completion.subtitle)"
        let parts = whole.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }

        let city = parts[0]
        // A street address leads with a number; a city does not.
        guard !city.isEmpty, city.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
        // The state has to be the next component. Anything else is a narrower address
        // inside a city rather than the city itself.
        let state = parts[1].uppercased()
        guard codes.contains(state) else { return nil }

        return Match(city: city, state: state, completion: completion)
    }

    /// Turns a chosen suggestion into somewhere a route can start from.
    func resolve(_ match: Match) async -> TripOrigin? {
        guard let completion = match.completion else { return nil }
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              !response.mapItems.isEmpty else { return nil }

        // The response's bounding region centres on the place that was searched for, which
        // for a city is the city. `mapItems.first?.placemark` would say the same thing but
        // is deprecated from iOS 26, and this needs no availability branch to stay correct
        // on the iOS 17 deployment target.
        let centre = response.boundingRegion.center
        return TripOrigin(name: "\(match.city), \(match.state)",
                          lat: centre.latitude,
                          lon: centre.longitude)
    }
}

import MapKit

/// Where the typed words are on the map, so a list of parks can be ranked around them.
///
/// The state-park table matches a park's own name and its state, and nothing else — so
/// "Austin" found nothing at all, though there are a dozen state parks within an hour of
/// it. Sorting the table needs one thing the table does not hold: where Austin is. Apple's
/// geocoder answers that in a few hundred milliseconds, off one request, with no key and
/// no rate limit — and the 470 rows are already on the phone, so the ranking that follows
/// is instant and works with no network beyond this lookup.
///
/// A state is deliberately *not* anchored. "Texas" geocodes to the middle of Texas, which
/// would rank the table by distance from a point in the scrub near Brady; the state
/// filter already answers that query properly.
@MainActor
@Observable
final class PlaceAnchor {
    struct Anchor: Equatable {
        /// What to call it in the heading — the name the geocoder gave back, which is
        /// tidier than what was typed ("Austin" for "austin tx").
        var label: String
        var lat: Double
        var lon: Double
        /// The state the place is in, in words, where the geocoder said. A city is asked
        /// "what is near you"; a city with no park near it is asked "then what is the
        /// nearest one in your own state", and that question needs the state named.
        var state: String?
    }

    private(set) var anchor: Anchor?
    private(set) var isLocating = false

    private var inFlight: Task<Void, Never>?
    private var lastQuery = ""

    /// The country, so a two-letter fragment is not resolved against the region the phone
    /// happens to be in.
    private static let unitedStates = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 60)
    )

    func clear() {
        inFlight?.cancel()
        lastQuery = ""
        anchor = nil
        isLocating = false
    }

    /// Two characters, then a pause: the same threshold the suggestions use, so the guess
    /// under the field and the list under it are talking about the same moment.
    func locate(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, USStates.abbreviation(for: text) == nil else {
            clear()
            return
        }
        guard text.lowercased() != lastQuery else { return }
        lastQuery = text.lowercased()

        inFlight?.cancel()
        isLocating = true
        inFlight = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = Self.unitedStates
            let response = try? await MKLocalSearch(request: request).start()

            guard !Task.isCancelled else { return }
            isLocating = false
            guard let response, !response.mapItems.isEmpty else {
                anchor = nil
                return
            }
            // The bounding region centres on the place that was searched for, and holds
            // for a city as well as for a single address.
            let centre = response.boundingRegion.center
            let first = response.mapItems.first
            // `administrativeArea` is the two-letter code on a US result; spelled out here
            // so the sentence it lands in reads "the nearest in Colorado".
            let area = first?.placemark.administrativeArea
            anchor = Anchor(label: first?.name ?? text,
                            lat: centre.latitude,
                            lon: centre.longitude,
                            state: area.map(USState.spellOut))
        }
    }
}

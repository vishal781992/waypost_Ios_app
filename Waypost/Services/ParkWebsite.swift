import Foundation
import MapKit

/// The park's own website, for the parks no register covers.
///
/// The National Park Service covers its own units and nothing else, so a state park's fee
/// and hours read "Not published" and the screen has nowhere to send anybody. Three
/// thousand state parks each publish their own page, and Apple Maps already knows the
/// address of most of them — `MKMapItem.url` is the field, and the app was throwing it
/// away everywhere it already looked places up.
///
/// This is a link, not a claim: the app does not scrape the page or state what is on it.
/// It says "the park publishes here" and gets out of the way, which is the honest thing to
/// offer when the alternative is two words saying nothing.
@MainActor
@Observable
final class ParkWebsite {
    static let shared = ParkWebsite()

    enum State: Equatable {
        case idle
        case looking
        /// Apple Maps has a page for this park.
        case found(URL)
        /// Apple Maps answered and has no website for it. Not a failure.
        case none
    }

    private(set) var states: [String: State] = [:]

    private init() {}

    func state(for park: CuratedPark) -> State { states[park.code] ?? .idle }

    func load(_ park: CuratedPark) {
        guard case .idle = state(for: park) else { return }

        // The bundled row already knows, for 2,300 of the 3,003 state parks. That is the
        // park's *own* published address rather than whatever Apple Maps associates with
        // the name, it needs no network, and it cannot pick the wrong Cherry Creek.
        if let known = park.website {
            states[park.code] = .found(known)
            return
        }
        states[park.code] = .looking

        Task { [weak self] in
            guard let self else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = park.full.isEmpty ? park.name : park.full
            // Centred on the park, so "Cherry Creek" finds the one in Colorado rather than
            // the several others in the country.
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: park.lat, longitude: park.lon),
                latitudinalMeters: 40_000, longitudinalMeters: 40_000
            )

            guard let response = try? await MKLocalSearch(request: request).start(),
                  let url = response.mapItems.compactMap(\.url).first else {
                states[park.code] = .none
                return
            }
            states[park.code] = .found(url)
        }
    }
}

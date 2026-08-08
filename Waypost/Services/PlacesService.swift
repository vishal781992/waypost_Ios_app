import Foundation
import MapKit
import SwiftUI

/// What is actually around a park, from Apple Maps.
///
/// This is the answer to the question a camper asks on the way in: where do I charge,
/// where do I fill up, where is the last shop before the gate, and where can I sleep.
/// The curated library had lists for four of the eight shipped parks and nothing for
/// anywhere else in the country; `MKLocalPointsOfInterestRequest` has all of it, needs no
/// key, and is on the phone already.
///
/// Every result carries its distance from the park and, where Apple has them, a phone
/// number and a URL — so a row is something you can act on rather than something you
/// have to go and look up.
@MainActor
@Observable
final class PlacesService {
    static let shared = PlacesService()

    enum Kind: String, CaseIterable, Hashable {
        case charger, fuel, store, campground, lodging, food

        var title: String {
            switch self {
            case .charger: return "Charging"
            case .fuel: return "Fuel"
            case .store: return "Shops & supplies"
            case .campground: return "Campgrounds"
            case .lodging: return "Lodges & hotels"
            case .food: return "Food"
            }
        }

        var categories: [MKPointOfInterestCategory] {
            switch self {
            case .charger: return [.evCharger]
            case .fuel: return [.gasStation]
            case .store: return [.store, .foodMarket, .pharmacy]
            case .campground:
                // RV parks are their own category from iOS 18; before that they come
                // back under campgrounds anyway.
                if #available(iOS 18.0, *) { return [.campground, .rvPark] }
                return [.campground]
            case .lodging: return [.hotel]
            case .food: return [.restaurant, .cafe]
            }
        }

        /// The same question in words. `MKLocalPointsOfInterestRequest` is the precise
        /// way to ask and it is not always answered — it fails outright on some
        /// installs — so every kind also knows how to ask in plain language, which goes
        /// through a different MapKit path.
        var phrase: String {
            switch self {
            case .charger: return "EV charging station"
            case .fuel: return "gas station"
            case .store: return "grocery store"
            case .campground: return "campground"
            case .lodging: return "hotel"
            case .food: return "restaurant"
            }
        }

        /// The symbol this category carries wherever it is listed.
        var glyph: String {
            switch self {
            case .charger: return "bolt.car"
            case .fuel: return "fuelpump"
            case .food: return "fork.knife"
            case .lodging: return "bed.double"
            case .campground: return "tent"
            case .store: return "cart"
            }
        }

        /// The colour this category carries wherever it is listed.
        ///
        /// A driving day lists four kinds of stop at every mile marker, and in one accent
        /// they read as one undifferentiated column. These are earthy rather than the usual
        /// signal colours — moss, brass, terracotta, dusk — so they stay distinguishable at
        /// a glance without fighting the warm page the app is set on.
        var tint: Color {
            switch self {
            case .charger: return Color(hex: 0x3B6D11)
            case .fuel: return Color(hex: 0x854F0B)
            case .food: return Color(hex: 0x993C1D)
            case .lodging: return Color(hex: 0x185FA5)
            case .campground: return Color(hex: 0x0F6E56)
            case .store: return Color(hex: 0x5F5E5A)
            }
        }

        /// The same colour washed out, for the disc the glyph sits on.
        var tintSoft: Color {
            switch self {
            case .charger: return Color(hex: 0xEAF3DE)
            case .fuel: return Color(hex: 0xFAEEDA)
            case .food: return Color(hex: 0xFAECE7)
            case .lodging: return Color(hex: 0xE6F1FB)
            case .campground: return Color(hex: 0xE1F5EE)
            case .store: return Color(hex: 0xF1EFE8)
            }
        }
    }

    struct Place: Identifiable, Hashable {
        var id: String
        var name: String
        var kind: Kind
        var miles: Double
        var locality: String?
        var phone: String?
        var url: URL?
        var lat: Double
        var lon: Double

        /// "12 mi · Moab" — the two things worth knowing before the name is tapped.
        var subtitle: String {
            let distance = miles < 10
                ? String(format: "%.1f mi", miles)
                : "\(Int(miles.rounded())) mi"
            return [distance, locality].compactMap { $0 }.joined(separator: " · ")
        }

        var mapItem: MKMapItem {
            let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            let item = MKMapItem(placemark: placemark)
            item.name = name
            return item
        }
    }

    /// Results by park code and kind, so switching segments does not re-query.
    private(set) var results: [String: [Kind: [Place]]] = [:]
    private(set) var searching: Set<String> = []
    private(set) var failed: [String: String] = [:]

    private init() {}

    func places(_ park: CuratedPark, _ kind: Kind) -> [Place]? { results[park.code]?[kind] }
    func isSearching(_ park: CuratedPark, _ kind: Kind) -> Bool { searching.contains(key(park, kind)) }
    func failure(_ park: CuratedPark, _ kind: Kind) -> String? { failed[key(park, kind)] }

    private func key(_ park: CuratedPark, _ kind: Kind) -> String { park.code + ":" + kind.rawValue }

    /// Asks Apple Maps once per park per kind.
    func load(_ park: CuratedPark, _ kind: Kind, radiusMiles: Double = 30) {
        let key = key(park, kind)
        guard results[park.code]?[kind] == nil, !searching.contains(key) else { return }
        searching.insert(key)

        Task { [weak self] in
            guard let self else { return }
            defer { searching.remove(key) }

            let centre = CLLocationCoordinate2D(latitude: park.lat, longitude: park.lon)
            // The API caps the radius at 50 km; a camper's question is "on the way in",
            // which is nearer than that anyway.
            let metres = min(radiusMiles * 1609.34, 50_000)
            let request = MKLocalPointsOfInterestRequest(center: centre, radius: metres)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)

            do {
                let response = try await search(request, fallback: kind, centre: centre, metres: metres)
                let origin = CLLocation(latitude: park.lat, longitude: park.lon)
                let places = response.mapItems.compactMap { item -> Place? in
                    guard let name = item.name else { return nil }
                    let coordinate = item.placemark.coordinate
                    let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude,
                                                                   longitude: coordinate.longitude))
                    return Place(
                        id: "\(kind.rawValue):\(name):\(coordinate.latitude),\(coordinate.longitude)",
                        name: name,
                        kind: kind,
                        miles: distance / 1609.34,
                        locality: item.placemark.locality,
                        phone: item.phoneNumber,
                        url: item.url,
                        lat: coordinate.latitude,
                        lon: coordinate.longitude
                    )
                }
                .sorted { $0.miles < $1.miles }

                results[park.code, default: [:]][kind] = places
                failed[key] = nil
            } catch {
                // An empty result and a refused request are different answers, and the
                // panel says which one it got.
                failed[key] = String(describing: error).prefix(90).description
                results[park.code, default: [:]][kind] = nil
            }
        }
    }

    /// The points-of-interest request first, then the same question in words.
    ///
    /// The POI request is the better one — it filters server-side by category rather than
    /// by matching a phrase — but it answers `MKErrorGEOError -8` on some installs, and a
    /// screen with nothing on it is not an acceptable outcome when the natural-language
    /// path works fine.
    private func search(_ request: MKLocalPointsOfInterestRequest,
                        fallback kind: Kind,
                        centre: CLLocationCoordinate2D,
                        metres: Double) async throws -> MKLocalSearch.Response {
        do {
            return try await MKLocalSearch(request: request).start()
        } catch {
            let words = MKLocalSearch.Request()
            words.naturalLanguageQuery = kind.phrase
            words.region = MKCoordinateRegion(center: centre,
                                              latitudinalMeters: metres * 2,
                                              longitudinalMeters: metres * 2)
            words.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)
            return try await MKLocalSearch(request: words).start()
        }
    }

    /// Everything a camper wants at once, for the screen that shows several groups.
    func loadAll(_ park: CuratedPark, _ kinds: [Kind], radiusMiles: Double = 30) {
        for kind in kinds { load(park, kind, radiusMiles: radiusMiles) }
    }
}

// MARK: - The rows

/// A group of places under a heading, in the same row shape as the rest of the app.
///
/// Tapping a row hands the place to Apple Maps, because the next thing anybody wants
/// after "where is the nearest charger" is directions to it.
struct PlaceRows: View {
    var park: CuratedPark
    var kind: PlacesService.Kind
    var title: String?
    var limit: Int = 5

    private var places: [PlacesService.Place]? { PlacesService.shared.places(park, kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                // The category's own colour rather than the one accent, so a park's
                // charging, fuel and food read apart at a glance — the same coding the
                // driving day uses for the stops between parks.
                Text(title).font(WP.body(11.5)).foregroundStyle(kind.tint)
            }

            if let places {
                if places.isEmpty {
                    Text("Apple Maps lists none within 30 miles.")
                        .font(WP.bodyItalic(12.5)).opacity(0.6).padding(.vertical, 3)
                } else {
                    ForEach(places.prefix(limit)) { place in
                        Button {
                            place.mapItem.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                            ])
                        } label: {
                            DividedRow(vertical: 10) {
                                HStack(spacing: 12) {
                                    Image(systemName: kind.glyph)
                                        .font(.system(size: 14))
                                        .foregroundStyle(kind.tint)
                                        .frame(width: 28, height: 28)
                                        .background(kind.tintSoft, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name)
                                            .font(WP.rowTitle(15))
                                            .multilineTextAlignment(.leading)
                                        Text(place.subtitle)
                                            .font(WP.body(11.5)).foregroundStyle(kind.tint).tnum()
                                    }
                                    Spacer(minLength: 0)
                                    // The size the driving day's own open-in-Maps control
                                    // is, so the same action is the same target on both.
                                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(WP.accent700)
                                        .frame(width: 36, height: 40)
                                }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.995))
                    }
                }
            } else if let why = PlacesService.shared.failure(park, kind) {
                Text("Apple Maps did not answer — \(why)")
                    .font(WP.bodyItalic(12.5)).opacity(0.6).lineSpacing(2).padding(.vertical, 3)
            } else {
                Text("Asking Apple Maps…")
                    .font(WP.bodyItalic(12.5)).opacity(0.55).padding(.vertical, 3)
            }
        }
        .task(id: park.code + kind.rawValue) {
            PlacesService.shared.load(park, kind)
        }
    }
}

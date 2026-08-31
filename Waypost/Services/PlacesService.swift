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

        /// The number Apple Maps published, as something the phone can dial. Everything
        /// that is not a digit or a leading `+` goes — Maps writes "+1 (435) 719-2299",
        /// and `tel:` wants the number.
        var callLink: URL? {
            guard let phone else { return nil }
            let plus = phone.hasPrefix("+") ? "+" : ""
            let digits = phone.filter(\.isNumber)
            guard digits.count >= 7 else { return nil }
            return URL(string: "tel:\(plus)\(digits)")
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
                let places = Self.places(from: response.mapItems,
                                         kind: kind,
                                         origin: centre,
                                         withinMetres: metres)

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

    /// Whether a result Maps returned is close enough to the point that was asked about.
    ///
    /// This is the one rule both search sites in the app go through — the park screen's
    /// `load`, and `LegStops` for a stop along a drive — because both had the same hole.
    ///
    /// Only one of the two ways either of them asks respects a radius.
    /// `MKLocalPointsOfInterestRequest` bounds its search server-side. The natural-language
    /// request underneath it does not: `MKLocalSearch.Request.region` is a *bias*, and Maps
    /// answers outside it freely — which it does exactly when the region holds none of what
    /// was asked for, falling back to what is near the device. Nothing downstream checked,
    /// so Pinnacles in California listed its nearest charger as an EVgo in Denver, 907 miles
    /// away, under a heading carrying the park's name.
    ///
    /// A point Maps could not place comes back at (0, 0) — the Atlantic off Ghana. It would
    /// fail the radius anyway; it is named separately because "not located" and "far away"
    /// are different facts.
    static func isNear(_ coordinate: CLLocationCoordinate2D,
                       to origin: CLLocationCoordinate2D,
                       withinMetres: Double) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate),
              !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return false }
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to) <= withinMetres
    }

    /// What Maps answered, turned into rows — with anything outside the radius dropped.
    ///
    /// A category with nothing inside the radius now yields no rows, which the chip already
    /// draws as "none". That is the true answer, and it is not an invitation to widen the
    /// search until something turns up.
    static func places(from items: [MKMapItem],
                       kind: Kind,
                       origin: CLLocationCoordinate2D,
                       withinMetres: Double) -> [Place] {
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return items.compactMap { item -> Place? in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            guard isNear(coordinate, to: origin, withinMetres: withinMetres) else { return nil }

            let distance = from.distance(from: CLLocation(latitude: coordinate.latitude,
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
        // The category request answers with nothing at all on some installs — sometimes by
        // throwing `MKErrorGEOError -8`, sometimes by returning an empty list. Only the
        // throwing case used to reach the worded search below, so on an install where it
        // answers "none" instead of refusing, every park showed an empty panel and the
        // fallback that exists for exactly this never ran.
        if let byCategory = try? await MKLocalSearch(request: request).start(),
           !byCategory.mapItems.isEmpty {
            return byCategory
        }

        let words = MKLocalSearch.Request()
        words.naturalLanguageQuery = kind.phrase
        // `latitudinalMeters` is the region's full span, not its radius — so covering a
        // 30-mile radius takes twice that. Passing the radius drew a box half the size of
        // the search and hid genuinely near places behind its edge.
        words.region = MKCoordinateRegion(center: centre,
                                          latitudinalMeters: metres * 2,
                                          longitudinalMeters: metres * 2)
        // On its own a region is only a bias: Maps answers outside it, and does whenever
        // the park has none of this kind nearby — which is how a park in California came to
        // list a charger in Denver. From iOS 18 the region can be made a condition instead
        // of a hint, which is what this is. `places(from:…)` still measures every row,
        // because iOS 17 has no such setting and a backstop that costs nothing is worth
        // keeping.
        if #available(iOS 18.0, *) {
            words.regionPriority = .required
        }
        words.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)
        return try await MKLocalSearch(request: words).start()
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
/// A secondary action on a place row — call it, or open its site. Sized to the same 36×40
/// the directions control is, so the three sit on one baseline.
/// One icon in a place row's trailing cluster — call, website, directions.
///
/// Drawn to the same pattern as the *Add* pill beside it: a capsule of the same height,
/// the same hairline, the same 44pt reach around a smaller mark. It used to be a 40pt
/// rounded rectangle with a heavier border, so a row ended in a squarish box sitting next
/// to a capsule and the pair read as two controls borrowed from different screens.
///
/// The colour is the accent ramp used as a ramp — `accent100` tint, `accent600` hairline,
/// `accent800` mark — the same three steps the passport stamp is built from. It was a bare
/// `accent700` glyph inside a grey `text` hairline, which is the ramp used as *lettering*:
/// that is what `accent700` is for everywhere else in the app (captions, tracking-spaced
/// labels, section rules), and a control wearing a text colour on a neutral border read as
/// a brown mark floating in a box that belonged to something else.
///
/// Not lime, and not `mark`. Lime is a claim about state — *added* on the pill next door,
/// *this opens a booking* on `book` — and `mark` belongs to the round controls that share
/// the app icon's orange. These three are secondary actions with no state, so they take the
/// page's own warm ramp and nothing louder.
struct PlaceAction: View {
    var glyph: String

    var body: some View {
        Image(systemName: glyph)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(WP.accent800)
            .frame(width: 38, height: 30)
            .background {
                Capsule().fill(WP.accent100)
                Capsule().stroke(WP.accent600.opacity(0.45), lineWidth: 0.75)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Charging, fuel and shops as three chips on one line, and the list of whichever one
/// you press underneath.
///
/// Three categories at five rows apiece is most of a screen for something a reader mostly
/// wants to know *exists*, and it sits between the alerts and the campgrounds, which are
/// what the page is for. Shut, the whole section is one line that still answers the
/// question — how many, and how far the nearest one is. Pressed, a chip opens its own list
/// and the other two stay shut.
///
/// The chips carry a glyph rather than the category's name, which is what buys the line.
/// The word is not lost: it is the accessibility label, and it heads the list the moment
/// one is open — so nobody has to know what a basket means to use this.
struct PlaceCategoryChips: View {
    var park: CuratedPark
    var kinds: [PlacesService.Kind]
    var limit: Int = 5

    /// Which category's list is showing. Nil is shut.
    @State private var open: PlacesService.Kind?

    /// Whether the section has already opened itself once.
    ///
    /// A row of chips with nothing under them gives a reader no reason to think there is
    /// anything under them. So the first category that has results opens on arrival: the
    /// ring and the list explain each other, and the mechanism is demonstrated rather
    /// than hinted at. It happens once — close it and it stays closed.
    @State private var didAutoOpen = false

    /// The first category the park actually has anything in. Charging usually, but a park
    /// with no chargers within thirty miles opens on fuel rather than on an empty chip.
    ///
    /// Nil while an earlier category is still unresolved, which is the whole point of the
    /// loop. Asking for `kinds.first { places is non-empty }` treated "Apple Maps has not
    /// answered yet" and "Apple Maps says none" as the same thing, so the section opened
    /// on whichever category happened to answer first — shops, usually, being the shortest
    /// search. Waiting for each in turn is what makes the order the order.
    private var firstWithRows: PlacesService.Kind? {
        for kind in kinds {
            guard let places = PlacesService.shared.places(park, kind) else {
                // A lookup that failed outright is never going to answer; it is a category
                // with nothing in it as far as this is concerned, so move past it.
                if PlacesService.shared.failure(park, kind) != nil { continue }
                return nil
            }
            if !places.isEmpty { return kind }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Equal shares of the row rather than three chips hugging their text with a
            // third of the width left dead beside them. Fixed shares also mean a chip
            // does not resize when the mileage under it changes from `2.0 mi` to `14 mi`.
            HStack(spacing: 7) {
                ForEach(kinds, id: \.self) { kind in
                    chip(kind)
                        .frame(maxWidth: .infinity)
                }
            }

            if let open {
                // The name the chip could not carry, restored the moment there is room
                // for it. Also the only thing on screen that says which chip is down.
                Text(caption(open))
                    .font(WP.body(11.5))
                    .foregroundStyle(open.tint)
                    .padding(.top, 13)

                PlaceRows(park: park, kind: open, title: nil, limit: limit)
                    .transition(.opacity)
            }
        }
        // The chips have to know their counts before anybody presses one, and the row
        // list is what used to do the asking — it carries the `.task` that starts the
        // lookup. Mounted only for the open category, that meant nothing was ever
        // requested and all three chips sat on their loading ellipsis forever. The
        // section asks for all of its categories up front, which is what `loadAll` is for.
        .task(id: park.code) {
            PlacesService.shared.loadAll(park, kinds)
            // A park whose answers are already on hand never fires the change below.
            didAutoOpen = false
            autoOpen()
        }
        // Apple Maps answers well after the section is drawn, so the usual case is this
        // one: the chips arrive empty and the first of them opens as its results land.
        .onChange(of: firstWithRows) { _, _ in autoOpen() }
    }

    private func autoOpen() {
        guard !didAutoOpen, let kind = firstWithRows else { return }
        didAutoOpen = true
        withAnimation(Motion.panel) { open = kind }
    }

    // MARK: One chip

    @ViewBuilder
    private func chip(_ kind: PlacesService.Kind) -> some View {
        let places = PlacesService.shared.places(park, kind)
        let isOpen = open == kind
        let hasRows = !(places?.isEmpty ?? true)

        Button {
            withAnimation(Motion.panel) { open = isOpen ? nil : kind }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.glyph)
                    .font(.system(size: 12, weight: .medium))
                Text(label(kind, places))
                    .font(WP.body(12))
                    .tnum()
            }
            .foregroundStyle(kind.tint)
            // Fills its share of the row. The `maxWidth` at the call site sizes the
            // *button*; without this one the capsule still hugged its text and sat
            // centred in a third of the row with the rest of that third left blank.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            // Selection is a ring, not a flood. Filling the open chip with `kind.tint`
            // read as a pressed or disabled control rather than a chosen one — and shops
            // are a neutral grey, so that fill came out as a black pill sitting between
            // two pale ones. The soft wash and a solid edge say "this is the open one"
            // without any chip having to change what colour it is.
            .background(isOpen ? kind.tintSoft : .clear, in: Capsule())
            .overlay {
                Capsule().stroke(kind.tint.opacity(isOpen ? 1 : 0.28),
                                 lineWidth: isOpen ? 1.5 : 0.5)
            }
            // A chip is 30pt of ink and a finger is not. The target grows around it
            // rather than the chip growing to meet it.
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .disabled(!hasRows)
        // Nothing to open reads as nothing to press.
        .opacity(hasRows ? 1 : 0.45)
        .accessibilityLabel(kind.title)
        .accessibilityValue(accessibilityValue(kind, places))
        .accessibilityHint(hasRows ? (isOpen ? "Closes the list" : "Opens the list") : "")
        .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: What a chip says

    /// `5 · 8.0 mi`, and the honest short forms when there is no list behind it. The
    /// distance is sliced off the first row's own subtitle, so the chip and the row it
    /// summarises can never disagree.
    private func label(_ kind: PlacesService.Kind, _ places: [PlacesService.Place]?) -> String {
        guard let places else { return "…" }
        guard let first = places.first else { return "none" }
        let shown = min(places.count, limit)
        let nearest = first.subtitle
            .split(separator: "·").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return nearest.isEmpty ? "\(shown)" : "\(shown) · \(nearest)"
    }

    /// The heading over an open list — the category's name, spelled out.
    private func caption(_ kind: PlacesService.Kind) -> String {
        let places = PlacesService.shared.places(park, kind) ?? []
        let shown = min(places.count, limit)
        return shown == 1 ? "\(kind.title) · 1 nearby" : "\(kind.title) · \(shown) nearby"
    }

    /// Said in full for VoiceOver, where a glyph and an abbreviation say nothing.
    private func accessibilityValue(_ kind: PlacesService.Kind, _ places: [PlacesService.Place]?) -> String {
        guard let places else { return "Still looking" }
        guard let first = places.first else {
            if let why = PlacesService.shared.failure(park, kind) { return "Apple Maps did not answer — \(why)" }
            return "None within 30 miles"
        }
        return "\(min(places.count, limit)) nearby, nearest \(first.subtitle)"
    }
}

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
                        // Directions, a call and the site are three different errands, so
                        // they are three controls rather than one row that guesses. Apple
                        // Maps has carried the number and the website on every result all
                        // along; only the directions were ever wired up.
                        DividedRow(vertical: 10) {
                            HStack(spacing: 8) {
                                Button {
                                    place.mapItem.openInMaps(launchOptions: [
                                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                                    ])
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: kind.glyph)
                                            .font(.system(size: 14))
                                            .foregroundStyle(kind.tint)
                                            .frame(width: 28, height: 28)
                                            .background(kind.tintSoft, in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            // Three controls to the right leave less room
                                            // for the name; two lines and then a tail, so
                                            // a long resort name cannot push a row to
                                            // four.
                                            Text(place.name)
                                                .font(WP.rowTitle(15))
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(2)
                                            Text(place.subtitle)
                                                .font(WP.body(11.5)).foregroundStyle(kind.tint).tnum()
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle(scale: 0.995))

                                // Curation happens where the reader already is. Every list
                                // in the app is a place they might want on their trip, so
                                // the control goes on the row rather than behind a search
                                // screen of its own. It draws nothing outside a trip.
                                PlaceRowActions(
                                    place: PlannedPlace(
                                        name: place.name,
                                        subtitle: place.subtitle,
                                        lat: place.mapItem.placemark.coordinate.latitude,
                                        lon: place.mapItem.placemark.coordinate.longitude,
                                        category: kind.rawValue
                                    ),
                                    day: nil,
                                    call: place.callLink,
                                    site: place.url
                                )
                            }
                        }
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

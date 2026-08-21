import Foundation
import MapKit

/// One thing a traveller has put on a trip's list.
///
/// The trip's third tab used to be Stays — a read-only catalogue of the park service's
/// campgrounds, which is a strictly worse version of a screen one tap away on the park
/// itself. This is what replaced it: not a list the app made, but the one the reader made,
/// built by pressing *add* on rows that were already there. A charger before the climb, the
/// last shop before the gate, the lodge they actually booked, the permit page, and a note
/// about the shuttle selling out by seven.
///
/// Three kinds, and the difference matters at the bottom of the screen: a **place** has
/// coordinates and can therefore be a waypoint in a drive; a **link** and a **note** cannot,
/// and so never offer to be one.
struct PlanItem: Codable, Hashable, Identifiable {
    var id: String
    /// The day this belongs to. Nil is deliberate and not a gap — a packing document or a
    /// trail list for the whole week is not a Tuesday thing, and forcing a date onto it
    /// would be a small lie that makes people stop using the list.
    var day: Date?
    var kind: Kind
    /// Whether a place is included when the list builds a drive.
    ///
    /// Everything is a stop when it is added, because a reader who added a charger meant
    /// to stop at it. Switching one off leaves it on the list and out of the route, which
    /// is the difference between "I am not going" and "I do not need directions to it".
    var isStop: Bool = true
    /// When it was added, which is the order the list keeps within a day.
    var added: Date

    enum Kind: Codable, Hashable {
        case place(PlannedPlace)
        /// Somebody's own link. Unfurled by `LinkPreviews`, which fetches the title and
        /// picture once and keeps them.
        case link(URL)
        case note(String)
    }

    /// Only a place can be driven to.
    var place: PlannedPlace? {
        if case .place(let place) = kind { return place }
        return nil
    }

    var isPlace: Bool { place != nil }
}

/// A place as it was when somebody added it.
///
/// Written down in full rather than kept as a search to re-run. A curated list that went
/// back to Apple Maps on every launch would reshuffle itself — different results, different
/// order, sometimes a different café — and a list that changes under you is not a list.
struct PlannedPlace: Codable, Hashable {
    var name: String
    /// The line under the name, as the row it was added from wrote it: `8.0 mi · Estes Park`.
    var subtitle: String
    var lat: Double
    var lon: Double
    /// Which `PlacesService.Kind` this was, by raw value, so the list can draw the same
    /// glyph in the same colour the row it came from used.
    var category: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var kind: PlacesService.Kind? { PlacesService.Kind(rawValue: category) }

    /// A map item to hand to Apple Maps. Built from coordinates rather than kept as one:
    /// `MKMapItem` is not `Codable`, and a name and a point are all directions need.
    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }
}

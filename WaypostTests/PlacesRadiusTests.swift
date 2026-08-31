import CoreLocation
import MapKit
import XCTest
@testable import Waypost

/// That "near the park" means near the park, and "on the way" means on the way.
///
/// The bug: Pinnacles National Park, in California, listed its nearest EV charger as an
/// EVgo in Denver — 907 miles away — under a heading carrying the park's own name. Charging,
/// fuel and shops all read `907 mi`, which is the distance from Pinnacles to the *phone*
/// rather than to anything a driver could reach. The same fault put a stop hundreds of
/// miles off the road on a trip's driving day.
///
/// The cause was never the centre of the search, which was always the park or the sample
/// point. It is that only one of the two ways the app asks respects a radius.
/// `MKLocalPointsOfInterestRequest` bounds itself server-side; the natural-language request
/// it falls back to when that path errors treats `region` as a bias it may ignore — and does
/// ignore when the region holds nothing of the kind asked for, at which point Maps answers
/// with what is near the device. Nothing downstream checked.
///
/// These exercise `PlacesService.isNear` and `PlacesService.places(from:…)`, which are the
/// single rule both search sites now go through. No network and no simulator location: the
/// coordinates are real, and the distances between them are what the earth says they are.
@MainActor
final class PlacesRadiusTests: XCTestCase {

    private let pinnacles = CLLocationCoordinate2D(latitude: 36.4869, longitude: -121.167)
    private let denver = CLLocationCoordinate2D(latitude: 39.7392, longitude: -104.9903)
    /// Soledad, the nearest town of any size to the Pinnacles west entrance.
    private let soledad = CLLocationCoordinate2D(latitude: 36.4247, longitude: -121.3263)
    /// Paicines, on the road to the east entrance.
    private let paicines = CLLocationCoordinate2D(latitude: 36.7277, longitude: -121.2777)

    private let thirtyMiles = 30 * 1609.34

    private func item(_ name: String,
                      _ coordinate: CLLocationCoordinate2D,
                      locality: String? = nil) -> MKMapItem {
        let placemark = MKPlacemark(
            coordinate: coordinate,
            addressDictionary: locality.map { ["City": $0] }
        )
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    private func places(_ items: [MKMapItem],
                        kind: PlacesService.Kind = .charger,
                        withinMetres: Double? = nil) -> [PlacesService.Place] {
        PlacesService.places(from: items,
                             kind: kind,
                             origin: pinnacles,
                             withinMetres: withinMetres ?? thirtyMiles)
    }

    // MARK: The reported bug

    func testAChargerNineHundredMilesAwayIsNotNearThePark() {
        let rows = places([item("EVgo", denver, locality: "Denver")])
        XCTAssertTrue(rows.isEmpty,
                      "A charger in Denver is not a charger near Pinnacles; it must not be listed.")
    }

    /// An empty list is the answer the chip already draws as "none". The failure being
    /// fixed is a wrong row, not a missing one.
    func testNothingWithinTheRadiusYieldsNoRowsRatherThanTheNearestFarOne() {
        let rows = places([
            item("EVgo", denver, locality: "Denver"),
            item("Electrify America", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                 locality: "San Francisco"),
        ])
        XCTAssertEqual(rows.count, 0)
    }

    /// The half that must survive: real neighbours are still listed.
    func testPlacesInsideTheRadiusSurvive() {
        let rows = places([
            item("Soledad Charging", soledad, locality: "Soledad"),
            item("EVgo", denver, locality: "Denver"),
            item("Paicines Pump", paicines, locality: "Paicines"),
        ])
        XCTAssertEqual(rows.map(\.name), ["Soledad Charging", "Paicines Pump"])
    }

    // MARK: The measurements a row carries

    func testDistanceIsMeasuredFromTheParkNotFromAnywhereElse() throws {
        let row = try XCTUnwrap(places([item("Soledad Charging", soledad)]).first)
        // Pinnacles to Soledad is about nine miles as the crow flies.
        XCTAssertEqual(row.miles, 9.0, accuracy: 1.5)
    }

    func testRowsComeBackNearestFirst() {
        let rows = places([item("Paicines Pump", paicines), item("Soledad Charging", soledad)])
        XCTAssertEqual(rows.map(\.name), ["Soledad Charging", "Paicines Pump"])
        XCTAssertLessThan(rows[0].miles, rows[1].miles)
    }

    /// The chip reads the first row's own subtitle, so this is the string that broke.
    func testTheSubtitleTheChipShowsIsTheOneThatWasWrong() throws {
        let subtitle = try XCTUnwrap(places([item("Soledad Charging", soledad, locality: "Soledad")]).first).subtitle
        XCTAssertTrue(subtitle.contains("mi"), "Got \(subtitle)")
        XCTAssertFalse(subtitle.contains("907"), "Got \(subtitle)")
    }

    // MARK: The edge of the boundary

    func testTheBoundaryIsInclusive() {
        let degrees = thirtyMiles / 111_320.0
        let onTheLine = CLLocationCoordinate2D(latitude: pinnacles.latitude + degrees * 0.999,
                                               longitude: pinnacles.longitude)
        XCTAssertEqual(places([item("Edge", onTheLine)]).count, 1)
    }

    func testJustOutsideTheBoundaryIsDropped() {
        let degrees = thirtyMiles / 111_320.0
        let pastIt = CLLocationCoordinate2D(latitude: pinnacles.latitude + degrees * 1.05,
                                            longitude: pinnacles.longitude)
        XCTAssertEqual(places([item("Past it", pastIt)]).count, 0)
    }

    func testAWiderRadiusAdmitsWhatThirtyMilesRefused() {
        let items = [item("EVgo", denver, locality: "Denver")]
        XCTAssertEqual(places(items).count, 0)
        XCTAssertEqual(places(items, withinMetres: 1_000 * 1609.34).count, 1)
    }

    // MARK: What is not a place

    /// A result Maps could not locate arrives at (0, 0) — the Atlantic off Ghana.
    func testUnlocatableResultsAreDroppedRatherThanMeasured() {
        XCTAssertTrue(places([item("Nowhere", CLLocationCoordinate2D(latitude: 0, longitude: 0))]).isEmpty)
        XCTAssertFalse(PlacesService.isNear(CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                            to: pinnacles, withinMetres: thirtyMiles))
    }

    // There is no test for a nameless result. `places(from:…)` guards on `item.name` and
    // should keep doing so, but the condition cannot be built: `MKMapItem` synthesises a
    // name from its placemark, so assigning nil does not produce one.

    // MARK: Every category, not only the one that was reported

    /// Charging was what the report named; fuel and shops read 907 miles on the same
    /// screen, and campgrounds, lodging and food ask Maps in exactly the same way.
    func testEveryCategoryIsHeldToTheRadius() {
        for kind in PlacesService.Kind.allCases {
            let rows = places([
                item("Far", denver, locality: "Denver"),
                item("Near", soledad, locality: "Soledad"),
            ], kind: kind)
            XCTAssertEqual(rows.map(\.name), ["Near"], "\(kind.rawValue) let a Denver row through")
            XCTAssertEqual(rows.first?.kind, kind)
        }
    }

    // MARK: The trip's driving day, which had the same hole

    /// `LegStops.nearest` took the minimum by distance over whatever Maps returned, with no
    /// bound at all — so an empty stretch of interstate got a filling station near the
    /// phone. It now filters through `isNear` before taking the minimum; this is that rule.
    func testALegSampleRejectsAStopOffTheRoute() {
        // A sample somewhere on I-5 in the Central Valley, and the radius a leg uses at the
        // default 80-mile spacing: half the spacing, in metres.
        let sample = CLLocationCoordinate2D(latitude: 36.3300, longitude: -120.1800)
        let legRadius = min(max(80 / 2 * 1609.34, 8_000), 50_000)

        XCTAssertFalse(PlacesService.isNear(denver, to: sample, withinMetres: legRadius),
                       "Denver is not a stop on a drive through the Central Valley.")
        // Something genuinely beside that stretch still passes.
        let coalinga = CLLocationCoordinate2D(latitude: 36.1397, longitude: -120.3601)
        XCTAssertTrue(PlacesService.isNear(coalinga, to: sample, withinMetres: legRadius))
    }
}

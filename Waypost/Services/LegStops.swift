import Foundation
import MapKit

/// Where to stop on a driving day, and what the road is actually like today.
///
/// The leg sheet said "no traffic, no departure time — this is the road, not the day",
/// which was honest and not much use on the morning you are driving it. This adds the two
/// things the disclaimer was apologising for: fuel and charging along the way, and a
/// travel time that accounts for conditions.
///
/// Apple Maps for both. `MKLocalPointsOfInterestRequest` caps its radius at 50 km, so a
/// 365-mile leg cannot be covered by one search from the middle — the route is sampled
/// every 80 miles instead and each sample searched in its own right, which is also the
/// spacing a driver actually thinks in.
@MainActor
@Observable
final class LegStops {
    static let shared = LegStops()

    struct Stop: Identifiable, Hashable {
        var name: String
        var kind: PlacesService.Kind
        /// How far along the leg this is, in miles from the start.
        var mile: Int
        var lat: Double
        var lon: Double
        var id: String { "\(kind.rawValue):\(name):\(mile)" }

        var mapItem: MKMapItem {
            let item = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            item.name = name
            return item
        }
    }

    /// What the drive looks like today, as distinct from what the road measures.
    struct Traffic: Hashable {
        var seconds: TimeInterval
        var checkedAt: Date

        var wheelTime: String {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return hours > 0 ? "\(hours) h \(minutes) m" : "\(minutes) m"
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case ready([Stop], Traffic?)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    /// How often to look for somewhere to stop. Eighty miles is roughly an hour and a
    /// quarter of driving, and comfortably inside the 50 km search radius on either side.
    private static let spacingMiles: Double = 80

    private init() {}

    func state(for leg: TripRouting.Leg) -> State { states[leg.id] ?? .idle }

    /// Only worth asking on the day. Traffic three weeks out is not a forecast of
    /// anything, and a list of open petrol stations is no better.
    static func isDriveDay(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    func load(_ leg: TripRouting.Leg, electric: Bool) {
        switch state(for: leg) {
        case .idle, .failed: break
        default: return
        }
        guard leg.coordinates.count > 1 else {
            states[leg.id] = .failed("This leg has no route to follow.")
            return
        }
        states[leg.id] = .loading

        Task { [weak self] in
            guard let self else { return }
            let samples = Self.samples(along: leg.coordinates, everyMiles: Self.spacingMiles)
            // Charging first for an electric vehicle, fuel first otherwise — the one that
            // decides whether the drive is possible goes at the top of each stop.
            let kinds: [PlacesService.Kind] = electric ? [.charger, .fuel] : [.fuel, .charger]

            var stops: [Stop] = []
            for sample in samples {
                for kind in kinds {
                    if let stop = await Self.nearest(kind, to: sample) { stops.append(stop) }
                }
            }
            let traffic = await Self.traffic(from: leg.coordinates.first, to: leg.coordinates.last)
            states[leg.id] = .ready(stops, traffic)
        }
    }

    // MARK: Sampling

    private struct Sample {
        var lat: Double
        var lon: Double
        var mile: Int
    }

    /// Points every `everyMiles` along the polyline, plus nothing at either end — the
    /// start and the finish are the parks themselves, which have their own screens.
    private static func samples(along coordinates: [(lat: Double, lon: Double)],
                                everyMiles: Double) -> [Sample] {
        var out: [Sample] = []
        var travelled: Double = 0
        var nextStop = everyMiles

        for index in 1..<coordinates.count {
            let previous = coordinates[index - 1]
            let current = coordinates[index]
            travelled += Geo.haversine(previous, current)
            while travelled >= nextStop {
                out.append(Sample(lat: current.lat, lon: current.lon, mile: Int(nextStop)))
                nextStop += everyMiles
            }
        }
        return out
    }

    private static func nearest(_ kind: PlacesService.Kind, to sample: Sample) async -> Stop? {
        let centre = CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon)
        let request = MKLocalPointsOfInterestRequest(center: centre, radius: 16_000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)

        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let origin = CLLocation(latitude: sample.lat, longitude: sample.lon)
        let best = response.mapItems
            .compactMap { item -> (MKMapItem, CLLocationDistance)? in
                guard item.name != nil else { return nil }
                let where_ = item.placemark.coordinate
                return (item, origin.distance(from: CLLocation(latitude: where_.latitude,
                                                              longitude: where_.longitude)))
            }
            .min { $0.1 < $1.1 }?.0

        guard let best, let name = best.name else { return nil }
        return Stop(name: name, kind: kind, mile: sample.mile,
                    lat: best.placemark.coordinate.latitude,
                    lon: best.placemark.coordinate.longitude)
    }

    // MARK: Traffic

    /// Apple's own estimate for leaving now, which unlike OSRM's accounts for conditions.
    private static func traffic(from start: (lat: Double, lon: Double)?,
                                to end: (lat: Double, lon: Double)?) async -> Traffic? {
        guard let start, let end else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: start.lat, longitude: start.lon)))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: end.lat, longitude: end.lon)))
        request.transportType = .automobile
        request.departureDate = Date()

        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        return Traffic(seconds: route.expectedTravelTime, checkedAt: Date())
    }
}

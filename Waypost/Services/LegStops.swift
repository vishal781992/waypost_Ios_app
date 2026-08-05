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

        var glyph: String {
            switch kind {
            case .charger: return "bolt.car"
            case .food: return "fork.knife"
            default: return "fuelpump"
            }
        }

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

    /// A ceiling on how many places to ask about. Eighty miles across a 2,275-mile drive is
    /// twenty-eight stops, which is not a list anybody reads — and eighty-four searches,
    /// which is not a wait anybody sits through. Beyond this the spacing widens instead.
    private static let maxSamples = 10

    private init() {}

    func state(for leg: TripRouting.Leg) -> State { states[leg.id] ?? .idle }

    /// How long before departure this becomes worth asking. A trip's start is a date with
    /// no time on it, so five hours before it means the evening before the drive — which is
    /// when the packing happens and the question first gets asked.
    static let liveWindow: TimeInterval = 5 * 3600

    /// Live from five hours before the drive until the end of the day it is driven.
    ///
    /// Not `isDateInToday`, which was the first cut: that shows nothing at eleven at night
    /// for a drive starting at six the next morning, and keeps showing traffic all day for
    /// a drive that has already happened.
    static func isLive(_ date: Date?) -> Bool {
        guard let date else { return false }
        let calendar = Calendar.current
        let opens = date.addingTimeInterval(-liveWindow)
        guard let closes = calendar.date(byAdding: .day, value: 1,
                                         to: calendar.startOfDay(for: date)) else { return false }
        let now = Date()
        return now >= opens && now < closes
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
            // How far apart to look for somewhere to stop, scaled to the leg.
            //
            // A fixed eighty-mile start gave a leg shorter than eighty no stop at all — a
            // 72-mile drive showed nothing — because the first sample never arrived. Under
            // 160 miles, halve the leg instead: one stop near the middle, which is the
            // useful place for it and, more to the point, always exists. From 160 up, a
            // stop every eighty miles, still widened past ~800 so a cross-country leg does
            // not fire dozens of searches.
            let spacing: Double = leg.miles < 160
                ? max(1, Double(leg.miles) / 2)
                : max(Self.spacingMiles, Double(leg.miles) / Double(Self.maxSamples))
            let samples = Self.samples(along: leg.coordinates, everyMiles: spacing)
            // Charging first for an electric vehicle, fuel first otherwise — the one that
            // decides whether the drive is possible goes at the top of each stop.
            let kinds: [PlacesService.Kind] = electric
                ? [.charger, .fuel, .food]
                : [.fuel, .charger, .food]

            // Concurrently, and grouped so the list still reads in travel order. Run one
            // after another this was 84 searches end to end on a 2,275-mile leg, which is
            // most of a minute of staring at a spinner.
            var stops: [Stop] = await withTaskGroup(of: [Stop].self) { group in
                for sample in samples {
                    group.addTask { @MainActor in
                        var found: [Stop] = []
                        for kind in kinds {
                            if let stop = await Self.nearest(kind, to: sample) { found.append(stop) }
                        }
                        return found
                    }
                }
                var all: [Stop] = []
                for await batch in group { all += batch }
                return all
            }
            stops.sort { $0.mile == $1.mile ? kindOrder(kinds, $0) < kindOrder(kinds, $1) : $0.mile < $1.mile }
            let traffic = await Self.traffic(from: leg.coordinates.first, to: leg.coordinates.last)
            states[leg.id] = .ready(stops, traffic)
        }
    }

    /// Keeps each mile's stops in the order the kinds were asked for.
    private func kindOrder(_ kinds: [PlacesService.Kind], _ stop: Stop) -> Int {
        kinds.firstIndex(of: stop.kind) ?? kinds.count
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

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

        var glyph: String { kind.glyph }

        /// One word for the row, where `Kind.title` is a section heading — "lodges &
        /// hotels" reads as a category, "hotel" reads as the thing you are stopping at.
        var label: String {
            switch kind {
            case .charger: return "charging"
            case .fuel: return "fuel"
            case .food: return "food"
            case .lodging: return "hotel"
            default: return kind.title.lowercased()
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

    /// How many searches may be in flight at once.
    ///
    /// Every sample asked for every kind at the same instant — twenty-one concurrent
    /// searches on a six-hundred-mile leg — and MapKit answered most of them with
    /// `loadingThrottled`. Those refusals were discarded silently, so the leg showed only
    /// the handful of samples that happened to get through: three stops, all at the same
    /// mile. A small window keeps every sample inside what MapKit will actually serve.
    private static let maxConcurrentSearches = 4

    /// How far off the route a stop may be, scaled to the spacing so the search covers the
    /// gap between one sample and the next rather than a fixed circle around each.
    ///
    /// `MKLocalPointsOfInterestRequest` caps its own radius at 50 km and refuses anything
    /// larger. Because only the *nearest* result is kept, a wider circle never displaces a
    /// closer stop — it only answers on the empty stretches where a narrow one found
    /// nothing at all.
    private static func radius(forSpacing miles: Double) -> Double {
        min(max(miles / 2 * 1609.34, 8_000), 50_000)
    }

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

    func load(_ leg: TripRouting.Leg, electric: Bool, includeTraffic: Bool) {
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
            let samples = Self.samples(along: leg.coordinates,
                                       everyMiles: spacing,
                                       roadMiles: Double(leg.miles))
            // Charging first for an electric vehicle, fuel first otherwise — the one that
            // decides whether the drive is possible goes at the top of each stop. Somewhere
            // to sleep comes last: it is the only one of the four that is a choice rather
            // than a necessity, and on a leg short enough to drive in a day, not needed.
            let kinds: [PlacesService.Kind] = electric
                ? [.charger, .fuel, .food, .lodging]
                : [.fuel, .charger, .food, .lodging]
            let radius = Self.radius(forSpacing: spacing)

            // Concurrently, but only a few at a time: run all at once MapKit throttles the
            // burst, and run one after another this is 84 searches end to end on a
            // 2,275-mile leg, which is most of a minute of staring at a spinner. A sliding
            // window of `maxConcurrentSearches` keeps the wait short without asking for
            // more than MapKit will answer.
            let wanted = samples.flatMap { sample in kinds.map { (sample: sample, kind: $0) } }
            var queue = wanted.makeIterator()
            var stops: [Stop] = []
            var refusals: [String] = []

            await withTaskGroup(of: Lookup.self) { group in
                for _ in 0..<Self.maxConcurrentSearches {
                    guard let next = queue.next() else { break }
                    group.addTask { @MainActor in
                        await Self.nearest(next.kind, to: next.sample, radius: radius)
                    }
                }
                // One more goes in as each one lands, so the window stays full until the
                // last sample has been asked about.
                for await outcome in group {
                    switch outcome {
                    case .found(let stop): stops.append(stop)
                    case .empty: break
                    case .refused(let why): refusals.append(why)
                    }
                    if let next = queue.next() {
                        group.addTask { @MainActor in
                            await Self.nearest(next.kind, to: next.sample, radius: radius)
                        }
                    }
                }
            }

            stops.sort { $0.mile == $1.mile ? kindOrder(kinds, $0) < kindOrder(kinds, $1) : $0.mile < $1.mile }
            // Neighbouring samples overlap where the spacing is tight, and the same filling
            // station answers both. Keep the first time it appears — which is the earliest
            // mile it is useful at — and drop the repeat.
            var seen = Set<String>()
            stops = stops.filter {
                seen.insert("\($0.kind.rawValue)|\($0.name.lowercased())|"
                            + "\(Int(($0.lat * 100).rounded()))|\(Int(($0.lon * 100).rounded()))").inserted
            }

            // Traffic is a leaving-now estimate, so it is only asked for when the drive is
            // within its window. The stops came regardless.
            let traffic = includeTraffic
                ? await Self.traffic(from: leg.coordinates.first, to: leg.coordinates.last)
                : nil

            // "Apple Maps lists nothing along this route" and "Apple Maps would not answer"
            // are different sentences, and the screen used to say the first one whichever
            // had happened. Nothing found *and* something refused means the second.
            if stops.isEmpty, let why = refusals.first {
                states[leg.id] = .failed("Apple Maps did not answer for this route — \(why).")
            } else {
                states[leg.id] = .ready(stops, traffic)
            }
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
    ///
    /// Two things this has to get right, because the leg screen reads the miles it returns:
    ///
    /// The route arrives simplified, so its vertices are up to seventy-odd miles apart.
    /// Snapping each sample to the vertex *after* the mile it wanted put several samples on
    /// one point — a 605-mile drive asked for miles 80 through 560 and got the same
    /// coordinate for most of them. A sample that falls mid-segment is interpolated along
    /// it instead.
    ///
    /// Simplifying also shortens the line: 579 miles of vertices for a 603-mile drive. The
    /// walk is therefore done in polyline miles and reported in road miles, so "mile 240"
    /// is 240 miles of driving rather than 240 miles of a shape that runs short.
    private static func samples(along coordinates: [(lat: Double, lon: Double)],
                                everyMiles: Double,
                                roadMiles: Double) -> [Sample] {
        guard coordinates.count > 1, everyMiles > 0 else { return [] }

        var lengths: [Double] = []
        var polylineMiles: Double = 0
        for index in 1..<coordinates.count {
            let segment = Geo.haversine(coordinates[index - 1], coordinates[index])
            lengths.append(segment)
            polylineMiles += segment
        }
        guard polylineMiles > 0 else { return [] }

        let scale = roadMiles > 0 ? roadMiles / polylineMiles : 1
        let step = everyMiles / scale

        var out: [Sample] = []
        var travelled: Double = 0
        var next = step

        for index in 1..<coordinates.count {
            let previous = coordinates[index - 1]
            let current = coordinates[index]
            let segment = lengths[index - 1]
            guard segment > 0 else { continue }
            while next <= travelled + segment {
                let t = (next - travelled) / segment
                out.append(Sample(lat: previous.lat + (current.lat - previous.lat) * t,
                                  lon: previous.lon + (current.lon - previous.lon) * t,
                                  mile: max(1, Int((next * scale).rounded()))))
                next += step
            }
            travelled += segment
        }
        // A sample that lands on the finish is the destination park, which has its own
        // screen; it is not somewhere to stop on the way.
        if let last = out.last, last.mile >= Int(roadMiles.rounded()) { out.removeLast() }
        return out
    }

    /// What one search came back with. A refusal and an empty stretch of road are not the
    /// same answer, and this used to return `nil` for both — which is why a throttled leg
    /// looked exactly like a leg with no filling stations on it.
    private enum Lookup {
        case found(Stop)
        case empty
        case refused(String)
    }

    private static func nearest(_ kind: PlacesService.Kind,
                                to sample: Sample,
                                radius: Double) async -> Lookup {
        let centre = CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon)
        let items: [MKMapItem]
        do {
            items = try await places(kind, centre: centre, radius: radius)
        } catch {
            return .refused(describe(error))
        }

        let origin = CLLocation(latitude: sample.lat, longitude: sample.lon)
        let best = items
            .compactMap { item -> (MKMapItem, CLLocationDistance)? in
                guard item.name != nil else { return nil }
                let where_ = item.placemark.coordinate
                return (item, origin.distance(from: CLLocation(latitude: where_.latitude,
                                                              longitude: where_.longitude)))
            }
            .min { $0.1 < $1.1 }?.0

        guard let best, let name = best.name else { return .empty }
        return .found(Stop(name: name, kind: kind, mile: sample.mile,
                           lat: best.placemark.coordinate.latitude,
                           lon: best.placemark.coordinate.longitude))
    }

    /// The points-of-interest request first, then the same question in plain language.
    ///
    /// The category request is the better one — it filters server-side rather than by
    /// matching a phrase — but it answers `MKErrorGEOError -8` on some installs, which is
    /// why `PlacesService` has carried a worded fallback since the park screens were built.
    /// The leg had no such fallback, so wherever the category path was refused the stop
    /// simply never appeared.
    /// Throws only when Maps refused to answer. "Nothing here" comes back as an empty
    /// array, because an empty stretch of road is an answer and the screen says so.
    private static func places(_ kind: PlacesService.Kind,
                               centre: CLLocationCoordinate2D,
                               radius: Double) async throws -> [MKMapItem] {
        // The category request is the better one when it works, so it is asked first and
        // its answer is taken whenever it has one.
        let byCategory = try? await retrying {
            let request = MKLocalPointsOfInterestRequest(center: centre, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)
            return try await MKLocalSearch(request: request).start().mapItems
        }
        if let byCategory, !byCategory.isEmpty { return byCategory }

        // Anything else — a refusal, or `placemarkNotFound` over a stretch of interstate
        // that plainly has filling stations on it — and the question is asked again in
        // words. The category request reports "nothing found" spuriously on some installs,
        // so its silence cannot be taken for an empty road; only the worded search agreeing
        // makes it one.
        do {
            return try await retrying {
                let words = MKLocalSearch.Request()
                words.naturalLanguageQuery = kind.phrase
                words.region = MKCoordinateRegion(center: centre,
                                                  latitudinalMeters: radius * 2,
                                                  longitudinalMeters: radius * 2)
                words.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)
                return try await MKLocalSearch(request: words).start().mapItems
            }
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    /// Asks again when the refusal was a "not now" rather than a "no".
    ///
    /// Throttling and server failures are the two MapKit gives out under load, and both
    /// clear on their own within a moment. Backing off between tries is what makes a long
    /// leg's worth of searches all arrive rather than the first few.
    private static func retrying<T>(attempts: Int = 3,
                                    _ work: () async throws -> T) async throws -> T {
        var pause = Duration.milliseconds(250)
        var last: Error = MKError(.unknown)
        for attempt in 1...attempts {
            do {
                return try await work()
            } catch {
                last = error
                guard attempt < attempts, isTransient(error) else { break }
                try? await Task.sleep(for: pause)
                pause = pause * 2
            }
        }
        throw last
    }

    private static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? MKError else {
            return (error as NSError).domain == NSURLErrorDomain
        }
        switch error.code {
        case .loadingThrottled, .serverFailure, .unknown: return true
        default: return false
        }
    }

    /// The refusal in words the leg screen can print.
    private static func describe(_ error: Error) -> String {
        guard let error = error as? MKError else { return error.localizedDescription }
        switch error.code {
        case .loadingThrottled: return "it was asked for too much at once"
        case .serverFailure: return "the Maps server did not answer"
        default: return error.localizedDescription
        }
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

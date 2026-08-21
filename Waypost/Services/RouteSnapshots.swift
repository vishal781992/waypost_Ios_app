import CoreImage
import MapKit
import UIKit

/// A trip's route map, drawn once and then kept.
///
/// The trip shelf used to carry a live `Map` per card. Every appearance re-streamed the
/// basemap tiles — scrolling the shelf, coming back to the tab, relaunching — and on a
/// road with no signal the cards came up blank, which is precisely where somebody is most
/// likely to be looking at them. A route map is not a map to explore: it is a picture of a
/// drive that will not change until the drive does. So it is rendered once through
/// `MKMapSnapshotter`, composited with its own route line, and written to disk.
///
/// **The trip is the key; its geometry is the receipt.** Each snapshot is stored under the
/// trip's id beside a fingerprint of what it was drawn from — the stops, the road, and the
/// size it was drawn at. Edit the trip and the fingerprint no longer matches, so the old
/// picture is deleted and a new one takes its place. Nothing accumulates, and nothing goes
/// stale without being noticed.
/// One stretch of a journey, and how it is travelled.
///
/// The plate used to take a single flat list of coordinates and one `routed` flag, which
/// between them can express exactly one line in one manner. A flown leg is three stretches
/// in two manners, so the flag becomes a list and the manner moves onto each stretch.
struct RouteLeg: Sendable {
    enum Mode: Sendable, Equatable {
        /// A road the router measured. Solid.
        case road
        /// A straight line standing in for a road nobody has measured yet. Dashed, and
        /// straight, which is the app's existing way of saying *roughly where you are
        /// going* rather than *this is the drive*.
        case provisional
        /// Flown. Drawn as an arc between two airports with a plane at its apex, and only
        /// ever carrying the two endpoints — the curve is the plate's, not the earth's.
        case air

        var tag: String {
            switch self {
            case .road: return "road"
            case .provisional: return "prov"
            case .air: return "air"
            }
        }
    }

    var mode: Mode
    var coordinates: [CLLocationCoordinate2D]

    init(_ mode: Mode, _ coordinates: [CLLocationCoordinate2D]) {
        self.mode = mode
        self.coordinates = coordinates
    }
}

actor RouteSnapshotStore {
    static let shared = RouteSnapshotStore()

    /// What the route is drawn in. Passed in rather than read here: the palette is
    /// `@MainActor` and these are its tokens, resolved by the view that asks.
    struct Style: Sendable {
        var line: UIColor
        var start: UIColor
        var stopFill: UIColor
        var stopStroke: UIColor
        /// The flown stretch and the plane on it — a step deeper than the road, so the two
        /// are told apart by colour as well as by shape.
        var air: UIColor
    }

    private let directory: URL
    private let manager = FileManager.default
    /// One render per trip at a time. Two cards asking at once for the same picture is
    /// two network snapshots for one file.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("route-maps", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func image(_ id: String) -> URL { directory.appendingPathComponent("\(id).jpg") }
    private func receipt(_ id: String) -> URL { directory.appendingPathComponent("\(id).fp") }

    // MARK: Asking

    /// The picture for this trip, from disk when it is still the right one and from
    /// MapKit when it is not. Nil only when the snapshot itself failed — offline, with
    /// nothing cached, which is the one case this cannot answer.
    func snapshot(
        id: String,
        key: String,
        region: MKCoordinateRegion,
        size: CGSize,
        scale: CGFloat,
        route: [RouteLeg],
        stops: [CLLocationCoordinate2D],
        airports: [CLLocationCoordinate2D] = [],
        style: Style
    ) async -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }

        let shape = route.map(\.mode.tag).joined(separator: ",")
        if let stored = cached(id: id, key: key, shape: shape) { return stored }

        if let running = inFlight[id] { return await running.value }
        let task = Task<UIImage?, Never> { [style] in
            await render(id: id, key: key, region: region, size: size, scale: scale,
                         route: route, stops: stops, airports: airports,
                         shape: shape, style: style)
        }
        inFlight[id] = task
        let result = await task.value
        inFlight[id] = nil
        return result
    }

    /// The stored picture, but only if it is still of this trip — and only if it is not a
    /// worse version of what is now available.
    ///
    /// The receipt is the trip's key plus whether the picture has the real road on it. The
    /// key is the stops and the size, deliberately *not* the road: the road is fetched
    /// fresh on every launch and arrives a moment after the card is drawn, so a key that
    /// included it disagreed with itself twice per launch and every trip re-rendered its
    /// map from the network every single time — the opposite of the point.
    ///
    /// A stored straight line is kept while the router is still being asked and replaced
    /// the moment the road answers. A stored road is never replaced by a straight line.
    private func cached(id: String, key: String, shape: String) -> UIImage? {
        guard let written = try? String(contentsOf: receipt(id), encoding: .utf8) else { return nil }
        let parts = written.split(separator: "\u{1}", maxSplits: 1).map(String.init)
        // A mismatch returns nil and nothing more. Deleting here looked tidier and was
        // the bug: the trip's origin resolves a beat after the card first draws, so every
        // launch briefly computed a one-stop key, deleted the good picture on the strength
        // of it, and re-rendered from the network once the real key arrived. A render
        // overwrites the file anyway; the only deletion that has to be explicit is a trip
        // that no longer exists, which is what `forget` is for.
        // A mismatch returns nil and nothing more. Deleting here looked tidier and was
        // the bug: the trip's origin resolves a beat after the card first draws, so every
        // launch briefly computed a one-stop key, deleted the good picture on the strength
        // of it, and re-rendered from the network once the real key arrived. A render
        // overwrites the file anyway; the only deletion that has to be explicit is a trip
        // that no longer exists, which is what `forget` is for.
        guard parts.first == key else { return nil }
        let stored = parts.count > 1 ? parts[1] : ""
        // The same rule as before, widened. A picture is kept while it is of the same
        // journey — the same stretches travelled the same ways — and replaced only when
        // more of it has been measured than the stored one had. A trip that turns from
        // driven to flown changes stretches, so it re-renders; a provisional road that
        // becomes a real one does not change stretches, and upgrades.
        guard Self.ground(stored) == Self.ground(shape) else { return nil }
        guard Self.measured(stored) >= Self.measured(shape) else { return nil }
        guard let data = try? Data(contentsOf: image(id)) else { return nil }
        return UIImage(data: data)
    }

    /// A shape with the difference between a measured road and a placeholder rubbed out,
    /// so the two compare equal and one can replace the other.
    private static func ground(_ shape: String) -> String {
        shape.replacingOccurrences(of: "prov", with: "gnd")
            .replacingOccurrences(of: "road", with: "gnd")
    }

    private static func measured(_ shape: String) -> Int {
        shape.split(separator: ",").filter { $0 == "road" }.count
    }

    // MARK: Drawing

    private func render(
        id: String, key: String, region: MKCoordinateRegion, size: CGSize,
        scale: CGFloat, route: [RouteLeg], stops: [CLLocationCoordinate2D],
        airports: [CLLocationCoordinate2D], shape: String, style: Style
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = scale
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        // The shelf is a light-mode surface whatever the phone is set to, and a snapshot
        // renders in the trait collection it is handed rather than the one on screen.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        guard let shot = await Self.take(options) else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        let composed = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // MapKit has no monochrome style, so the basemap is greyed here rather than by
            // a filter on the view — which is what lets the route be drawn in colour over
            // the top of it instead of being greyed along with it.
            (Self.desaturated(shot.image) ?? shot.image).draw(in: CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            // Ground first, then the air over it, then the planes over that. A flight
            // crossing a road it has nothing to do with should pass above it.
            for leg in route where leg.mode != .air {
                let line = leg.coordinates.map(shot.point(for:))
                guard line.count > 1 else { continue }
                cg.setStrokeColor(style.line.cgColor)
                cg.setLineWidth(leg.mode == .road ? 2.4 : 2)
                // A real road is drawn solid; the straight line standing in for one while
                // the router is still being asked stays dashed, which is the difference
                // between "this is the drive" and "this is roughly where you are going".
                if leg.mode == .provisional { cg.setLineDash(phase: 0, lengths: [5, 4]) }
                cg.addLines(between: line)
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
            }

            var planes: [(point: CGPoint, angle: CGFloat)] = []
            for leg in route where leg.mode == .air {
                guard let first = leg.coordinates.first, let last = leg.coordinates.last,
                      leg.coordinates.count > 1 else { continue }
                let (path, apex, angle) = Self.arc(from: shot.point(for: first),
                                                   to: shot.point(for: last))
                cg.setStrokeColor(style.air.cgColor)
                cg.setLineWidth(2.2)
                cg.setLineDash(phase: 0, lengths: [7, 5])
                cg.addPath(path)
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
                planes.append((apex, angle))
            }

            for plane in planes {
                let path = Self.planePath(at: plane.point, angle: plane.angle, size: 17)
                // Knocked out of the dashes it sits on, so the glyph reads as a plane
                // rather than as a thicker piece of the line.
                cg.setStrokeColor(style.stopFill.cgColor)
                cg.setLineWidth(3.4)
                cg.addPath(path)
                cg.strokePath()
                cg.setFillColor(style.air.cgColor)
                cg.addPath(path)
                cg.fillPath()
            }

            // Airports are diamonds and parks are circles. At eight points across, on a
            // greyed basemap, shape carries a distinction that colour cannot.
            for airport in airports.map(shot.point(for:)) {
                let path = Self.diamond(at: airport, radius: 5)
                cg.setFillColor(style.stopFill.cgColor)
                cg.addPath(path)
                cg.fillPath()
                cg.setStrokeColor(style.air.cgColor)
                cg.setLineWidth(1.6)
                cg.addPath(path)
                cg.strokePath()
            }

            for (index, stop) in stops.map(shot.point(for:)).enumerated() {
                let diameter: CGFloat = index == 0 ? 6 : 8
                let box = CGRect(x: stop.x - diameter / 2, y: stop.y - diameter / 2,
                                 width: diameter, height: diameter)
                cg.setFillColor(index == 0 ? style.start.cgColor : style.stopFill.cgColor)
                cg.fillEllipse(in: box)
                cg.setStrokeColor(style.stopStroke.cgColor)
                cg.setLineWidth(1.5)
                cg.strokeEllipse(in: box)
            }
        }

        if let data = composed.jpegData(compressionQuality: 0.9) {
            try? data.write(to: image(id), options: .atomic)
            let written = key + "\u{1}" + shape
            try? written.write(to: receipt(id), atomically: true, encoding: .utf8)
        }
        return composed
    }

    /// The curve a flight is drawn along, in the plate's own coordinates.
    ///
    /// It bulges toward the top of the picture whichever way the flight runs, which is the
    /// convention every flight map uses and is *not* a great circle: a great circle on this
    /// basemap's projection is a different shape, and drawing the real one would be a claim
    /// about a route no airline has published to this app. The arc says "flown", not "flown
    /// exactly here", and the leg card carries the honest wording.
    private static func arc(from a: CGPoint, to b: CGPoint) -> (CGPath, CGPoint, CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(1, hypot(dx, dy))
        let control = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - length * 0.22)

        let path = CGMutablePath()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)

        // Halfway along a quadratic is a quarter of one end, half the control point and a
        // quarter of the other; its tangent there runs parallel to the chord, which is why
        // the plane can take its heading from the two endpoints alone.
        let apex = CGPoint(x: 0.25 * a.x + 0.5 * control.x + 0.25 * b.x,
                           y: 0.25 * a.y + 0.5 * control.y + 0.25 * b.y)
        return (path, apex, atan2(dy, dx))
    }

    /// The plane, drawn nose-up about the origin and then turned to lie along its flight.
    private static func planePath(at point: CGPoint, angle: CGFloat, size: CGFloat) -> CGPath {
        let points: [CGPoint] = [
            .init(x: 0, y: -10), .init(x: 1.4, y: -6.5), .init(x: 1.4, y: -2.2),
            .init(x: 9.5, y: 2.4), .init(x: 9.5, y: 4.4), .init(x: 1.4, y: 2.0),
            .init(x: 1.4, y: 6.6), .init(x: 3.6, y: 8.2), .init(x: 3.6, y: 9.6),
            .init(x: 0, y: 8.6), .init(x: -3.6, y: 9.6), .init(x: -3.6, y: 8.2),
            .init(x: -1.4, y: 6.6), .init(x: -1.4, y: 2.0), .init(x: -9.5, y: 4.4),
            .init(x: -9.5, y: 2.4), .init(x: -1.4, y: -2.2), .init(x: -1.4, y: -6.5)
        ]
        // Nose-up means nose toward negative y, so a quarter turn past the heading points
        // it along the flight.
        let unit = size / 20
        let transform = CGAffineTransform(translationX: point.x, y: point.y)
            .rotated(by: angle + .pi / 2)
            .scaledBy(x: unit, y: unit)
        let path = CGMutablePath()
        path.addLines(between: points, transform: transform)
        path.closeSubpath()
        return path
    }

    private static func diamond(at point: CGPoint, radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: point.x, y: point.y - r), CGPoint(x: point.x + r, y: point.y),
            CGPoint(x: point.x, y: point.y + r), CGPoint(x: point.x - r, y: point.y)
        ])
        path.closeSubpath()
        return path
    }

    /// `MKMapSnapshotter` predates async, and its one-shot completion is exactly a
    /// continuation.
    private nonisolated static func take(_ options: MKMapSnapshotter.Options) async -> MKMapSnapshotter.Snapshot? {
        await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, _ in
                continuation.resume(returning: snapshot)
            }
        }
    }

    /// The design's grey basemap: saturation off, and a touch of contrast so the
    /// coastlines survive losing their colour.
    private nonisolated static func desaturated(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        filter.setValue(1.04, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: Housekeeping

    /// Forgets one trip's map — for a trip being deleted, where waiting for a fingerprint
    /// to disagree would mean waiting forever.
    func forget(id: String) {
        try? manager.removeItem(at: image(id))
        try? manager.removeItem(at: receipt(id))
    }

    func clear() {
        for file in (try? manager.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil)) ?? [] {
            try? manager.removeItem(at: file)
        }
    }
}

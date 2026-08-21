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
actor RouteSnapshotStore {
    static let shared = RouteSnapshotStore()

    /// What the route is drawn in. Passed in rather than read here: the palette is
    /// `@MainActor` and these are its tokens, resolved by the view that asks.
    struct Style: Sendable {
        var line: UIColor
        var start: UIColor
        var stopFill: UIColor
        var stopStroke: UIColor
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
        route: [CLLocationCoordinate2D],
        stops: [CLLocationCoordinate2D],
        routed: Bool,
        style: Style
    ) async -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }

        if let stored = cached(id: id, key: key, routed: routed) { return stored }

        if let running = inFlight[id] { return await running.value }
        let task = Task<UIImage?, Never> { [style] in
            await render(id: id, key: key, region: region, size: size,
                         scale: scale, route: route, stops: stops, routed: routed, style: style)
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
    private func cached(id: String, key: String, routed: Bool) -> UIImage? {
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
        let storedIsRouted = parts.count > 1 && parts[1] == "road"
        guard storedIsRouted || !routed else { return nil }
        guard let data = try? Data(contentsOf: image(id)) else { return nil }
        return UIImage(data: data)
    }

    // MARK: Drawing

    private func render(
        id: String, key: String, region: MKCoordinateRegion, size: CGSize,
        scale: CGFloat, route: [CLLocationCoordinate2D], stops: [CLLocationCoordinate2D],
        routed: Bool, style: Style
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
            let line = route.map(shot.point(for:))
            if line.count > 1 {
                cg.setStrokeColor(style.line.cgColor)
                cg.setLineWidth(routed ? 2.4 : 2)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                // A real road is drawn solid; the straight line standing in for one while
                // the router is still being asked stays dashed, which is the difference
                // between "this is the drive" and "this is roughly where you are going".
                if !routed { cg.setLineDash(phase: 0, lengths: [5, 4]) }
                cg.addLines(between: line)
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
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
            let written = key + "\u{1}" + (routed ? "road" : "straight")
            try? written.write(to: receipt(id), atomically: true, encoding: .utf8)
        }
        return composed
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

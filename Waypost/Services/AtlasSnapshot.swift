import CoreImage
import MapKit
import SwiftUI
import UIKit

/// The picture of the country on the profile, drawn once and then kept.
///
/// `AtlasBackdrop` is a map that nobody touches: it never pans, never zooms, and changes only
/// when a park is added to the rail. A live `Map` there would re-stream the basemap on
/// every appearance — scrolling the profile, coming back to the tab, relaunching — and come
/// up blank with no signal, which is the lesson `RouteSnapshots` already learned on the trip
/// shelf. So it is rendered through `MKMapSnapshotter`, the pins composited onto it, and
/// written to the caches directory.
///
/// **The visited set is the key.** The region never changes — it is the lower forty-eight,
/// always — so the only thing that can make the stored picture wrong is having stood
/// somewhere new. The receipt is that set and the size it was drawn at; collect a park and
/// the receipt disagrees, and the next draw replaces the file.
@MainActor
final class AtlasSnapshot {
    static let shared = AtlasSnapshot()

    /// The lower forty-eight, framed once. Alaska, Hawai‘i and the territories are
    /// deliberately outside it: at a hundred and fifty points there is no room for insets,
    /// and the count beside the card carries all sixty-two whatever the picture shows.
    /// `AtlasScreen` is a real map and pans to them.
    /// Computed and `nonisolated`, so a `View` can use it for the initial value of a
    /// camera without borrowing this class's actor to read a constant.
    nonisolated static var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.6, longitude: -98.4),
            span: MKCoordinateSpan(latitudeDelta: 25.5, longitudeDelta: 61)
        )
    }

    private let directory: URL
    private let manager = FileManager.default
    /// One render at a time per cut. The card and its own redraw asking together is two
    /// snapshots for one file; the card and the backdrop asking together are two different
    /// files and must not queue behind each other.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("atlas", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Drawn at three times the points it will occupy — sharp on every phone, and small
    /// enough on disk that the cache is one file rather than a folder to manage.
    nonisolated static var plateScale: CGFloat { 3 }

    /// Two pictures of the same country, at two shapes.
    ///
    /// The card's is the lower forty-eight's own proportions. The profile's ground is
    /// whatever shape the sheet leaves above it — taller than it is wide on most phones —
    /// and asking the snapshotter for that shape is the only way to fill it: a landscape
    /// picture in a portrait hole either letterboxes or crops half the country away.
    private func image(_ cut: String) -> URL { directory.appendingPathComponent("\(cut).jpg") }
    private func receipt(_ cut: String) -> URL { directory.appendingPathComponent("\(cut).fp") }

    // MARK: Asking

    /// The profile's ground, at the shape the sheet leaves for it: from disk while it is
    /// still of this collection and this shape, and from MapKit when it is not. Nil only
    /// when the snapshot itself failed with nothing cached.
    ///
    /// The size is the caller's because only the caller knows it — and it is part of the
    /// receipt, so a phone that renders at one shape and is then handed another (a rotation,
    /// a different device restoring the same cache) draws again rather than stretching what
    /// it has.
    func backdrop(visited: Set<String>, size: CGSize) async -> UIImage? {
        let asked = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard asked.width > 1, asked.height > 1 else { return nil }
        return await picture(cut: "backdrop", visited: visited, size: asked)
    }

    private func picture(cut: String, visited: Set<String>, size: CGSize) async -> UIImage? {
        let key = Self.key(visited: visited, size: size)
        if let stored = cached(key, cut: cut) { return stored }

        if let running = inFlight[cut] { return await running.value }
        let task = Task<UIImage?, Never> {
            await render(key: key, cut: cut, visited: visited,
                         size: size, scale: Self.plateScale)
        }
        inFlight[cut] = task
        let result = await task.value
        inFlight[cut] = nil
        return result
    }

    /// The collection and the shape it was drawn at. Sorted, because a set has no order and
    /// two runs of the same parks must produce the same receipt.
    private static func key(visited: Set<String>, size: CGSize) -> String {
        "v3|\(Int(size.width))x\(Int(size.height))|" + visited.sorted().joined(separator: ",")
    }

    private func cached(_ key: String, cut: String) -> UIImage? {
        guard let written = try? String(contentsOf: receipt(cut), encoding: .utf8), written == key,
              let data = try? Data(contentsOf: image(cut)) else { return nil }
        return UIImage(data: data)
    }

    // MARK: Drawing

    private func render(key: String, cut: String, visited: Set<String>,
                        size: CGSize, scale: CGFloat) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = Self.region
        options.size = size
        options.scale = scale
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        // The profile is a light surface whatever the phone is set to, and a snapshot
        // renders in the trait collection it is handed rather than the one on screen.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        guard let shot = await Self.take(options) else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        let composed = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Greyed here rather than by a filter on the view, which is what lets the pins
            // be drawn in colour on top of a basemap that has lost its own.
            (Self.desaturated(shot.image) ?? shot.image).draw(in: CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            cg.setLineCap(.round)

            // Not visited first, so a park you have stood in is never behind one you have
            // not. The country is dense enough in Utah for that to matter.
            let parks = NationalParks.all.map { (park: $0, visited: visited.contains($0.code)) }
            for entry in parks.sorted(by: { !$0.visited && $1.visited }) {
                let point = shot.point(for: CLLocationCoordinate2D(latitude: entry.park.lat,
                                                                  longitude: entry.park.lon))
                guard CGRect(origin: .zero, size: size).insetBy(dx: -6, dy: -6).contains(point) else { continue }
                // In the 400-point drawing space, shown at about 353 — so a touch bigger
                // than they want to look, or they arrive on the card smaller than drawn.
                let r: CGFloat = entry.visited ? 5.0 : 3.6
                let box = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                if entry.visited {
                    cg.setFillColor(UIColor(WP.lime).cgColor)
                    cg.fillEllipse(in: box)
                    cg.setStrokeColor(UIColor(WP.accent800).cgColor)
                    cg.setLineWidth(1.3)
                    cg.strokeEllipse(in: box)
                } else {
                    cg.setStrokeColor(UIColor(WP.text).withAlphaComponent(0.34).cgColor)
                    cg.setLineWidth(1.2)
                    cg.strokeEllipse(in: box)
                }
            }
        }

        if let data = composed.jpegData(compressionQuality: 0.9) {
            try? data.write(to: image(cut), options: .atomic)
            try? key.write(to: receipt(cut), atomically: true, encoding: .utf8)
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

    /// The design's grey basemap: saturation off, and a touch of contrast so the coastlines
    /// survive losing their colour. The same treatment the trip plates get, so the two
    /// pictures in the app read as one family.
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
}

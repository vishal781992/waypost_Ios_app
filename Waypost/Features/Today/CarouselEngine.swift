import SwiftUI
import UIKit

/// The rotation behind the home screen: which park is showing, when it changes, and what
/// the photograph underneath is doing to the type on top of it.
///
/// The playlist is every national park in the country, shuffled — sixty-three, not a
/// hand-picked five — so the home screen is a gallery rather than a loop you learn. Two
/// things follow from that and are the reason this class is shaped the way it is:
///
///  * **Only a window is mounted.** Sixty-three layers cross-fading is sixty-three views
///    SwiftUI keeps laid out. Three are mounted — the one showing, the one before, the one
///    next — which is exactly what a cross-fade plus a prefetch needs and no more.
///  * **Only a window is decoded.** A display-size photograph is about eighteen megabytes
///    once it is pixels. Holding all sixty-three would be over a gigabyte, so the decoded
///    images are evicted down to the mounted window and re-read from disk on the way back.
@MainActor
@Observable
final class CarouselEngine {

    /// One park in the rotation, with how far away it is when the phone will say.
    struct Slide: Identifiable, Hashable {
        var park: CuratedPark
        var miles: Int?

        var id: String { park.code }

        /// `212 mi · Utah`, or `You are here · Utah` when you are standing in it.
        var meta: String {
            let place = USStates.name(for: park.state) ?? park.state
            guard let miles else { return place }
            return miles == 0 ? "You are here · \(place)" : "\(miles) mi · \(place)"
        }
    }

    // MARK: Timing — the design's numbers, in one place

    /// Eight seconds, not five. Five was quick enough that the screen felt like it was
    /// working at you; at eight a photograph is something you look at and the drift has
    /// room to read as drift.
    static let dwell: Double = 8.0
    /// Long, and the only motion on the screen. The drift the design asked for is gone —
    /// a photograph that creeps while you read the name under it is a photograph you
    /// notice moving, which is the opposite of what a slow gallery is for. What is left is
    /// one dissolve: two and a half seconds, ease in and ease out, opacity and nothing
    /// else, so neither end of it has an edge you can see.
    static let crossfade: Double = 2.5

    /// Layers kept mounted either side of the one showing. One is the whole requirement:
    /// the outgoing photograph and the incoming one are both on screen during a fade, and
    /// the next is warmed while the current holds.
    static let windowRadius = 1

    /// The playlist: every national park, shuffled once per launch.
    private(set) var slides: [Slide] = []
    private(set) var index = 0

    /// The decoded photograph per park code, and the luminance of the strip the wordmark
    /// sits in. Images are evicted to the mounted window; luminance is a `Double` per park
    /// and is kept for all of them, so a photograph seen once never has to be measured
    /// again this launch.
    private(set) var images: [String: UIImage] = [:]
    private(set) var headerLuminance: [String: Double] = [:]

    /// Nil until somebody has switched the rotation on. Cancelled the moment the screen
    /// goes away, so photographs are never left animating behind another tab.
    private var ticker: Task<Void, Never>?

    var current: Slide? { slides.indices.contains(index) ? slides[index] : nil }

    /// The slides that are actually drawn — the one showing and its immediate neighbours.
    /// Deduplicated by park, so a playlist shorter than the window cannot hand `ForEach`
    /// the same identity twice.
    var mounted: [Slide] {
        let count = slides.count
        guard count > 0 else { return [] }
        var seen: Set<String> = []
        return (-Self.windowRadius...Self.windowRadius).compactMap { offset in
            let slide = slides[((index + offset) % count + count) % count]
            return seen.insert(slide.id).inserted ? slide : nil
        }
    }

    /// How hard the top scrim has to work under the wordmark, 0…1.
    ///
    /// The design fixes both scrims and says so — a scrim that breathes with the picture
    /// is a scrim you can see moving. This is the one exception, and it is deliberately
    /// one-directional: the type never lightens, the ground under it only ever deepens.
    /// A dark photograph gets nothing added; a snowfield gets the full ramp.
    var headerScrimBoost: Double {
        guard let code = current?.park.code, let lum = headerLuminance[code] else { return 0 }
        return ((lum - 0.42) / 0.36).clampedUnit
    }

    // MARK: Building the rotation

    /// Every national park in the country, in a random order, measured from wherever the
    /// phone last said it was.
    func fill(from fix: (lat: Double, lon: Double)?) {
        guard slides.isEmpty else { return }
        slides = NationalParks.all.shuffled().map { park in
            let miles = fix.map { Int((Geo.haversine($0, (park.lat, park.lon)) / 5).rounded()) * 5 }
            return Slide(park: CuratedPark(bundled: park), miles: miles)
        }
        loadWindow()
    }

    /// A fix arrived after the rotation was drawn. Fill the distances in; do not redraw
    /// the parks, or the photograph under the reader's thumb changes because the phone
    /// finally found a satellite.
    func refreshDistances(from fix: (lat: Double, lon: Double)?) {
        guard let fix else { return }
        slides = slides.map { slide in
            var updated = slide
            updated.miles = Int((Geo.haversine(fix, (slide.park.lat, slide.park.lon)) / 5).rounded()) * 5
            return updated
        }
    }

    // MARK: Running

    /// The screen is on and in front. Nothing rotates until this is true, and the ticker
    /// dies the moment it is false — backgrounded, or a tab away.
    func setRunning(_ running: Bool) {
        ticker?.cancel()
        ticker = nil
        guard running, slides.count > 1 else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.dwell))
                guard !Task.isCancelled, let self else { return }
                self.advance(by: 1, restartingTimer: false)
            }
        }
    }

    /// A hand on the photograph, or a dot tapped. Either way the eight seconds start again
    /// from here rather than finishing whatever was left of the last one.
    func go(to target: Int) {
        guard slides.indices.contains(target), target != index else { return }
        // Animated because a jump of more than one lands on a layer that was not mounted a
        // frame ago, and only a transition can fade that in. A step of one moves between
        // layers already on screen and would cross-fade with or without this.
        withAnimation(.easeInOut(duration: Self.crossfade)) {
            index = target
        }
        loadWindow()
        if ticker != nil { setRunning(true) }
    }

    func advance(by step: Int, restartingTimer: Bool = true) {
        guard !slides.isEmpty else { return }
        index = (index + step + slides.count) % slides.count
        loadWindow()
        if restartingTimer, ticker != nil { setRunning(true) }
    }

    // MARK: Photographs

    /// Resolve and decode everything in the window — which covers both the photograph
    /// showing and the one the cross-fade is about to need — then drop what has fallen
    /// out of it. A fade into a picture that has not arrived is the one failure everybody
    /// sees, and a gigabyte of decoded parks is the one nobody sees until the app is killed.
    private func loadWindow() {
        let keep = Set(mounted.map(\.id))
        images = images.filter { keep.contains($0.key) }
        for slide in mounted { load(slide) }
    }

    private func load(_ slide: Slide) {
        let code = slide.park.code
        guard images[code] == nil else { return }

        ParkPhotos.shared.load(slide.park)
        Task { [weak self] in
            guard let self else { return }
            // `load` resolves the URL asynchronously; wait for it rather than giving up on
            // the first miss, or a cold launch shows colour fields and never replaces them.
            for _ in 0..<40 where ParkPhotos.shared.photo(for: slide.park) == nil {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard let photo = ParkPhotos.shared.photo(for: slide.park),
                  let image = await PhotoStore.shared.fetch(photo.url, maxEdge: PhotoStore.displayEdge)
            else { return }
            // It may have scrolled out of the window during the fetch. Measuring is cheap
            // and permanent; holding the pixels is neither.
            self.headerLuminance[code] = Self.meanLuminance(of: image, in: Self.headerBand)
            guard self.mounted.contains(where: { $0.id == code }) else { return }
            self.images[code] = image
        }
    }

    /// Where the wordmark falls on the picture, in the image's own unit space: the top
    /// eighth, left two-thirds. Approximate — the photograph is `scaledToFill`, so the
    /// crop and the screen do not line up exactly — and approximate is enough to tell a
    /// snowfield from a canyon wall.
    private static let headerBand = CGRect(x: 0, y: 0, width: 0.66, height: 0.14)

    /// Rec. 709 luminance of one region, averaged by drawing it into a single pixel.
    nonisolated static func meanLuminance(of image: UIImage, in unit: CGRect) -> Double {
        guard let source = image.cgImage else { return 0.5 }
        let width = CGFloat(source.width), height = CGFloat(source.height)
        let crop = CGRect(x: unit.minX * width, y: unit.minY * height,
                          width: unit.width * width, height: unit.height * height).integral
        guard crop.width >= 1, crop.height >= 1,
              let piece = source.cropping(to: crop) else { return 0.5 }

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0.5 }

        context.interpolationQuality = .medium
        context.draw(piece, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = Double(pixel[0]) / 255, g = Double(pixel[1]) / 255, b = Double(pixel[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

// MARK: - Small helpers

extension USStates {
    /// `UT` → `Utah`. The bundled park list carries the code; the design writes the name.
    static func name(for code: String) -> String? {
        let wanted = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard let match = map.first(where: { $0.value == wanted }) else { return nil }
        return match.key
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

private extension Double {
    var clampedUnit: Double { min(max(self, 0), 1) }
}

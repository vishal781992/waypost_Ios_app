import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// A park, as much of one as a widget needs.
///
/// `Decodable` off the same `national-parks.json` the app reads — the extension carries
/// its own copy of the file, because a widget cannot reach into the app's bundle. Only the
/// four fields drawn here are declared; the decoder ignores the rest.
struct WidgetPark: Decodable, Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let full: String
    let state: String

    var id: String { code }

    static let all: [WidgetPark] = {
        guard let url = Bundle.main.url(forResource: "national-parks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parks = try? JSONDecoder().decode([WidgetPark].self, from: data)
        else { return [] }
        return parks
    }()
}

/// The photograph on a plate.
///
/// Kept on disk once fetched. A timeline is rebuilt from nothing every ninety minutes, and
/// a provider that goes to the network for every park every time is both wasteful and the
/// thing most likely to be killed halfway: WidgetKit gives a provider seconds, not
/// minutes, and takes the extension down when it overruns. After the first build almost
/// every park is answered from the cache, and only the ones that have not been seen cost
/// a request.
enum ParkPhoto {
    /// One size for both families. The medium plate is 338 points and draws at three
    /// times that on a Pro, but a widget is not a poster and 700 pixels of canyon is
    /// indistinguishable from 1,000 at that size — while being half the bytes and far
    /// likelier to exist. Wikimedia will not scale a thumbnail past the original, and a
    /// request for a width the file does not have comes back as nothing at all.
    static let side = 700

    /// Everything a timeline needs, fetched at once rather than one after another.
    ///
    /// This is the fix for a plate that never showed a photograph. Six parks fetched in a
    /// row is twelve round trips end to end, and with the timeouts they had it could run
    /// past two minutes — far past what a provider is given before it is killed. Killed
    /// halfway, no timeline is returned at all, and what is left on the screen is the
    /// placeholder: a park's name over its colours, exactly what was on the phone.
    static func prepare(_ parks: [WidgetPark]) async -> [String: UIImage] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for park in parks {
                group.addTask { (park.code, await bytes(for: park)) }
            }
            var out: [String: UIImage] = [:]
            for await (code, data) in group {
                if let data, let image = decode(data) { out[code] = image }
            }
            return out
        }
    }

    // MARK: One park

    private static func bytes(for park: WidgetPark) async -> Data? {
        if let kept = read(park.code) { return kept }
        guard let url = await source(for: park), let data = await download(url) else { return nil }
        write(data, for: park.code)
        return data
    }

    /// Wikipedia's summary endpoint: no key, no proxy, one image per article — the same
    /// source the app's own `ParkPhotos` falls back to, so a plate and a park screen show
    /// the same picture.
    private static func source(for park: WidgetPark) async -> URL? {
        let title = park.full.replacingOccurrences(of: " ", with: "_")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let endpoint = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else { return nil }

        guard let data = await download(endpoint),
              let object = try? JSONSerialization.jsonObject(with: data),
              let summary = object as? [String: Any],
              let thumbnail = (summary["thumbnail"] as? [String: Any])?["source"] as? String
        else { return nil }

        // The widened URL where the pattern allows it, and the thumbnail Wikipedia offered
        // where it does not. A small picture is better than none.
        return URL(string: widened(thumbnail) ?? thumbnail)
    }

    /// A Wikimedia thumbnail asked for at the size it will be drawn.
    ///
    /// Their thumbnail URLs carry the width in the last path component —
    /// `320px-Name.jpg` — so asking for a bigger one is a substitution rather than another
    /// request. The alternative is `originalimage`, which on a landscape photograph of a
    /// canyon can be twenty megabytes; a widget extension has tens of megabytes for
    /// everything it does.
    private static func widened(_ source: String) -> String? {
        guard let slash = source.lastIndex(of: "/") else { return nil }
        let file = source[source.index(after: slash)...]
        guard let px = file.range(of: "px-"),
              !file[..<px.lowerBound].isEmpty,
              file[..<px.lowerBound].allSatisfy(\.isNumber)
        else { return nil }
        return String(source[...slash]) + "\(side)px-" + String(file[px.upperBound...])
    }

    private static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        // Short on purpose. A provider that waits is a provider that is killed, and a
        // plate with yesterday's park on it beats a plate with none.
        request.timeoutInterval = 6
        // Wikimedia asks for a real user agent and refuses anonymous ones.
        request.setValue("ParkHop/1.0 (https://parkhop.us)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return data
    }

    /// Decoded straight to the size it is drawn at.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` decodes to the bound rather than decoding the
    /// whole picture and then shrinking it, which is the difference between a few
    /// megabytes and the extension being killed for using too many.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: On disk

    /// The extension's own caches directory. Not shared with the app — that would need the
    /// group entitlement, and this needs nothing.
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let folder = base.appendingPathComponent("park-plates", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(_ code: String) -> URL? {
        directory?.appendingPathComponent(code).appendingPathExtension("img")
    }

    private static func read(_ code: String) -> Data? {
        guard let file = file(code) else { return nil }
        return try? Data(contentsOf: file)
    }

    private static func write(_ data: Data, for code: String) {
        guard let file = file(code) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

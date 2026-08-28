import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// A park, as much of one as a widget needs.
///
/// `Decodable` off the same `national-parks.json` the app reads — the extension carries
/// its own copy of the file, because a widget cannot reach into the app's bundle. Only the
/// four fields drawn here are declared; the decoder ignores the rest.
struct WidgetPark: Decodable, Identifiable, Hashable {
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
enum ParkPhoto {
    /// Wikipedia's summary endpoint: no key, no proxy, one image per article — the same
    /// source the app's own `ParkPhotos` falls back to, so a widget and the park screen
    /// show the same picture.
    static func url(for park: WidgetPark, width: Int) async -> URL? {
        let title = park.full.replacingOccurrences(of: " ", with: "_")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let endpoint = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        // Wikimedia asks for a real user agent and refuses anonymous ones.
        request.setValue("ParkHop/1.0 (https://parkhop.us)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thumbnail = (object["thumbnail"] as? [String: Any])?["source"] as? String
        else { return nil }

        return URL(string: widened(thumbnail, to: width) ?? thumbnail)
    }

    /// A Wikimedia thumbnail asked for at the size it will be drawn.
    ///
    /// Their thumbnail URLs carry the width in the last path component —
    /// `320px-Name.jpg` — so asking for a bigger one is a substitution rather than another
    /// request. The alternative is `originalimage`, which on a landscape photograph of a
    /// canyon can be twenty megabytes; a widget extension has tens of megabytes for
    /// everything it does.
    ///
    /// Returns nil where the pattern does not match, and the caller keeps the thumbnail it
    /// was given: a small picture is better than none.
    private static func widened(_ source: String, to width: Int) -> String? {
        guard let slash = source.lastIndex(of: "/") else { return nil }
        let file = source[source.index(after: slash)...]
        guard let px = file.range(of: "px-"),
              !file[..<px.lowerBound].isEmpty,
              file[..<px.lowerBound].allSatisfy(\.isNumber)
        else { return nil }
        return String(source[...slash]) + "\(width)px-" + String(file[px.upperBound...])
    }

    /// Downloaded and decoded straight to the size it is drawn at.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` decodes to the bound rather than decoding the
    /// whole picture and then shrinking it, which is the difference between a few
    /// megabytes and the extension being killed for using too many.
    static func image(at url: URL, maxPixel: Int) async -> UIImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("ParkHop/1.0 (https://parkhop.us)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

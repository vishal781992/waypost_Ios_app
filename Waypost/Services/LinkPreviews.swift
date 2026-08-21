import LinkPresentation
import SwiftUI
import UIKit

/// What a pasted link turns out to be.
///
/// Somebody putting a Recreation.gov reservation or an AllTrails route on a trip's list
/// should see the page, not the address — `nps.gov/…/timed-entry.htm` says nothing you can
/// read at a glance. `LPMetadataProvider` is Apple's own unfurl, the one Messages and Notes
/// use, so a link on this list looks the way a link looks everywhere else on the phone.
///
/// **Fetched once, then kept.** Unfurling is slow and costs a request; a list redrawn on
/// every scroll would do it again each time, and on a road with no signal would show
/// nothing at all. Title, site and image go to disk keyed by the URL, so a card that has
/// been seen once reads offline for good.
@MainActor
@Observable
final class LinkPreviews {
    static let shared = LinkPreviews()

    struct Preview: Codable, Hashable {
        var title: String
        /// The site it came from — `nps.gov` — under the title.
        var host: String
        /// Filename of the picture on disk, when the page had one.
        var image: String?
    }

    private(set) var previews: [String: Preview] = [:]
    /// Links that answered with nothing. Kept so the card can say so rather than sitting
    /// on a spinner for ever, and cleared on relaunch so a page that was merely down gets
    /// another chance.
    private(set) var failed: Set<String> = []
    private var inFlight: Set<String> = []

    private let directory: URL
    private let manager = FileManager.default

    private init() {
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("link-previews", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        restore()
    }

    // MARK: Reading

    func preview(for url: URL) -> Preview? { previews[url.absoluteString] }
    func didFail(_ url: URL) -> Bool { failed.contains(url.absoluteString) }

    func image(for preview: Preview) -> UIImage? {
        guard let name = preview.image,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name))
        else { return nil }
        return UIImage(data: data)
    }

    // MARK: Fetching

    func load(_ url: URL) {
        let key = url.absoluteString
        guard previews[key] == nil, !inFlight.contains(key), !failed.contains(key) else { return }
        inFlight.insert(key)

        Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(key) }

            let provider = LPMetadataProvider()
            // Long enough for a slow park-service page, short enough that a dead link
            // does not leave a card spinning while somebody is trying to read a list.
            provider.timeout = 12

            guard let metadata = try? await provider.startFetchingMetadata(for: url) else {
                self.failed.insert(key)
                return
            }

            let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
            let title = metadata.title ?? url.lastPathComponent
            var imageName: String?
            if let image = await Self.image(from: metadata.imageProvider ?? metadata.iconProvider),
               let data = Self.downsized(image).jpegData(compressionQuality: 0.85) {
                let name = Self.filename(key)
                try? data.write(to: self.directory.appendingPathComponent(name), options: .atomic)
                imageName = name
            }

            self.previews[key] = Preview(title: title, host: host, image: imageName)
            self.persist()
        }
    }

    /// `NSItemProvider` predates async and hands back a `UIImage` through a completion.
    private nonisolated static func image(from provider: NSItemProvider?) async -> UIImage? {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// A card is a little over the width of the screen and 140 points tall. A page's
    /// og:image is routinely 1200 across, which is a megabyte to keep for a thumbnail.
    private nonisolated static func downsized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 900 else { return image }
        let scale = 900 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private nonisolated static func filename(_ key: String) -> String {
        let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(safe.suffix(110)) + ".jpg"
    }

    // MARK: Persistence

    private static let key = "parkhop-link-previews"

    private func persist() {
        if let data = try? JSONEncoder().encode(previews) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([String: Preview].self, from: data)
        else { return }
        previews = stored
    }
}

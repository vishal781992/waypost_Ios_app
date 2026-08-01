import UIKit

/// Park photographs, kept on the phone.
///
/// The pictures are the app. Waiting for one over a mountain road with two bars is the
/// difference between a screen that works and a screen that shrugs, so they are stored
/// rather than re-fetched.
///
/// **Sized to the screen, not to the source.** The widest thing this app ever draws a
/// photograph into is the full width of the display; Wikipedia's original of Delicate
/// Arch is 1.8 MB of pixels for a card 393 points across. Every image is therefore
/// re-encoded to at most 1400 points on its long edge before it is written down —
/// roughly 250 KB apiece, against a megabyte for the original.
///
/// **Capped, and honest about it.** Eighty megabytes, evicting whatever was read longest
/// ago. All sixty-two national parks at one photograph each is about fifteen; the cap is
/// there so that browsing hundreds of state parks cannot quietly fill a phone.
actor PhotoStore {
    static let shared = PhotoStore()

    /// The ceiling. Reached only by browsing far past the national parks.
    static let capBytes = 80 * 1024 * 1024
    /// The long edge everything is stored at: a little over the widest iPhone, so a
    /// photograph is never upscaled and never much larger than it needs to be.
    static let longEdge: CGFloat = 1400

    private let directory: URL
    private let manager = FileManager.default

    private init() {
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("park-photos", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Reading and writing

    private func file(for key: String) -> URL {
        directory.appendingPathComponent(Self.filename(key))
    }

    /// A stable, filesystem-safe name. The URL is the identity, so the same photograph
    /// found twice is stored once.
    private static func filename(_ key: String) -> String {
        let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(safe.suffix(120)) + ".jpg"
    }

    func image(for url: URL) -> UIImage? {
        let path = file(for: url.absoluteString)
        guard let data = try? Data(contentsOf: path) else { return nil }
        // Reading it counts as using it, which is what keeps it out of the eviction.
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        return UIImage(data: data)
    }

    /// Fetches, downsizes, stores and returns. A photograph already on disk is returned
    /// without touching the network.
    @discardableResult
    func fetch(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        var request = URLRequest(url: url)
        request.setValue(ParkDirectory.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await HTTP.session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let full = UIImage(data: data)
        else { return nil }

        let sized = Self.downsized(full)
        guard let jpeg = sized.jpegData(compressionQuality: 0.82) else { return sized }
        try? jpeg.write(to: file(for: url.absoluteString), options: .atomic)
        await evictIfNeeded()
        return sized
    }

    private static func downsized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longEdge else { return image }
        let scale = longEdge / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: Housekeeping

    private var files: [(url: URL, size: Int, used: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let contents = (try? manager.contentsOfDirectory(at: directory,
                                                         includingPropertiesForKeys: keys)) ?? []
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
    }

    var bytesUsed: Int { files.reduce(0) { $0 + $1.size } }

    /// Oldest-read first, until back under the cap.
    private func evictIfNeeded() {
        var all = files
        var total = all.reduce(0) { $0 + $1.size }
        guard total > Self.capBytes else { return }
        all.sort { $0.used < $1.used }
        for entry in all where total > Self.capBytes {
            try? manager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    func clear() {
        for entry in files { try? manager.removeItem(at: entry.url) }
    }
}

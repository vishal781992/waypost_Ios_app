import UIKit

/// Park photographs, kept on the phone.
///
/// The pictures are the app. Waiting for one over a mountain road with two bars is the
/// difference between a screen that works and a screen that shrugs, so they are stored
/// rather than re-fetched.
///
/// **Two sizes, because there are two jobs.** A 126×74 rail tile and a photograph filling
/// the whole display are not the same request, and storing one size for both meant either
/// a soft home screen or eight oversized decodes in a horizontal rail. `standardEdge` is
/// what a card or a tile needs; `displayEdge` is the home carousel's, a little over the
/// longest edge any current iPhone reports, so a full-bleed photograph is never upscaled.
/// The size is part of the cache key, so the two never overwrite each other.
///
/// **Capped, and honest about it.** Evicting whatever was read longest ago. The cap is
/// there so that browsing hundreds of state parks — or rotating through every national
/// park at display size — cannot quietly fill a phone.
actor PhotoStore {
    static let shared = PhotoStore()

    /// The ceiling. All sixty-three national parks at display size is about eighty of
    /// this, which leaves room for the tiles and for a long browse through state parks.
    static let capBytes = 220 * 1024 * 1024

    /// What a card, a tile or a rail thumbnail is stored at.
    static let standardEdge: CGFloat = 1400
    /// What the home carousel is stored at. The 17 Pro Max reports 1320×2868; this is a
    /// little over that, so no phone in service upscales its home screen.
    static let displayEdge: CGFloat = 2900

    private let directory: URL
    private let manager = FileManager.default

    private init() {
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("park-photos", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Reading and writing

    private func file(for key: String, edge: CGFloat) -> URL {
        directory.appendingPathComponent(Self.filename(key, edge: edge))
    }

    /// A stable, filesystem-safe name. The URL *and the size* are the identity, so the
    /// same photograph stored for a tile and for the carousel is two files rather than
    /// one that keeps being rewritten at whichever size was asked for last.
    private static func filename(_ key: String, edge: CGFloat) -> String {
        let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let suffix = edge == standardEdge ? "" : "-\(Int(edge))"
        return String(safe.suffix(120)) + suffix + ".jpg"
    }

    func image(for url: URL, maxEdge: CGFloat = PhotoStore.standardEdge) -> UIImage? {
        let path = file(for: url.absoluteString, edge: maxEdge)
        guard let data = try? Data(contentsOf: path) else { return nil }
        // Reading it counts as using it, which is what keeps it out of the eviction.
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        return UIImage(data: data)
    }

    /// Fetches, downsizes, stores and returns. A photograph already on disk at this size
    /// is returned without touching the network.
    @discardableResult
    func fetch(_ url: URL, maxEdge: CGFloat = PhotoStore.standardEdge) async -> UIImage? {
        if let cached = image(for: url, maxEdge: maxEdge) { return cached }

        var request = URLRequest(url: url)
        request.setValue(ParkDirectory.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await HTTP.session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let full = UIImage(data: data)
        else { return nil }

        let sized = Self.downsized(full, to: maxEdge)
        // A photograph filling the display shows its own compression; a 74pt tile does not.
        let quality: CGFloat = maxEdge > Self.standardEdge ? 0.92 : 0.82
        guard let jpeg = sized.jpegData(compressionQuality: quality) else { return sized }
        try? jpeg.write(to: file(for: url.absoluteString, edge: maxEdge), options: .atomic)
        evictIfNeeded()
        return sized
    }

    /// Never upscales: a source smaller than the target is stored as it came.
    private static func downsized(_ image: UIImage, to edge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > edge else { return image }
        let scale = edge / longest
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

import MapKit
import SwiftUI
import UIKit

/// A park, kept on the phone for a road with no signal.
///
/// This replaces a progress bar that counted to a hundred on a timer and stored nothing.
/// A pack now holds three files, and they are the three things a park screen cannot draw
/// without a network: what the park service publishes about the park, its photograph, and
/// a picture of the ground around it. The size on the row is the size on the disk.
///
/// **Application Support, not caches.** The caches directory is what iOS empties when a
/// phone runs short, and a pack emptied without being asked is worse than no pack — it is
/// a promise about a canyon with no signal, broken in the canyon. `PhotoStore` keeps its
/// copy in caches on purpose, because it can always be fetched again; a pack copies the
/// picture out so that eviction cannot reach it.
@MainActor
@Observable
final class ParkPack {
    static let shared = ParkPack()

    /// What is on the phone, by park code, with what it weighs.
    struct Stored: Identifiable, Hashable {
        var code: String
        var name: String
        var bytes: Int
        var packedAt: Date
        /// Which of the three parts actually landed. A pack whose photograph could not be
        /// fetched is still worth keeping — it is the park service's own record that a
        /// park screen is unreadable without.
        var parts: [String]
        var id: String { code }

        var sizeLabel: String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    /// Where a download has got to: nil when nothing is running for that park.
    private(set) var progress: [String: Double] = [:]
    /// What is on disk, read once at launch and kept in step with every write.
    private(set) var stored: [String: Stored] = [:]
    /// Why a pack could not be made, by code — shown on the row that failed.
    private(set) var failures: [String: String] = [:]

    private var running: [String: Task<Void, Never>] = [:]
    private let manager = FileManager.default
    private let directory: URL

    private init() {
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("park-packs", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // A pack is the user's data, not a cache. Telling the system so is what stops it
        // being uploaded to iCloud and, on some devices, being reclaimed under pressure.
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        reload()
    }

    // MARK: What is here

    private func folder(_ code: String) -> URL {
        directory.appendingPathComponent(code, isDirectory: true)
    }

    /// Reads the directory. Cheap — one listing and a size per park — and it is the only
    /// thing that decides whether a park counts as packed, so what the app says is on the
    /// phone is what is on the phone.
    func reload() {
        var found: [String: Stored] = [:]
        let codes = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        for code in codes {
            let folder = folder(code)
            guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            // The record is what makes a pack a pack. A folder with only a picture in it is
            // a half-written download, and is treated as absent rather than as a pack that
            // will disappoint somebody later.
            guard files.contains(where: { $0.lastPathComponent == Self.recordFile }) else { continue }

            var bytes = 0
            var newest = Date.distantPast
            var parts: [String] = []
            for file in files {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                bytes += values?.fileSize ?? 0
                if let modified = values?.contentModificationDate, modified > newest { newest = modified }
                if let part = Self.partName(file.lastPathComponent) { parts.append(part) }
            }
            let name = (try? String(contentsOf: folder.appendingPathComponent(Self.nameFile), encoding: .utf8)) ?? code
            found[code] = Stored(code: code, name: name, bytes: bytes,
                                 packedAt: newest, parts: parts.sorted())
        }
        stored = found
    }

    private static let recordFile = "record.json"
    private static let photoFile = "photo.jpg"
    private static let mapFile = "map.jpg"
    private static let nameFile = "name.txt"

    private static func partName(_ file: String) -> String? {
        switch file {
        case recordFile: return "Park record"
        case photoFile: return "Photograph"
        case mapFile: return "Map"
        default: return nil
        }
    }

    var isEmpty: Bool { stored.isEmpty }
    var totalBytes: Int { stored.values.reduce(0) { $0 + $1.bytes } }
    var totalLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    /// Newest first — the pack somebody just made is the one they are looking for.
    var list: [Stored] { stored.values.sorted { $0.packedAt > $1.packedAt } }

    func has(_ code: String) -> Bool { stored[code] != nil }
    func isDownloading(_ code: String) -> Bool { running[code] != nil }

    // MARK: Reading a pack

    /// The park service's record, as it was when the pack was made.
    ///
    /// The park screen reads this when the network does not answer. It carries the date it
    /// was fetched, because a fee from three months ago is worth showing and worth saying
    /// the age of — it is not worth showing as though it arrived just now.
    func record(for code: String) -> ParkFacts.Facts? {
        guard let data = try? Data(contentsOf: folder(code).appendingPathComponent(Self.recordFile)) else { return nil }
        return try? JSONDecoder().decode(ParkFacts.Facts.self, from: data)
    }

    func photo(for code: String) -> UIImage? {
        guard let data = try? Data(contentsOf: folder(code).appendingPathComponent(Self.photoFile)) else { return nil }
        return UIImage(data: data)
    }

    func map(for code: String) -> UIImage? {
        guard let data = try? Data(contentsOf: folder(code).appendingPathComponent(Self.mapFile)) else { return nil }
        return UIImage(data: data)
    }

    // MARK: Making one

    /// Fetches the three parts and writes them. Progress is the fraction of them done —
    /// not a timer, so a slow connection reads as slow rather than as finished.
    func download(_ park: CuratedPark) {
        guard running[park.code] == nil else { return }
        failures[park.code] = nil
        progress[park.code] = 0.02

        running[park.code] = Task { [weak self] in
            guard let self else { return }
            defer {
                running[park.code] = nil
                progress[park.code] = nil
                reload()
            }

            let folder = folder(park.code)
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? park.name.write(to: folder.appendingPathComponent(Self.nameFile),
                                 atomically: true, encoding: .utf8)

            // 1 · The record. The one part a pack cannot do without, so a failure here
            // ends the download and says why rather than leaving a folder that looks
            // like a pack and answers nothing.
            switch await ParkFacts.shared.fetch(park) {
            case .loaded(let facts):
                if let data = try? JSONEncoder().encode(facts) {
                    try? data.write(to: folder.appendingPathComponent(Self.recordFile), options: .atomic)
                }
            case .notCovered:
                failures[park.code] = "The park service has no record for \(park.name)."
                try? manager.removeItem(at: folder)
                return
            case .failed(let why):
                failures[park.code] = why
                try? manager.removeItem(at: folder)
                return
            case .idle, .loading:
                failures[park.code] = "The park service did not answer."
                try? manager.removeItem(at: folder)
                return
            }
            guard !Task.isCancelled else { return }
            progress[park.code] = 0.45

            // 2 · The photograph, copied out of the cache the rest of the app reads from —
            // or fetched if it is not there. Either way the pack gets its own copy, where
            // the system cannot reclaim it.
            ParkPhotos.shared.load(park)
            if let url = ParkPhotos.shared.photo(for: park)?.url,
               let image = await PhotoStore.shared.fetch(url),
               let data = image.jpegData(compressionQuality: 0.86) {
                try? data.write(to: folder.appendingPathComponent(Self.photoFile), options: .atomic)
            }
            guard !Task.isCancelled else { return }
            progress[park.code] = 0.75

            // 3 · The ground around the park. Ten miles across, which is the gateway town
            // and the road in — the two things somebody with no signal is trying to work
            // out from a car park.
            if let map = await Self.mapImage(park), let data = map.jpegData(compressionQuality: 0.8) {
                try? data.write(to: folder.appendingPathComponent(Self.mapFile), options: .atomic)
            }
            progress[park.code] = 1
        }
    }

    func cancel(_ code: String) {
        running[code]?.cancel()
        running[code] = nil
        progress[code] = nil
    }

    /// Removes a pack, and says how much came back.
    @discardableResult
    func remove(_ code: String) -> Int {
        cancel(code)
        let freed = stored[code]?.bytes ?? 0
        try? manager.removeItem(at: folder(code))
        reload()
        return freed
    }

    @discardableResult
    func removeAll() -> Int {
        let freed = totalBytes
        for code in stored.keys { cancel(code) }
        try? manager.removeItem(at: directory)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        return freed
    }

    // MARK: Drawing the map

    private static func mapImage(_ park: CuratedPark) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: park.lat, longitude: park.lon),
            latitudinalMeters: 16_000, longitudinalMeters: 16_000
        )
        options.size = CGSize(width: 700, height: 700)
        options.scale = 2
        options.showsBuildings = false
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }
}

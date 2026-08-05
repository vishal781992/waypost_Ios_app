import SwiftUI

/// Real photographs for the park cards.
///
/// The design fades a photograph in behind every park tile — full-bleed on the heroes,
/// blurred behind the smaller ones — over the colour field, which stays as the thing you
/// see until a picture arrives.
///
/// Two sources, in order:
///
///  1. **The NPS API**, through the proxy, which is where the design's photographs come
///     from. It returns `images[].url` with a credit and an alt text per park.
///  2. **Wikipedia's REST summary**, which needs no key and no proxy. It is the only
///     reason a photograph appears at all on a device that has not been given the proxy,
///     and the park screen names it, so a Wikipedia picture is never passed off as the
///     park service's own.
///
/// Whichever answers, the credit travels with the URL — a photograph with no attribution
/// is not shown.
@MainActor
@Observable
final class ParkPhotos {
    static let shared = ParkPhotos()

    struct Photo: Hashable {
        var url: URL
        var credit: String
        /// Where it came from, for the source line.
        var source: String
    }

    private(set) var photos: [String: Photo] = [:]
    private var inFlight: Set<String> = []
    fileprivate var isPrefetching = false
    private let failures = FailureLog()
    private var proxy: ProxyConfig { ProxyConfig() }

    private init() { restore() }

    /// Commons serves a file by name through `Special:FilePath`, which redirects to the
    /// real upload URL and will resize on the way — the same address the web app builds.
    static func commonsURL(_ file: String, width: Int = 1000) -> URL? {
        guard !file.isEmpty,
              let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string:
            "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=\(width)")
    }

    func photo(for park: CuratedPark) -> Photo? { photos[park.code] }

    /// Asks for a park's photograph once. Repeat calls are free, and a park that has no
    /// photograph anywhere is not asked about again this launch.
    func load(_ park: CuratedPark) {
        guard photos[park.code] == nil, !inFlight.contains(park.code) else { return }

        // The bundled row names a photograph for 1,821 of the state parks, on Wikimedia
        // Commons — the same picture the web app draws. No search needed, no request to
        // find it, and it is the right park rather than the nearest name match.
        if let file = park.photoFile, let url = Self.commonsURL(file) {
            photos[park.code] = Photo(url: url,
                                      credit: "Wikimedia Commons",
                                      source: "Wikimedia Commons")
            persist()
            return
        }
        inFlight.insert(park.code)

        Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(park.code) }

            if let fromNPS = await npsPhoto(park) {
                photos[park.code] = fromNPS
                persist()
                return
            }
            if let fromWikipedia = await wikipediaPhoto(park) {
                photos[park.code] = fromWikipedia
                persist()
            }
        }
    }

    /// Fills the store with a photograph for every national park in the country.
    ///
    /// Sixty-two pictures at roughly 250 KB each is about fifteen megabytes — worth
    /// spending once, on wi-fi, so that every park screen opens instantly afterwards and
    /// keeps working with no signal. It runs at most once a fortnight, four at a time so
    /// it never competes with whatever the user is actually looking at, and only while
    /// the connection is unmetered.
    func prefetchNationalParks() {
        let key = "parkhop-photo-prefetch"
        let last = UserDefaults.standard.object(forKey: key) as? Date
        if let last, Date().timeIntervalSince(last) < 14 * 24 * 3600 { return }
        guard !isPrefetching else { return }
        isPrefetching = true

        Task.detached(priority: .background) {
            defer { Task { @MainActor in ParkPhotos.shared.isPrefetching = false } }

            // `NWPathMonitor` has not necessarily settled the instant the app launches,
            // and an unsettled path is not the same as a metered one. Give it a moment
            // before deciding to spend somebody's data — or not to.
            for _ in 0..<5 where !Network.isUnmetered {
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard Network.isUnmetered else { return }

            let parks = await MainActor.run { NationalParks.all.map { CuratedPark(bundled: $0) } }
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for park in parks {
                    if running >= 4 { await group.next(); running -= 1 }
                    group.addTask { await ParkPhotos.shared.prefetch(park) }
                    running += 1
                }
            }
            // Recorded on the way out, not on the way in: a run that never happened
            // should not stop the next one for a fortnight.
            UserDefaults.standard.set(Date(), forKey: key)
        }
    }

    /// One park: find the photograph if it is not known, then put it on disk.
    fileprivate func prefetch(_ park: CuratedPark) async {
        if photos[park.code] == nil {
            if let found = await wikipediaPhoto(park) {
                photos[park.code] = found
                persist()
            }
        }
        guard let photo = photos[park.code] else { return }
        await PhotoStore.shared.fetch(photo.url)
    }

    // MARK: Sources

    /// The park service's own photographs, through the proxy that holds the key.
    private func npsPhoto(_ park: CuratedPark) async -> Photo? {
        guard proxy.isConnected,
              let request = proxy.request("/nps", [
                  "endpoint": "parks", "parkCode": park.code, "fields": "images",
              ]) else { return nil }
        do {
            let object = try await HTTP.any(request)
            let rows = object["data"] as? [[String: Any]] ?? []
            let images = rows.first?["images"] as? [[String: Any]] ?? []
            // The design picks at random so a park looks different between visits; the
            // park code seeds it so it at least holds still within one.
            guard !images.isEmpty else { return nil }
            let index = abs(park.code.hashValue) % images.count
            let image = images[index]
            guard let url = safeURL(image["url"] as? String) else { return nil }
            let credit = (image["credit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Photo(url: url, credit: credit ?? "NPS", source: "NPS")
        } catch {
            failures.note("park photographs (NPS)", error)
            return nil
        }
    }

    /// Wikipedia's summary endpoint: no key, no proxy, one image per article.
    private func wikipediaPhoto(_ park: CuratedPark) async -> Photo? {
        let title = park.full.replacingOccurrences(of: " ", with: "_")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        // Wikimedia asks for a real user agent and refuses anonymous ones.
        request.setValue("ParkHop/1.0 (https://parkhop.us)", forHTTPHeaderField: "User-Agent")

        do {
            let object = try await HTTP.any(request)
            let original = (object["originalimage"] as? [String: Any])?["source"] as? String
            let thumbnail = (object["thumbnail"] as? [String: Any])?["source"] as? String
            guard let photoURL = safeURL(original ?? thumbnail) else { return nil }
            return Photo(url: photoURL, credit: "Wikipedia", source: "Wikipedia")
        } catch {
            failures.note("park photographs (Wikipedia)", error)
            return nil
        }
    }

    // MARK: Persistence
    //
    // Only the resolved URLs are kept here. The pictures themselves live in PhotoStore,
    // downsized to what the screen can show and capped, so a phone cannot quietly fill up
    // with photographs of state parks somebody scrolled past once.

    private struct Stored: Codable {
        var url: URL
        var credit: String
        var source: String
    }

    private static let key = "parkhop-photos"

    private func persist() {
        let stored = photos.mapValues { Stored(url: $0.url, credit: $0.credit, source: $0.source) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([String: Stored].self, from: data) else { return }
        photos = stored.mapValues { Photo(url: $0.url, credit: $0.credit, source: $0.source) }
    }
}

// MARK: - The view

/// A park's photograph over its colour field.
///
/// The colour field is not a placeholder to be replaced — it is what the park looks like
/// until a photograph arrives, and what it goes on looking like if none does. The picture
/// cross-fades in over it, exactly as the design's `photoOn` opacity does.
struct ParkImage: View {
    var park: CuratedPark
    /// The design blurs the photograph behind the smaller tiles so the name stays legible.
    var blur: CGFloat = 0
    var saturation: Double = 1
    var showsScrim: Bool = true
    var topLight: Bool = true

    @State private var loaded = false

    private var photo: ParkPhotos.Photo? { ParkPhotos.shared.photo(for: park) }

    var body: some View {
        // The photograph and its scrim are overlays rather than stacked siblings on
        // purpose: `scaledToFill` reports a size larger than the space it was offered, and
        // a ZStack would grow to match it — which pushed the whole page sideways. An
        // overlay draws into the colour field's frame without ever changing it.
        BlobField(colors: park.c.map { Color(css: $0) }, scrim: showsScrim, topLight: topLight)
            .overlay {
                if let photo {
                    // From the phone if it is there; from the network once, and from the
                    // phone every time after that.
                    CachedPhoto(url: photo.url, blur: blur, saturation: saturation)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                // The scrim goes back over the photograph, or white type stops reading.
                if photo != nil, showsScrim {
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x181008, opacity: 0.5), location: 0),
                            .init(color: Color(hex: 0x181008, opacity: 0.14), location: 0.56),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .bottom, endPoint: .top
                    )
                }
            }
            .clipped()
            .task(id: park.code) { ParkPhotos.shared.load(park) }
    }
}


/// One photograph, read from the store.
///
/// `AsyncImage` fetches straight from the network every time a view is rebuilt and keeps
/// whatever it gets in memory only. This goes through `PhotoStore` instead: sized down
/// once, written to disk, and read from there afterwards — which is what makes a park
/// screen work on a road with two bars, and what makes the same picture cost nothing the
/// second time.
struct CachedPhoto: View {
    var url: URL
    var blur: CGFloat = 0
    var saturation: Double = 1

    @State private var image: UIImage?

    var body: some View {
        // `Color.clear` rather than a bare conditional: a view that renders as empty is
        // an `EmptyView`, and SwiftUI never runs `.task` on one — which is exactly how
        // every photograph in the app quietly stopped loading.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: blur, opaque: false)
                        .saturation(saturation)
                        .scaleEffect(blur > 0 ? 1.2 : 1)   // hides the blur's soft edge
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.45), value: image != nil)
            .task(id: url) { image = await PhotoStore.shared.fetch(url) }
    }
}

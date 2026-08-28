import SwiftUI
import WidgetKit

/// Named for what it holds, not for the target it is in.
///
/// A type sharing its module's name makes every `WaypostWidgets.Something` ambiguous — the
/// same trap the Appwrite SDK set, where a `Backend` had to stop being called `Appwrite`.
@main
struct ParkHopWidgets: WidgetBundle {
    var body: some Widget { ParkPlateWidget() }
}

// MARK: - What one plate shows

struct ParkEntry: TimelineEntry {
    var date: Date
    var park: WidgetPark
    /// Fetched when the timeline was built. `nil` on a phone that was offline then, and
    /// the plate draws the park's own colours instead of an empty rectangle.
    var photo: UIImage?
    var isSaved: Bool
}

// MARK: - The timeline

struct ParkPlateProvider: TimelineProvider {
    /// How many parks one timeline carries, and how long each is up for.
    ///
    /// Not "every unlock" — WidgetKit gives no unlock to hang anything on. A widget draws
    /// the entry whose date has passed, so the picture changes on a clock rather than on a
    /// gesture. Four parks twenty minutes apart is a new one most times the phone is
    /// picked up, at a dozen or so timeline builds a day, which is well inside the refresh
    /// budget iOS allows.
    ///
    /// Four is a memory number and a time one. Every photograph in a timeline is held at
    /// once, and every one not already on disk is a request the provider has to finish
    /// before WidgetKit stops waiting and takes the extension down.
    private static let count = 4
    private static let step: TimeInterval = 20 * 60

    func placeholder(in context: Context) -> ParkEntry {
        ParkEntry(date: Date(), park: Self.fallback, photo: nil, isSaved: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ParkEntry) -> Void) {
        // The gallery, where a widget is being chosen and must draw at once: no network.
        // Everywhere else a snapshot is a real plate — it is what is shown while a timeline
        // is being built, and a photographless one there was the plate arriving as a
        // coloured rectangle every time.
        guard !context.isPreview else {
            completion(ParkEntry(date: Date(), park: Self.fallback, photo: nil, isSaved: false))
            return
        }
        Task {
            let park = Self.rota(count: 1).first ?? Self.fallback
            let photos = await ParkPhoto.prepare([park])
            completion(ParkEntry(date: Date(), park: park, photo: photos[park.code],
                                 isSaved: SavedParks.contains(park.code)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ParkEntry>) -> Void) {
        Task {
            let saved = SavedParks.codes()
            let parks = Self.rota(count: Self.count)

            // Every picture at once rather than one after another. Parks fetched in a row
            // is two round trips each end to end, which ran past what a provider is given
            // before it is killed — and a provider killed halfway returns no timeline at
            // all, which is why the plate stayed on its colours.
            let photos = await ParkPhoto.prepare(parks)

            var entries: [ParkEntry] = []
            var when = Date()
            for park in parks {
                entries.append(ParkEntry(date: when, park: park, photo: photos[park.code],
                                         isSaved: saved.contains(park.code)))
                when = when.addingTimeInterval(Self.step)
            }

            // An empty register would mean the bundled file did not ship. Draw something
            // and ask again rather than handing WidgetKit a timeline with nothing in it.
            let timeline = entries.isEmpty ? [placeholder(in: context)] : entries
            completion(Timeline(entries: timeline, policy: .after(when)))
        }
    }

    /// The parks this timeline will show, in an order that moves between builds.
    ///
    /// Started from the register's own order and it showed Acadia every time: a timeline
    /// is rebuilt from nothing, so anything derived only from the list is the same list.
    /// The day and the hour move the starting point, and the stride is coprime with the
    /// count so a run never repeats a park inside one timeline.
    private static func rota(count: Int) -> [WidgetPark] {
        let all = WidgetPark.all
        guard !all.isEmpty else { return [] }
        guard all.count > count else { return all }

        let clock = Int(Date().timeIntervalSince1970 / (15 * 60))
        let stride = 7
        return (0..<count).map { all[((clock + $0 * stride) % all.count + all.count) % all.count] }
    }

    /// What is drawn before anything has been read: the first park in the register, or a
    /// stand-in on the impossible day the file is missing.
    private static var fallback: WidgetPark {
        WidgetPark.all.first
            ?? WidgetPark(code: "acad", name: "Acadia", full: "Acadia National Park", state: "ME")
    }
}

// MARK: - The widget

struct ParkPlateWidget: Widget {
    static let kind = "ParkPlate"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ParkPlateProvider()) { entry in
            ParkPlateView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        // The plate paints its own edges. Without this the system insets everything —
        // including the photograph, which is the black border it used to sit inside.
        .contentMarginsDisabled()
        .configurationDisplayName("A park")
        .description("A national park, changing through the day. Tap to open it.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

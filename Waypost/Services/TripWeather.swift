import SwiftUI

/// Weather for the days a trip actually happens on.
///
/// The park screen asks for one park on one date. A trip route asks for every leg and
/// every park day at once, and asks again every time the tab is drawn — so the answers are
/// held here, keyed by place and date, and each is fetched once per launch.
///
/// Beyond Open-Meteo's sixteen-day horizon `WeatherService` already falls back to ten years
/// of the same calendar window, flagged `isNormals`. That is what most trips get, because
/// most trips are planned further out than a fortnight, and the row draws it differently:
/// a typical August is not a forecast for next Tuesday and must not look like one.
@MainActor
@Observable
final class TripWeather {
    static let shared = TripWeather()

    private var days: [String: WeatherDay] = [:]
    private var asked: Set<String> = []
    /// Places and dates nothing answered about. Kept apart from `asked`, which is emptied
    /// of a failed key so the next launch can try again — without this second set, given
    /// up and never-asked are the same state, and the row cannot tell a forecast that is
    /// coming from one that is not.
    private var gaveUp: Set<String> = []
    private let failures = FailureLog()

    private init() {}

    private static let iso: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Place and date together. Two parks on the same day are two answers, and one park on
    /// two days is two answers.
    private func key(_ lat: Double, _ lon: Double, _ date: Date) -> String {
        String(format: "%.3f,%.3f@", lat, lon) + Self.iso.string(from: date)
    }

    func day(lat: Double, lon: Double, date: Date) -> WeatherDay? {
        days[key(lat, lon, date)]
    }

    /// Whether a forecast for this place and date is still expected.
    ///
    /// True before the row has even asked, which is the point: `.task` runs a frame after
    /// the row is first drawn, so a reservation that waited for `asked` to fill would
    /// still let the column go from nothing to thirty-four points — the jump it exists to
    /// prevent, one frame later. Every row that draws a glyph asks for it on appear, so
    /// not-yet-asked and in-flight are the same thing to the layout.
    ///
    /// False once something has come back, and false once nothing has: a request that
    /// failed collapses the column rather than leaving a grey block breathing on the row
    /// for the rest of the session.
    func isAsking(lat: Double, lon: Double, date: Date) -> Bool {
        let id = key(lat, lon, date)
        return days[id] == nil && !gaveUp.contains(id)
    }

    /// Asks once per place-and-date, ever. Repeat calls — and there are many, because
    /// every redraw of the route calls this for every row — cost nothing.
    func load(lat: Double, lon: Double, date: Date) {
        let id = key(lat, lon, date)
        guard days[id] == nil, !asked.contains(id) else { return }
        asked.insert(id)
        // Asking again after a failure. Until this answers, the row is waiting rather
        // than given up on, and its column holds its place again.
        gaveUp.remove(id)

        Task { [weak self] in
            guard let self else { return }
            let iso = Self.iso.string(from: date)
            if let day = await WeatherService(failures: failures).forecast(lat: lat, lon: lon, iso: iso) {
                self.days[id] = day
            } else {
                // Nothing answered. Let it be asked again next launch rather than never —
                // and stop the row holding a column open for an answer that is not coming.
                self.asked.remove(id)
                self.gaveUp.insert(id)
            }
        }
    }
}

// MARK: - The glyph

/// One day's sky and high, as a symbol over a number.
///
/// Drawn only when something answered. An absent forecast draws nothing at all rather than
/// a question mark or a zero — "0°" in this spot used to read as a freezing day rather
/// than as no reading, which is the mistake this whole column exists to avoid repeating.
struct WeatherGlyph: View {
    var day: WeatherDay?
    /// The weekday letter over the symbol, for a park being spent more than one day in.
    var caption: String?
    var size: CGFloat = 19
    /// Whether the forecast is still on its way. The column holds its width while it is,
    /// and holds nothing when the answer was that there is no answer.
    var awaiting: Bool = false

    var body: some View {
        // A `Group` with a real else-branch, rather than a bare `if`. A view that renders
        // as empty *is* an `EmptyView`, and SwiftUI never runs `.task` on one — so a glyph
        // waiting on its forecast never asked for it and waited forever, the same trap
        // `CachedPhoto` documents. `Color.clear` at zero size keeps the modifier alive
        // while taking no room, and — unlike wrapping the whole thing in an overlay —
        // leaves the drawn glyph free to size itself, which two side by side need.
        Group {
            if let day, let condition = day.condition {
                loaded(day, condition)
            } else if awaiting {
                // One forecast per row, asked for the moment the row appears — a count
                // this screen knows before it asks. Without the reservation the glyph
                // arrives thirty-four points wide into a row whose text column then has
                // that much less to wrap in, so the sentence under the leg reflows and
                // the row changes height a second after it was drawn.
                waiting
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    /// The glyph's own footprint, in the page's paper. Sized off `size` rather than off a
    /// measured number, so the two stay together if the glyph is ever drawn larger.
    private var waiting: some View {
        VStack(spacing: 1) {
            if caption != nil { SkeletonBar(width: 14, height: 8, corner: 2) }
            SkeletonBar(width: 21, height: size - 2, corner: 5)
                .frame(height: size + 3)
            SkeletonBar(width: 17, height: 8, corner: 2)
        }
        .frame(minWidth: 34)
        .skeletonBreath()
    }

    private func loaded(_ day: WeatherDay, _ condition: WeatherCondition) -> some View {
        Group {
            VStack(spacing: 1) {
                if let caption {
                    Text(caption.uppercased())
                        .font(WP.body(9.5)).tracking(0.6)
                        .foregroundStyle(WP.text.opacity(0.45))
                }
                Image(systemName: condition.symbol)
                    .font(.system(size: size, weight: .regular))
                    // Monochrome, not hierarchical or multicolour: the sky on this screen
                    // is the mark's orange and nothing else, so a symbol cannot quietly
                    // introduce a second colour of its own.
                    .symbolRenderingMode(.monochrome)
                    // A ten-year average is not a forecast, and the two must not look
                    // alike. Normals are drawn back; the park screen's own panel carries
                    // the sentence that says so.
                    .foregroundStyle(WP.mark.opacity(day.isNormals ? 0.55 : 1))
                    .frame(height: size + 3)
                Text("\(day.hi)°")
                    .font(WP.body(11)).tnum()
                    .foregroundStyle(WP.text.opacity(day.isNormals ? 0.45 : 0.7))
            }
            .frame(minWidth: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([caption, condition.label,
                                 "high \(day.hi) degrees",
                                 day.isNormals ? "typical for this date, not a forecast" : nil]
                .compactMap { $0 }.joined(separator: ", "))
        }
    }
}

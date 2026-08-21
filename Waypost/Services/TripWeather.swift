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

    /// Asks once per place-and-date, ever. Repeat calls — and there are many, because
    /// every redraw of the route calls this for every row — cost nothing.
    func load(lat: Double, lon: Double, date: Date) {
        let id = key(lat, lon, date)
        guard days[id] == nil, !asked.contains(id) else { return }
        asked.insert(id)

        Task { [weak self] in
            guard let self else { return }
            let iso = Self.iso.string(from: date)
            if let day = await WeatherService(failures: failures).forecast(lat: lat, lon: lon, iso: iso) {
                self.days[id] = day
            } else {
                // Nothing answered. Let it be asked again next launch rather than never.
                self.asked.remove(id)
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
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
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

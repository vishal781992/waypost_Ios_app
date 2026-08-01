import CoreLocation
import Foundation

/// Which park to put at the top of the home screen today.
///
/// It used to be day five of the seed trip, every time, forever — the same park with the
/// same photograph however far you had travelled and whatever the weather was doing. A
/// recommendation that never changes is not a recommendation.
///
/// Four things decide it, and the card says which of them applied:
///
///  * **Where you are.** Measured from the device fix, or the loose IP city behind it.
///    Near is better, but not overwhelmingly — a park an hour away in a heatwave is
///    worse than one four hours away in good weather.
///  * **Whether today is a good day to be there.** Open-Meteo's forecast for the park
///    itself, scored against what a day outdoors actually wants: sixties and seventies,
///    dry, not blowing.
///  * **Whether you have been.** A park you have stamped, saved or already put in a trip
///    scores lower than one you have never seen. The point is to send you somewhere new.
///  * **What it said last time.** The last two recommendations are held back so the
///    screen is different when you open it again.
@MainActor
@Observable
final class Recommender {
    struct Pick: Hashable {
        var park: CuratedPark
        /// Why this one — shown under the name, in place of the trip's day count.
        var reason: String
        var miles: Int?
    }

    private(set) var pick: Pick?
    private(set) var isWorking = false
    /// Where the phone said it was, in words, for the screens that measure from it.
    private(set) var placeName: String?
    private(set) var fix: (lat: Double, lon: Double)?

    private let location = LocationService()
    private let failures = FailureLog()
    private var weather: WeatherService { WeatherService(failures: failures) }

    /// Codes the last two opens landed on, so this one lands somewhere else.
    private static let recentKey = "parkhop-recent-recommendations"

    private var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(3)), forKey: Self.recentKey) }
    }

    /// Runs once per launch. The home screen shows the curated day-five park until this
    /// answers, so there is never an empty hero.
    func choose(from candidates: [CuratedPark], visited: Set<String>) {
        guard !isWorking, pick == nil, !candidates.isEmpty else { return }
        isWorking = true

        Task { [weak self] in
            guard let self else { return }
            defer { isWorking = false }

            // A precise fix takes as long as it takes; the recommendation should not.
            // Four seconds, then whatever the IP lookup says, then nothing.
            let fix = await withTaskGroup(of: LocationService.Fix?.self) { group in
                group.addTask { @MainActor in await self.location.currentFix() }
                group.addTask {
                    try? await Task.sleep(for: .seconds(4))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            if let fix {
                self.fix = (fix.lat, fix.lon)
                self.placeName = fix.city
                // An IP lookup often answers with a township nobody has heard of, so a
                // nameless fix is snapped to the nearest town Apple Maps does know.
                if self.placeName == nil {
                    self.placeName = await Self.nearestPlaceName(lat: fix.lat, lon: fix.lon)
                }
            }

            // Distance first, because it is free — then only the nearest handful are
            // worth a forecast each.
            let ranked = candidates.map { park -> (park: CuratedPark, miles: Double?) in
                guard let fix else { return (park, nil) }
                return (park, Geo.haversine((fix.lat, fix.lon), (park.lat, park.lon)))
            }
            .sorted { ($0.miles ?? .greatestFiniteMagnitude) < ($1.miles ?? .greatestFiniteMagnitude) }

            let shortlist = Array(ranked.prefix(6))
            let today = WPDate.iso(Date())

            // Six forecasts at once rather than one after another: sequentially this
            // took long enough that the screen had settled on the fallback before the
            // recommendation arrived, which is the same as not having one.
            let service = weather
            let held = recent
            let scored = await withTaskGroup(of: (pick: Pick, score: Double).self) { group in
                for candidate in shortlist {
                    group.addTask { @MainActor in
                        let forecast = await service.quickForecast(lat: candidate.park.lat,
                                                                   lon: candidate.park.lon,
                                                                   iso: today)
                        let isNew = !visited.contains(candidate.park.code)
                        return (
                            Pick(park: candidate.park,
                                 reason: Self.reason(miles: candidate.miles,
                                                     forecast: forecast,
                                                     isNew: isNew,
                                                     city: fix?.city),
                                 miles: candidate.miles.map { Int($0.rounded()) }),
                            Self.score(miles: candidate.miles,
                                       forecast: forecast,
                                       isNew: isNew,
                                       heldBack: held.contains(candidate.park.code))
                        )
                    }
                }
                var out: [(pick: Pick, score: Double)] = []
                for await result in group { out.append(result) }
                return out
            }

            guard let best = scored.max(by: { $0.score < $1.score })?.pick else { return }
            pick = best
            recent = [best.park.code] + recent.filter { $0 != best.park.code }
        }
    }

    /// The town a coordinate is in, from Apple Maps.
    private static func nearestPlaceName(lat: Double, lon: Double) async -> String? {
        let placemarks = try? await CLGeocoder()
            .reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
        return placemarks?.first.flatMap { $0.locality ?? $0.subAdministrativeArea }
    }

    // MARK: Scoring

    /// Out of 100. The weights are the argument: weather matters most, because a park in
    /// a hundred-degree afternoon is a bad day out however close it is.
    private static func score(miles: Double?, forecast: WeatherDay?,
                              isNew: Bool, heldBack: Bool) -> Double {
        var total = 0.0

        // Weather, 40. Sixty-eight is the middle of a good day; every ten degrees off
        // costs a third of the marks, and rain and wind take their own bite.
        if let forecast {
            let comfort = max(0, 1 - abs(Double(forecast.hi) - 68) / 30)
            var weather = comfort * 40
            if let chance = Int(forecast.precip.filter(\.isNumber)), chance > 40 {
                weather -= Double(chance) / 100 * 12
            }
            if let wind = Int(forecast.wind.filter(\.isNumber)), wind > 25 {
                weather -= 6
            }
            total += max(0, weather)
        } else {
            total += 18   // no forecast is not a bad forecast; it is an unknown one
        }

        // Distance, 35, on a curve rather than a line: the difference between 40 miles
        // and 90 matters; the difference between 600 and 700 does not.
        if let miles {
            total += 35 * (1 / (1 + miles / 220))
        } else {
            total += 12
        }

        // Somewhere new, 25. This is the whole point of the panel.
        if isNew { total += 25 }

        // And not the same park as last time.
        if heldBack { total -= 30 }

        return total
    }

    /// The line under the name. Only says what is actually known — no distance when
    /// there is no fix, no temperature when no forecast came back.
    private static func reason(miles: Double?, forecast: WeatherDay?,
                               isNew: Bool, city: String?) -> String {
        var parts: [String] = []

        if let forecast {
            parts.append("\(forecast.hi)° today")
        }
        if let miles {
            let rounded = miles < 100 ? Int((miles / 5).rounded()) * 5 : Int((miles / 10).rounded()) * 10
            parts.append(city.map { "\(rounded) mi from \($0)" } ?? "\(rounded) mi from you")
        }
        parts.append(isNew ? "not stamped yet" : "you have been")

        return parts.joined(separator: " · ")
    }
}

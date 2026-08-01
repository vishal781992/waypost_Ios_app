import Foundation
import CoreLocation
#if PARKHOP_WEATHERKIT
import WeatherKit
#endif

/// Apple's own forecast, through WeatherKit.
///
/// It is the best source available on an iPhone for the things this app shows — daily
/// high and low, UV index, wind, sunrise and sunset all come from one call, already in
/// the user's units, with no key in the app and no proxy in front of it.
///
/// **It is switched off, and the code is kept.**
///
/// The entitlement requires a paid Apple Developer Program membership. Signing with a
/// free personal team, Xcode cannot generate a provisioning profile carrying it, so the
/// build fails before any of this runs — Apple policy, not a fault in the project. Rather
/// than delete a working implementation for a billing reason, it is compiled out behind
/// `PARKHOP_WEATHERKIT`, which is not defined.
///
/// To bring it back: pay for the membership, add the WeatherKit capability to the App ID,
/// re-enable `CODE_SIGN_ENTITLEMENTS` in `project.yml`, uncomment the key in
/// `Waypost.entitlements`, and define `PARKHOP_WEATHERKIT`. Nothing else changes —
/// `WeatherService` already asks this first and falls through when it declines.
///
/// Until then Open-Meteo and the National Weather Service carry the app, as they did
/// before this file existed, and the panel names whichever answered.
@MainActor
struct AppleWeather {
    let failures: FailureLog

    /// Attribution is required by WeatherKit's terms wherever its data is shown.
    static let attribution = "Apple Weather"

    /// False while the entitlement is unavailable, so `WeatherService` does not even
    /// try — a refusal that costs a round trip is worse than one that costs nothing.
    var isAvailable: Bool {
        #if PARKHOP_WEATHERKIT
        return true
        #else
        return false
        #endif
    }

    /// The forecast for one day at one place, or nil if WeatherKit is not entitled,
    /// not reachable, or has nothing for that date.
    func forecast(lat: Double, lon: Double, iso: String) async -> WeatherDay? {
        #if PARKHOP_WEATHERKIT
        let location = CLLocation(latitude: lat, longitude: lon)
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)

            // Match the requested date rather than assuming today: the park screen asks
            // for the day the trip is in that park.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            guard let wanted = formatter.date(from: iso) else { return nil }

            guard let day = weather.dailyForecast.forecast.first(where: {
                calendar.isDate($0.date, inSameDayAs: wanted)
            }) ?? weather.dailyForecast.forecast.first else { return nil }

            let time = DateFormatter()
            time.dateFormat = "h:mm a"
            time.timeZone = .current

            return WeatherDay(
                source: Self.attribution,
                hi: Int(day.highTemperature.converted(to: UnitTemperature.fahrenheit).value.rounded()),
                lo: Int(day.lowTemperature.converted(to: UnitTemperature.fahrenheit).value.rounded()),
                precip: "\(Int((day.precipitationChance * 100).rounded()))%",
                wind: "\(Int(day.wind.speed.converted(to: UnitSpeed.milesPerHour).value.rounded())) mph",
                uv: day.uvIndex.value,
                humidity: nil,
                sunrise: day.sun.sunrise.map { time.string(from: $0) },
                sunset: day.sun.sunset.map { time.string(from: $0) },
                shortForecast: day.condition.description,
                note: "\(day.condition.description). \(Int((day.precipitationChance * 100).rounded()))% chance of precipitation."
            )
        } catch {
            // The common failure is a missing entitlement, which is a build-configuration
            // fact rather than a network one — worth naming so it is not read as an outage.
            failures.note("Apple Weather (WeatherKit)", error)
            return nil
        }
        #else
        return nil
        #endif
    }
}

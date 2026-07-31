import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Apple's own forecast, through WeatherKit.
///
/// It is the best source available on an iPhone for the things this app shows — daily
/// high and low, UV index, wind, sunrise and sunset all come from one call, already in
/// the user's units, with no key in the app and no proxy in front of it.
///
/// It is also the only source here that can be switched off by something outside the
/// code: WeatherKit needs the capability on the App ID and a paid developer account, and
/// without the entitlement every call throws. That is why it is a source rather than
/// *the* source — when it is unavailable the app falls back to Open-Meteo and the panel
/// says which one answered, exactly as it does for every other feed.
@MainActor
struct AppleWeather {
    let failures: FailureLog

    /// Attribution is required by WeatherKit's terms wherever its data is shown.
    static let attribution = "Apple Weather"

    var isAvailable: Bool {
        #if canImport(WeatherKit)
        return true
        #else
        return false
        #endif
    }

    /// The forecast for one day at one place, or nil if WeatherKit is not entitled,
    /// not reachable, or has nothing for that date.
    func forecast(lat: Double, lon: Double, iso: String) async -> WeatherDay? {
        #if canImport(WeatherKit)
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

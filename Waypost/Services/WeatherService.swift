import Foundation

/// Weather for a park on a specific day.
///
/// Three sources, in order of authority:
///  1. **Open-Meteo forecast** — 16 days out, carries UV, humidity and sun times.
///  2. **NWS** — sharper numbers and wording inside its ~7-day window; overlaid on top.
///  3. **Open-Meteo archive (ERA5)** — for dates beyond the forecast, the *same*
///     calendar window (±3 days) averaged across the last 10 years at this park's
///     coordinates. Computed, never hard-coded, and always labelled as an average.
///
/// UV is absent from ERA5, so on the normals path it is derived from solar geometry and
/// flagged `uvModelled` — the cell reads "· modelled" so it can't pass as a measurement.
@MainActor
struct WeatherService {
    let failures: FailureLog

    func forecast(lat: Double, lon: Double, iso: String) async -> WeatherDay? {
        var day = await openMeteo(lat: lat, lon: lon, iso: iso)
        if let nws = await nationalWeatherService(lat: lat, lon: lon, iso: iso) {
            day = merge(openMeteo: day, nws: nws)
        }
        return day
    }

    // MARK: Open-Meteo forecast

    private func openMeteo(lat: Double, lon: Double, iso: String) async -> WeatherDay? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,uv_index_max,sunrise,sunset"),
            .init(name: "hourly", value: "relative_humidity_2m"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "wind_speed_unit", value: "mph"),
            .init(name: "timezone", value: "auto"),
            .init(name: "start_date", value: iso),
            .init(name: "end_date", value: iso),
        ]
        guard let url = c.url else { return nil }
        do {
            let obj = try await HTTP.any(url)
            guard let daily = obj["daily"] as? [String: Any],
                  let times = daily["time"] as? [String], !times.isEmpty else { return nil }
            func first(_ key: String) -> Double? { (daily[key] as? [Double?])?.first ?? nil }
            guard let hi = first("temperature_2m_max"), let lo = first("temperature_2m_min") else { return nil }

            let humidityHours = (obj["hourly"] as? [String: Any])?["relative_humidity_2m"] as? [Double?]
            let midday = humidityHours?.compactMap { $0 }
            let rh = midday.flatMap { $0.isEmpty ? nil : $0[min(12, $0.count - 1)] }

            let sunrise = (daily["sunrise"] as? [String])?.first
            let sunset = (daily["sunset"] as? [String])?.first

            return WeatherDay(
                source: "Open-Meteo",
                hi: Int(hi.rounded()),
                lo: Int(lo.rounded()),
                precip: "\(Int((first("precipitation_probability_max") ?? 0).rounded()))%",
                wind: "\(Int((first("wind_speed_10m_max") ?? 0).rounded())) mph, gusts \(Int((first("wind_gusts_10m_max") ?? 0).rounded()))",
                uv: first("uv_index_max").map { Int($0.rounded()) },
                humidity: rh.map { "\(Int($0.rounded()))%" },
                sunrise: Self.time12(sunrise),
                sunset: Self.time12(sunset)
            )
        } catch {
            failures.note("forecast (Open-Meteo)", error)
            return nil
        }
    }

    // MARK: NWS overlay

    private struct NWSDay {
        var hi: Int
        var lo: Int?
        var wind: String
        var short: String
        var precip: String
    }

    private func nationalWeatherService(lat: Double, lon: Double, iso: String) async -> NWSDay? {
        guard let pointURL = URL(string: "https://api.weather.gov/points/\(lat),\(lon)") else { return nil }
        do {
            let point = try await HTTP.any(pointURL)
            guard let props = point["properties"] as? [String: Any],
                  let forecastURL = safeURL(props["forecast"] as? String) else { return nil }
            let forecast = try await HTTP.any(forecastURL)
            guard let periods = (forecast["properties"] as? [String: Any])?["periods"] as? [[String: Any]] else { return nil }

            func onDay(_ daytime: Bool) -> [String: Any]? {
                periods.first { p in
                    (p["isDaytime"] as? Bool) == daytime && ((p["startTime"] as? String) ?? "").hasPrefix(iso)
                }
            }
            guard let day = onDay(true), let hi = day["temperature"] as? Int else { return nil }
            let night = onDay(false)
            let pop = ((day["probabilityOfPrecipitation"] as? [String: Any])?["value"] as? Int) ?? 0
            return NWSDay(
                hi: hi,
                lo: night?["temperature"] as? Int,
                wind: "\(day["windDirection"] as? String ?? "") \(day["windSpeed"] as? String ?? "")".trimmingCharacters(in: .whitespaces),
                short: day["shortForecast"] as? String ?? "",
                precip: "\(pop)%"
            )
        } catch {
            // NWS only covers the US and only ~7 days out; a miss here is normal and
            // Open-Meteo already answered, so this is not a source failure.
            return nil
        }
    }

    private func merge(openMeteo: WeatherDay?, nws: NWSDay) -> WeatherDay {
        var day = openMeteo ?? WeatherDay(source: "NWS", hi: nws.hi, lo: nws.lo ?? nws.hi,
                                          precip: nws.precip, wind: nws.wind)
        day.source = openMeteo == nil ? "NWS" : "NWS + Open-Meteo"
        day.hi = nws.hi
        if let lo = nws.lo { day.lo = lo }
        day.wind = nws.wind
        day.precip = nws.precip
        day.shortForecast = nws.short
        return day
    }

    // MARK: Climate normals (ERA5 archive)

    /// Averages the same calendar window (±3 days) across the last 10 years. Nothing is
    /// hard-coded: every figure is computed for the exact date at this park's coordinates.
    func normals(lat: Double, lon: Double, iso: String) async -> WeatherDay? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (year, month, dayOfMonth) = (parts[0], parts[1], parts[2])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // The archive lags roughly five days, so never ask for the current year.
        let newest = min(year - 1, utc.component(.year, from: Date()) - 1)
        let years = (0..<10).map { newest - $0 }
        let daily = "temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max,wind_gusts_10m_max,sunrise,sunset"

        func window(_ y: Int) -> (String, String)? {
            var comps = DateComponents(); comps.year = y; comps.month = month; comps.day = dayOfMonth
            guard let centre = utc.date(from: comps),
                  let from = utc.date(byAdding: .day, value: -3, to: centre),
                  let to = utc.date(byAdding: .day, value: 3, to: centre) else { return nil }
            let f = DateFormatter()
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd"
            return (f.string(from: from), f.string(from: to))
        }

        var payloads: [[String: Any]] = []
        await withTaskGroup(of: [String: Any]?.self) { group in
            for y in years {
                guard let (from, to) = window(y) else { continue }
                group.addTask {
                    var c = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")!
                    c.queryItems = [
                        .init(name: "latitude", value: String(lat)),
                        .init(name: "longitude", value: String(lon)),
                        .init(name: "start_date", value: from),
                        .init(name: "end_date", value: to),
                        .init(name: "daily", value: daily),
                        .init(name: "hourly", value: "relative_humidity_2m"),
                        .init(name: "temperature_unit", value: "fahrenheit"),
                        .init(name: "wind_speed_unit", value: "mph"),
                        .init(name: "timezone", value: "auto"),
                    ]
                    guard let url = c.url else { return nil }
                    return try? await HTTP.any(url)
                }
            }
            for await payload in group {
                if let payload, let d = payload["daily"] as? [String: Any],
                   let t = d["time"] as? [String], !t.isEmpty {
                    payloads.append(payload)
                }
            }
        }

        guard !payloads.isEmpty else {
            failures.note("climate normals (Open-Meteo archive)", "no archive years answered")
            return nil
        }

        func column(_ key: String) -> [Double] {
            payloads.flatMap { (($0["daily"] as? [String: Any])?[key] as? [Double?] ?? []).compactMap { $0 } }
        }
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

        let his = column("temperature_2m_max"), los = column("temperature_2m_min")
        guard let hi = mean(his), let lo = mean(los) else { return nil }
        let precip = column("precipitation_sum")
        let wind = mean(column("wind_speed_10m_max")) ?? 0
        let gusts = mean(column("wind_gusts_10m_max")) ?? 0
        let humidity = payloads.flatMap { (($0["hourly"] as? [String: Any])?["relative_humidity_2m"] as? [Double?] ?? []).compactMap { $0 } }
        let wetFraction = precip.isEmpty ? 0 : Double(precip.filter { $0 >= 0.2 }.count) / Double(precip.count)

        // ERA5 publishes no UV field. Derive it from solar geometry for this date and
        // latitude, lifted for elevation and damped by how often the window runs wet.
        let dayOfYear = Self.dayOfYear(year: year, month: month, day: dayOfMonth)
        let declination = (23.44 * .pi / 180) * sin(2 * .pi * (284 + Double(dayOfYear)) / 365)
        let latR = lat * .pi / 180
        let cosZenith = max(0, sin(latR) * sin(declination) + cos(latR) * cos(declination))
        let elevation = (payloads.first?["elevation"] as? Double) ?? 0
        let uv = max(0, Int((12.5 * pow(cosZenith, 2.42) * (1 + 0.06 * elevation / 1000) * (1 - 0.28 * wetFraction)).rounded()))

        let wetPercent = Int((wetFraction * 100).rounded())
        var bits: [String] = []
        if hi >= 95 { bits.append("dangerous midday heat — hike at dawn") }
        else if hi >= 85 { bits.append("hot afternoons") }
        if lo <= 35 { bits.append("near-freezing nights — pack layers") }
        if wetPercent >= 40 { bits.append("wet on about \(wetPercent)% of days in this window") }
        else if wetPercent >= 20 { bits.append("showers on roughly \(wetPercent)% of days") }
        if gusts >= 30 { bits.append("gusts to \(Int(gusts.rounded())) mph") }
        if uv >= 10 { bits.append("extreme UV — sun cover essential") }

        let sunriseRow = (payloads.first?["daily"] as? [String: Any])?["sunrise"] as? [String]
        let sunsetRow = (payloads.first?["daily"] as? [String: Any])?["sunset"] as? [String]
        let mid = max(0, min(3, (sunriseRow?.count ?? 1) - 1))

        var note = "Averaged from \(payloads.count) years of \(month)/\(dayOfMonth) (±3 days) at this location. "
        note += bits.isEmpty
            ? "Generally settled conditions in this window."
            : bits.joined(separator: "; ").prefix(1).uppercased() + bits.joined(separator: "; ").dropFirst() + "."

        return WeatherDay(
            source: "Open-Meteo archive",
            hi: Int(hi.rounded()),
            lo: Int(lo.rounded()),
            precip: "\(wetPercent)%",
            wind: "\(Int(wind.rounded())) mph, gusts \(Int(gusts.rounded()))",
            uv: uv,
            uvModelled: true,
            humidity: mean(humidity).map { "\(Int($0.rounded()))%" },
            sunrise: Self.time12(sunriseRow?[safe: mid]),
            sunset: Self.time12(sunsetRow?[safe: mid]),
            note: note,
            isNormals: true,
            years: payloads.count
        )
    }

    // MARK: Helpers

    /// "2026-08-05T06:23" -> "6:23 am"
    static func time12(_ iso: String?) -> String? {
        guard let iso, iso.count >= 16 else { return nil }
        let hhmm = iso.dropFirst(11).prefix(5).split(separator: ":").compactMap { Int($0) }
        guard hhmm.count == 2 else { return nil }
        let (h, m) = (hhmm[0], hhmm[1])
        return String(format: "%d:%02d %@", ((h + 11) % 12) + 1, m, h >= 12 ? "pm" : "am")
    }

    static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = day
        guard let date = utc.date(from: comps) else { return 1 }
        return utc.ordinality(of: .day, in: .year, for: date) ?? 1
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

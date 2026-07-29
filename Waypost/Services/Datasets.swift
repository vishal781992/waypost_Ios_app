import Foundation

/// The bundled datasets, loaded once. `state-parks.json` is 426 KB and is only read the
/// first time the user switches the source to state parks — the same lazy split the web
/// app makes with its dynamic `import()`.
final class Datasets: @unchecked Sendable {
    static let shared = Datasets()

    let cities: [City]
    let seedParks: [Park]
    let legs: [String: Leg]
    let airports: [Airport]

    private var _stateParks: [StateParkRow]?
    private let lock = NSLock()

    private init() {
        cities = Self.load("cities", as: [City].self) ?? []
        seedParks = Self.load("parks", as: [Park].self) ?? []
        airports = Self.load("airports", as: [Airport].self) ?? []
        let legRows = Self.load("legs", as: [Leg].self) ?? []
        legs = Dictionary(uniqueKeysWithValues: legRows.compactMap { leg in
            leg.key.map { ($0, leg) }
        })
    }

    var stateParks: [StateParkRow] {
        lock.lock()
        defer { lock.unlock() }
        if let _stateParks { return _stateParks }
        let rows = Self.load("state-parks", as: [StateParkRow].self) ?? []
        _stateParks = rows
        return rows
    }

    var seedParksByCode: [String: Park] {
        Dictionary(uniqueKeysWithValues: seedParks.map { ($0.code, $0) })
    }

    private static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("missing bundled dataset: \(name).json")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            assertionFailure("bad dataset \(name).json: \(error)")
            return nil
        }
    }
}

// MARK: - Geometry, shared with the web app

enum Geo {
    static let earthRadiusMiles = 3958.8

    /// Great-circle miles. Same constant and formula as `haversine()` in parks-data.js.
    static func haversine(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let rad = { (d: Double) in d * .pi / 180 }
        let dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon)
        let h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLon / 2), 2)
        return 2 * earthRadiusMiles * asin(sqrt(h))
    }

    /// The curated leg if one exists in either direction, otherwise a coordinate
    /// estimate — flagged `estimated` so the UI can say the numbers are modelled.
    static func legBetween(fromKey: String, fromLat: Double, fromLon: Double,
                           toKey: String, toLat: Double, toLon: Double) -> Leg {
        let legs = Datasets.shared.legs
        if var hit = legs["\(fromKey)|\(toKey)"] { hit.reversed = false; return hit }
        if var hit = legs["\(toKey)|\(fromKey)"] { hit.reversed = true; return hit }

        let mi = Int((haversine((fromLat, fromLon), (toLat, toLon)) * 1.28).rounded())
        let hrs = Double(mi) / 58
        let h = Int(hrs)
        let m = Int(((hrs - Double(h)) * 60 / 5).rounded()) * 5
        return Leg(
            mi: mi,
            drive: m > 0 ? "\(h) h \(m) m" : "\(h) h",
            route: "Fastest highway route (estimated)",
            chargers: ["Fast charging every 60–120 mi on interstates — verify on PlugShare"],
            fly: FlyOption(via: "Check connections via SLC or DEN", time: "",
                           note: "Estimated leg — no curated flight data"),
            estimated: true
        )
    }
}

// MARK: - Dates

enum WPDate {
    static func addDays(_ d: Date, _ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: d) ?? d
    }

    /// The `YYYY-MM-DD` the APIs want, in the device's calendar — not UTC, because a
    /// trip date is a local day.
    static func iso(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func fromISO(_ s: String) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return Calendar.current.date(from: c)
    }

    /// "Wed, Aug 5" — the web app's `fmtDate`.
    static func short(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Aug 5, 2026"
    static func medium(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func today() -> Date {
        Calendar.current.startOfDay(for: Date())
    }
}

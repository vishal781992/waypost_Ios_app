import Foundation

// MARK: - Live records, in the shape the screens already draw
//
// Every screen in the app draws a `CuratedPark`. That is a good shape — it is the one
// the design was drawn against — so a park found live is converted into it rather than
// given a second layout of its own. Nothing about the design changes; only where the
// values come from.
//
// The rule the whole app is built on applies hardest here: a field the source did not
// publish is left saying so. An NPS park with no published fee reads "Not published by
// NPS", never "$30". A park found through OpenStreetMap shows no fee at all, because
// OpenStreetMap does not know it.

extension CuratedPark {

    /// An NPS unit, from the park service's own record.
    init(live park: Park) {
        self.init(
            code: park.code,
            name: park.name,
            full: park.full,
            state: park.state,
            lat: park.lat,
            lon: park.lon,
            tag: park.tagline,
            gw: park.gateway,
            region: CuratedPark.region(for: park.designation ?? park.tagline),
            crowd: park.designation ?? "National Park Service unit",
            fee: park.fee,
            hours: park.hours,
            res: park.reservation != nil,
            resNote: park.reservation.map(\.note) ?? "NPS does not publish an entry reservation for this park.",
            c: CuratedPark.palette(for: park.code),
            pack: "Not downloaded",
            wx: .unpublished,
            gates: park.gates,
            parking: park.parking,
            airports: park.airports.map {
                CuratedAirport(code: $0.code, name: $0.name, drive: $0.drive, note: $0.note, best: $0.best)
            },
            camping: [],
            lodging: [],
            fuel: CuratedFuel(gas: [], fast: [], slow: []),
            alerts: park.alerts.map { CuratedAlert(cat: $0.cat, title: $0.title, body: $0.body) },
            days: [],
            stamps: [],
            source: .nps
        )
    }

    /// A protected area as OpenStreetMap has it — a name, a place, and a designation.
    /// Everything else is honestly blank: OSM is a map, not a park service.
    init(osm place: OSMPlace) {
        self.init(
            code: place.id,
            name: CuratedPark.shortName(place.name),
            full: place.name,
            state: place.state,
            lat: place.lat,
            lon: place.lon,
            tag: place.designation ?? "Protected area",
            gw: "",
            region: CuratedPark.region(for: place.designation ?? place.name),
            crowd: place.designation ?? "Protected area",
            fee: "Not published by OpenStreetMap",
            hours: "Not published by OpenStreetMap",
            res: false,
            resNote: "OpenStreetMap does not carry entry reservations. Check with the park before you travel.",
            c: CuratedPark.palette(for: place.id),
            pack: "Not downloaded",
            wx: .unpublished,
            gates: [],
            parking: "",
            airports: [],
            camping: [],
            lodging: [],
            fuel: CuratedFuel(gas: [], fast: [], slow: []),
            alerts: [],
            days: [],
            stamps: [],
            source: .openStreetMap
        )
    }

    /// The same park with today's weather filled in, once a forecast has been fetched.
    func withWeather(_ day: WeatherDay) -> CuratedPark {
        var copy = self
        copy.wx = CuratedWeather(
            hi: day.hi,
            lo: day.lo,
            uv: day.uv.map { "\($0) — \(CuratedWeather.uvWord(for: $0))" } ?? "Not published",
            wind: day.wind,
            sr: day.sunrise ?? "—",
            ss: day.sunset ?? "—",
            note: day.note ?? (day.isNormals ? "Normals for this date." : "Forecast for this date."),
            source: day.source
        )
        return copy
    }

    // MARK: Derived decoration
    //
    // Colour is the one thing invented here, and it is not a claim about the park — it
    // is how a card is told apart from the card above it. The park's own code seeds it,
    // so a park looks the same every time you open it.

    static func palette(for seed: String) -> [String] {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let hue = Double(hash % 360)
        return [
            "oklch(0.42 0.11 \(Int(hue)))",
            "oklch(0.58 0.13 \(Int((hue + 22).truncatingRemainder(dividingBy: 360))))",
            "oklch(0.74 0.09 \(Int((hue + 48).truncatingRemainder(dividingBy: 360))))",
        ]
    }

    /// The chip rail on Discover groups by terrain; a designation is the closest thing a
    /// live record carries to one, and "Protected area" is an honest fallback.
    static func region(for text: String) -> String {
        let t = text.lowercased()
        if t.contains("seashore") || t.contains("coast") || t.contains("island") { return "Coast" }
        if t.contains("desert") || t.contains("canyon") || t.contains("dunes") { return "Desert" }
        if t.contains("volcan") || t.contains("geyser") || t.contains("hot spring") { return "Geothermal" }
        if t.contains("mountain") || t.contains("peak") || t.contains("alpine") || t.contains("glacier") { return "Alpine" }
        return "Protected area"
    }

    /// "Arches National Park" reads as "Arches" on a card; the full name stays in `full`.
    static func shortName(_ full: String) -> String {
        var name = full
        for suffix in [" National Park and Preserve", " National Park", " National Monument",
                       " National Recreation Area", " National Seashore", " National Forest",
                       " State Park", " Wilderness"] {
            if name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)); break }
        }
        return name
    }
}

extension CuratedWeather {
    /// What the app shows before a forecast has come back — and what it goes on showing
    /// if none does. No zeroes dressed up as measurements.
    static let unpublished = CuratedWeather(
        hi: 0, lo: 0, uv: "Not published", wind: "Not published",
        sr: "—", ss: "—", note: "No forecast has been fetched for this park yet.",
        source: nil
    )

    /// True once a source has actually answered. The weather panel reads this rather
    /// than showing 0° as if it were a temperature.
    var isPublished: Bool { source != nil }

    static func uvWord(for index: Int) -> String {
        switch index {
        case 11...: return "extreme"
        case 8...10: return "very high"
        case 6...7: return "high"
        case 3...5: return "moderate"
        default: return "low"
        }
    }
}

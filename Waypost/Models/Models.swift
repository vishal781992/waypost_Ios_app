import Foundation

// MARK: - Bundled datasets
//
// These mirror the web repo's `parks-data.js`, `airports.js` and `state-parks.js`
// verbatim — `tools/convert-data.mjs` re-generates the JSON from those modules, so the
// two apps can never disagree about what a park is.

struct City: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let airport: String?

    /// "Denver, CO" -> "Denver". Used on the map and in leg headings.
    var shortName: String { name.split(separator: ",").first.map(String.init) ?? name }
}

struct Airport: Codable, Hashable {
    let code: String
    let name: String
    let city: String?
    let st: String?
    let lat: Double
    let lon: Double
    /// 1 = large hub, 2 = medium/regional, 3 = small field.
    let t: Int
}

/// One row of the Wikidata-derived state-park table. Coordinates and a website are all
/// that is published nationwide — no hours, fees, alerts or campsites exist for these.
struct StateParkRow: Codable, Hashable {
    let n: String
    let s: String
    let lat: Double
    let lon: Double
    let w: String?
    let i: String?
}

struct Reservation: Codable, Hashable {
    var required: Bool
    var note: String
}

struct ParkAirport: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    var drive: String
    var note: String
    var best: Bool?
    var id: String { code }
}

struct Campground: Codable, Hashable, Identifiable {
    var rgId: Int?
    var name: String
    var whereText: String
    var sites: String
    var price: String
    var status: String
    var src: String
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case rgId, name, sites, price, status, src
        case whereText = "where"
    }

    /// Recreation.gov deep link when we know the campground id, otherwise a search.
    var link: URL? {
        if let rgId {
            return URL(string: "https://www.recreation.gov/camping/campgrounds/\(rgId)")
        }
        var c = URLComponents(string: "https://www.recreation.gov/search")
        c?.queryItems = [URLQueryItem(name: "q", value: name)]
        return c?.url
    }
}

struct Lodging: Codable, Hashable, Identifiable {
    var name: String
    var whereText: String?
    var price: String?
    var note: String?
    var link: String?
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, price, note, link
        case whereText = "where"
    }
}

struct Fuel: Codable, Hashable {
    var gas: [String] = []
    var fast: [String] = []
    var slow: [String] = []
}

struct Alert: Codable, Hashable, Identifiable {
    var cat: String
    var title: String
    var body: String
    var id: String { cat + title }
}

struct DayPlanItem: Codable, Hashable, Identifiable {
    var time: String
    var text: String
    var id: String { time + text }
}

struct DayPlan: Codable, Hashable, Identifiable {
    var title: String
    var items: [DayPlanItem]
    var id: String { title }
}

/// Where a park's record came from — decides which panels can claim knowledge.
enum ParkTier: String, Codable, Hashable {
    /// Curated seed park: full detail bundled with the app.
    case seed
    /// Found through the NPS API: real record, thin until the live fetches land.
    case nps
    /// Wikidata state park: coordinates and a website, nothing else exists nationwide.
    case state
}

struct Park: Codable, Identifiable, Hashable {
    var code: String
    var name: String
    var full: String
    var state: String
    var lat: Double
    var lon: Double
    var gwLat: Double?
    var gwLon: Double?
    var tagline: String
    var gateway: String
    var fee: String
    var hours: String
    var reservation: Reservation?
    var gates: [String] = []
    var parking: String = ""
    var airports: [ParkAirport] = []
    var camping: [Campground] = []
    var lodging: [Lodging] = []
    var fuel: Fuel = Fuel()
    var alerts: [Alert] = []
    var days: [DayPlan] = []
    var flex: DayPlan?
    var tier: ParkTier = .seed
    var designation: String?
    var website: String?
    var wikiImage: String?
    var distMi: Int?
    /// NPS publishes some units without coordinates; those can't be ranked by distance
    /// or drawn on the map, so the nearby shelf drops them rather than placing them at
    /// a default point.
    var hasCoordinates: Bool = true

    var id: String { code }
    var gatewayLat: Double { gwLat ?? lat }
    var gatewayLon: Double { gwLon ?? lon }

    /// The tile badge. Resolution order matches the web app after v1.9.1: explicit
    /// designation field -> recovered from the end of the official name -> tagline.
    /// Never a truncation of descriptive prose.
    var badge: String? {
        if let d = designation, !d.isEmpty { return Self.shortDesignation(d) }
        if let d = Self.designationFromName(full) { return Self.shortDesignation(d) }
        return nil
    }

    var isNationalPark: Bool {
        (badge ?? "").localizedCaseInsensitiveContains("national park")
            || full.localizedCaseInsensitiveContains("National Park")
    }

    static func designationFromName(_ full: String) -> String? {
        let known = ["National Park & Preserve", "National Park and Preserve", "National Park",
                     "National Monument", "National Historic Site", "National Historical Park",
                     "National Recreation Area", "National Seashore", "National Lakeshore",
                     "National Memorial", "National Battlefield", "National Preserve",
                     "National Scenic Trail", "National Reserve", "State Park"]
        return known.first { full.hasSuffix($0) }
    }

    /// "National Historical Park" is too long for a 3-column tile; the web app trims the
    /// leading "National" the same way.
    static func shortDesignation(_ d: String) -> String {
        let t = d.replacingOccurrences(of: "National ", with: "")
        return t.isEmpty ? d : t.prefix(1).uppercased() + t.dropFirst()
    }
}

extension Park {
    /// Hand-written because the bundled seed rows omit the fields the app fills in
    /// later (tier, designation, distance). Synthesized decoding would treat a missing
    /// key as an error rather than as "not published yet".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        full = try c.decodeIfPresent(String.self, forKey: .full) ?? name
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        gwLat = try c.decodeIfPresent(Double.self, forKey: .gwLat)
        gwLon = try c.decodeIfPresent(Double.self, forKey: .gwLon)
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? ""
        gateway = try c.decodeIfPresent(String.self, forKey: .gateway) ?? name
        fee = try c.decodeIfPresent(String.self, forKey: .fee) ?? "See NPS"
        hours = try c.decodeIfPresent(String.self, forKey: .hours) ?? "See the park page"
        reservation = try c.decodeIfPresent(Reservation.self, forKey: .reservation)
        gates = try c.decodeIfPresent([String].self, forKey: .gates) ?? []
        parking = try c.decodeIfPresent(String.self, forKey: .parking) ?? ""
        airports = try c.decodeIfPresent([ParkAirport].self, forKey: .airports) ?? []
        camping = try c.decodeIfPresent([Campground].self, forKey: .camping) ?? []
        lodging = try c.decodeIfPresent([Lodging].self, forKey: .lodging) ?? []
        fuel = try c.decodeIfPresent(Fuel.self, forKey: .fuel) ?? Fuel()
        alerts = try c.decodeIfPresent([Alert].self, forKey: .alerts) ?? []
        days = try c.decodeIfPresent([DayPlan].self, forKey: .days) ?? []
        flex = try c.decodeIfPresent(DayPlan.self, forKey: .flex)
        tier = try c.decodeIfPresent(ParkTier.self, forKey: .tier) ?? .seed
        designation = try c.decodeIfPresent(String.self, forKey: .designation)
        website = try c.decodeIfPresent(String.self, forKey: .website)
        wikiImage = try c.decodeIfPresent(String.self, forKey: .wikiImage)
        distMi = try c.decodeIfPresent(Int.self, forKey: .distMi)
        hasCoordinates = try c.decodeIfPresent(Bool.self, forKey: .hasCoordinates) ?? true
    }

    /// The minimum a park needs to exist in the app: everything else arrives live, or
    /// is reported as unpublished.
    init(code: String, name: String, full: String, state: String, lat: Double, lon: Double,
         tagline: String, gateway: String, tier: ParkTier, designation: String? = nil,
         website: String? = nil, wikiImage: String? = nil, fee: String = "See NPS",
         hours: String = "See the park page", gates: [String] = []) {
        self.code = code
        self.name = name
        self.full = full
        self.state = state
        self.lat = lat
        self.lon = lon
        self.tagline = tagline
        self.gateway = gateway
        self.fee = fee
        self.hours = hours
        self.gates = gates
        self.tier = tier
        self.designation = designation
        self.website = website
        self.wikiImage = wikiImage
    }
}

// MARK: - Legs

/// One end of a flown leg: which airport, and where on the earth it is.
struct FlyAirport: Codable, Hashable {
    var code: String
    var lat: Double
    var lon: Double
}

struct FlyOption: Codable, Hashable {
    var via: String
    var time: String
    var note: String
    /// The airports the leg would be flown between.
    ///
    /// `FlightCompare` has always known these — it finds both hubs and measures the air
    /// miles between them — and then returned nothing but `via`, a string reading
    /// "MDW → SLC". Two coordinates went into every verdict and neither came out, so the
    /// map had no way to draw a leg the app itself had decided to fly.
    ///
    /// Optional because the bundled table in `curated.json` names a connection in prose
    /// and carries no coordinates at all. A flight with no airports is drawn as a drive,
    /// which is what it was before.
    var from: FlyAirport? = nil
    var to: FlyAirport? = nil
}

struct Leg: Codable, Hashable {
    var key: String?
    var mi: Int
    var drive: String
    var route: String
    var chargers: [String] = []
    var fly: FlyOption?
    /// True when the leg was computed from coordinates rather than read from the
    /// curated table — the UI labels it so no estimate reads as a measurement.
    var estimated: Bool = false
    var reversed: Bool = false

    init(key: String? = nil, mi: Int, drive: String, route: String, chargers: [String] = [],
         fly: FlyOption? = nil, estimated: Bool = false, reversed: Bool = false) {
        self.key = key
        self.mi = mi
        self.drive = drive
        self.route = route
        self.chargers = chargers
        self.fly = fly
        self.estimated = estimated
        self.reversed = reversed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        mi = try c.decode(Int.self, forKey: .mi)
        drive = try c.decode(String.self, forKey: .drive)
        route = try c.decodeIfPresent(String.self, forKey: .route) ?? ""
        chargers = try c.decodeIfPresent([String].self, forKey: .chargers) ?? []
        fly = try c.decodeIfPresent(FlyOption.self, forKey: .fly)
        estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        reversed = try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? false
    }
}

// MARK: - Live records

/// A day's weather for one park. `source` names exactly where each number came from;
/// `isNormals` marks a climate average rather than a forecast.
struct WeatherDay: Hashable {
    var source: String
    var hi: Int
    var lo: Int
    var precip: String
    var wind: String
    var uv: Int?
    var uvModelled: Bool = false
    var humidity: String?
    var sunrise: String?
    var sunset: String?
    var shortForecast: String?
    var note: String?
    var isNormals: Bool = false
    var years: Int?
    /// What the sky is doing, when a source will say. Nil is not "clear" — it is "nobody
    /// told us", and nothing is drawn for it.
    var condition: WeatherCondition?
}

/// The sky, in the handful of states worth a symbol on a row.
///
/// Deliberately coarser than the forty-odd codes the WMO publishes: a reader glancing at a
/// trip wants to know whether to expect sun, cloud, water or ice, and nine glyphs that can
/// be told apart at 19pt beat forty that cannot. Everything maps into one of these.
enum WeatherCondition: String, Hashable, Codable {
    case clear, mainlyClear, cloudy, fog, drizzle, rain, snow, sleet, thunderstorm

    /// The park service's weather in Apple's own glyphs. SF Symbols rather than drawn
    /// shapes: they are already on the phone, they carry the reader's Dynamic Type size,
    /// and they are the vocabulary every other weather reading on iOS uses.
    /// The filled cuts, not the outlines. These are drawn in the mark's orange at 19pt,
    /// and an outline at that size in that colour reads as a thin sketch rather than as a
    /// symbol — the fill is what lets the colour carry.
    var symbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .mainlyClear: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .sleet: return "cloud.sleet.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        }
    }

    /// Said in words for VoiceOver, which cannot read a glyph.
    var label: String {
        switch self {
        case .clear: return "Clear"
        case .mainlyClear: return "Mainly clear"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .sleet: return "Freezing rain"
        case .thunderstorm: return "Thunderstorms"
        }
    }

    /// The WMO codes Open-Meteo answers with, folded into the nine.
    init?(wmo code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .mainlyClear
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 80, 81, 82: self = .rain
        case 66, 67: self = .sleet
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .thunderstorm
        default: return nil
        }
    }
}

/// Recreation.gov availability for one campground over the nights of a stay.
enum AvailabilityLevel: Hashable {
    case open(Int)
    case partial(Int)
    case none
    case firstCome
    /// Recreation.gov refused the request or published nothing. Never a projection.
    case unknown

    var text: String {
        switch self {
        case .open(let n): return "\(n) site\(n == 1 ? "" : "s") open for your nights"
        case .partial(let n): return "\(n) site\(n == 1 ? "" : "s") open some nights"
        case .none: return "No sites open for your nights"
        case .firstCome: return "First-come, first-served"
        case .unknown: return "Availability not published — check Recreation.gov"
        }
    }
}

/// One stop on the composed itinerary.
struct Stop: Identifiable, Hashable {
    var park: Park
    var days: Int
    var start: Date
    var end: Date
    var leg: Leg
    var fromName: String
    var legKey: String
    var fromLat: Double
    var fromLon: Double
    var id: String { park.code }
}

struct HomeLeg: Hashable {
    var leg: Leg
    var date: Date
    var fromName: String
    var toName: String
    var legKey: String
    var fromLat: Double
    var fromLon: Double
    var toLat: Double
    var toLon: Double
}

struct Schedule {
    var city: City
    var stops: [Stop]
    var home: HomeLeg?
    var end: Date
}

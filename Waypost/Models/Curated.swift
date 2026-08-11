import Foundation

// MARK: - The curated field library
//
// This is the dataset the design ships with, converted by `tools/extract-curated.mjs`:
// eight parks with their own colour identity, gates, airports, fuel and nearby stamps;
// the four legs of the seed trip; the ten days of that trip; and the passport book.
//
// What it no longer carries is anything a service can be asked for. The fee, the opening
// hours, the entry reservation, the current alerts, the campgrounds, the lodges, the day
// plans and a written-down August forecast all shipped here once — eight parks' worth of
// facts fixed at build time, presented beside the same facts fetched live for the other
// fifty-five. The park service, Recreation.gov, Open-Meteo, the National Weather Service
// and Apple Maps answer for all of them now, for every park and on the date being asked
// about. What is left is either identity (a name, a place, a colour) or reference the
// services do not publish (which gates a park has, which airports fly there).

struct CuratedLibrary: Decodable {
    let cities: [CuratedCity]
    let parks: [String: CuratedPark]
    let legs: [CuratedLeg]
    let days: [CuratedDay]
    let passport: [PassportUnit]

    enum CodingKeys: String, CodingKey {
        case cities = "CITIES"
        case parks = "P"
        case legs = "LEGS"
        case days = "DAYS"
        case passport = "PASSPORT"
    }

    static let shared: CuratedLibrary = {
        guard let url = Bundle.main.url(forResource: "curated", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("curated.json missing from the bundle")
        }
        do {
            return try JSONDecoder().decode(CuratedLibrary.self, from: data)
        } catch {
            fatalError("curated.json could not be read: \(error)")
        }
    }()

    /// The order the design lists parks in — the dictionary would otherwise shuffle.
    static let parkOrder = ["romo", "arch", "zion", "grte", "yell", "glac", "olym", "grca"]

    var orderedParks: [CuratedPark] {
        Self.parkOrder.compactMap { parks[$0] } + parks.values
            .filter { !Self.parkOrder.contains($0.code) }
            .sorted { $0.name < $1.name }
    }

    func park(_ code: String) -> CuratedPark? { parks[code] }
    func city(_ id: String) -> CuratedCity? { cities.first { $0.id == id } }
}

struct CuratedCity: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let air: String

    var shortName: String { name.split(separator: ",").first.map(String.init) ?? name }
}

struct CuratedPark: Decodable, Identifiable, Hashable {
    let code: String
    let name: String
    let full: String
    let state: String
    let lat: Double
    let lon: Double
    let tag: String
    /// Gateway town.
    let gw: String
    let region: String
    let crowd: String
    /// The park's OKLCH identity — deep, mid, light. Drives every hero card and thumbnail.
    let c: [String]
    /// Offline pack size, e.g. "112 MB".
    let pack: String
    /// Today's weather, once a service has answered. Never bundled.
    ///
    /// This used to ship a written-down high, low, UV, wind, sunrise and sunset for each of
    /// the eight parks in `curated.json` — a single August day, typed once, presented as
    /// this park's weather whatever the date. The forecast services answer for every park in
    /// the country and for any date asked, so the record starts unpublished and only a
    /// service fills it.
    var wx: CuratedWeather = .unpublished
    let gates: [String]
    let airports: [CuratedAirport]
    let fuel: CuratedFuel
    let stamps: [CuratedStamp]
    /// Which catalogue this park came out of. Absent in `curated.json`, which is the
    /// curated library by definition.
    var source: CatalogueSource? = nil
    /// What kind of unit this is — National Park, National Monument, State Park. Absent
    /// in `curated.json`, where every entry is a national park, so it is read off the
    /// full name for those.
    var designation: String? = nil
    /// The park service's own four-letter unit code, when this park is one of its units
    /// and the code is already known. Saves a lookup that did not work anyway.
    var npsCode: String? = nil
    /// The park's own page, where the bundled record knows it.
    ///
    /// `state-parks.json` has carried this for 2,300 of its 3,003 parks all along —
    /// `StateParkRow` even decoded it — and it was dropped on the way into this type, so
    /// the app went and asked Apple Maps for something it already had on disk.
    var website: URL? = nil
    /// The park's photograph on Wikimedia Commons, by filename, where the bundled record
    /// knows one. 1,821 of the 3,003 state parks carry one and the app was drawing a
    /// generated colour tile for every one of them.
    var photoFile: String? = nil

    /// Only what `curated.json` actually carries.
    ///
    /// `wx` is deliberately absent: it is non-optional with a default, and a synthesised
    /// decoder does not fall back to a default for a missing key — it throws, which took
    /// the whole library down at launch the moment the bundled forecasts came out of the
    /// file. Leaving it out of the keys is what makes the default the value. The optional
    /// fields below it decode as normal, absent or not.
    enum CodingKeys: String, CodingKey {
        case code, name, full, state, lat, lon, tag, gw, region, crowd, c, pack
        case gates, airports, fuel, stamps
        case source, designation, npsCode, website, photoFile
    }

    var id: String { code }

    /// Whether the card should draw a map rather than a photograph. A state park with no
    /// picture named on Wikimedia Commons has no photo to show — but it has coordinates, so
    /// the tile becomes a pin on the map instead of a blank colour field. National parks
    /// and photographed state parks always have a picture, so this is false for them.
    var usesMapHero: Bool { isStatePark && photoFile == nil }

    /// Whether this is a state park rather than one of the park service's units. The
    /// prefix is put on when a row of `state-parks.json` is converted, and is the one
    /// thing that says so on every path into this type.
    var isStatePark: Bool { code.hasPrefix("sp-") }

    /// The designation, always in words. Never "Protected area" for something whose own
    /// name says National Park, and never "National Park" for something that isn't one.
    var designationLabel: String {
        if let designation, !designation.isEmpty { return ParkDesignation.tidy(designation) }
        if let inName = ParkDesignation.inName(full) { return inName }
        return source == nil ? "National Park" : "Protected area"
    }
    /// Named wherever the park is shown, so a live record is never read as a curated one.
    var sourceName: String { (source ?? .curated).rawValue }

    /// The state in words, wherever the record only carries the postal code.
    ///
    /// `curated.json` writes "Colorado"; `national-parks.json` and the park service write
    /// "CO", so the same kicker read "Colorado · National Park" on one park and "CA ·
    /// National Park" on the next. Several of the codes are a genuine stumble at a glance
    /// — MI, MN, MO, MS, MT are five states and one letter apart — and a kicker is read in
    /// passing or not at all. A park spanning states carries them comma-separated, and
    /// each is expanded in place.
    var stateName: String { USState.spellOut(state) }

    /// Megabytes, for the storage total on the Profile screen.
    var packMB: Int { Int(pack.split(separator: " ").first.flatMap { Int($0) } ?? 0) }
}

struct CuratedWeather: Decodable, Hashable {
    let hi: Int
    let lo: Int
    /// "11 — extreme"
    let uv: String
    let wind: String
    /// Sunrise / sunset.
    let sr: String
    let ss: String
    let note: String
    /// Which service answered. Nil until one has.
    var source: String? = nil

    var uvIndex: String { uv.split(separator: " ").first.map(String.init) ?? uv }
    var uvWord: String { uv.components(separatedBy: "— ").last ?? "" }
}

struct CuratedAirport: Decodable, Hashable, Identifiable {
    let code: String
    let name: String
    let drive: String
    let note: String
    let best: Bool?
    var id: String { code }
}

struct CuratedFuel: Decodable, Hashable {
    let gas: [String]
    let fast: [String]
    let slow: [String]
}

/// Reading a unit's designation out of its own name — "Petrified Forest National Park"
/// says what it is. Kept here rather than in the OSM bridge because the curated library
/// needs it too: those eight records carry no designation field at all.
enum ParkDesignation {
    static let titles = [
        "National Park and Preserve", "National Park", "National Monument",
        "National Preserve", "National Seashore", "National Lakeshore",
        "National Recreation Area", "National Historical Park", "National Historic Site",
        "National Battlefield", "National Forest", "National Wildlife Refuge",
        "State Park", "State Recreation Area", "State Forest",
        "Wildlife Management Area", "Wilderness",
    ]

    static func inName(_ name: String) -> String? {
        titles.first { name.localizedCaseInsensitiveContains($0) }
    }

    /// Mappers type "state park" as often as "State Park". Same designation, and it
    /// should not look like two.
    static func tidy(_ raw: String) -> String {
        if let known = titles.first(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) {
            return known
        }
        return raw.capitalized(with: .current)
    }
}

/// Where a park record came from.
enum CatalogueSource: String, Decodable, Hashable {
    case nps = "NPS"
    case onDevice = "ParkHop"
    case appleMaps = "Apple Maps"
    case openStreetMap = "OpenStreetMap"
    case curated = "the curated library"
}

struct CuratedAlert: Decodable, Hashable, Identifiable {
    let cat: String
    let title: String
    let body: String
    var id: String { cat + title }
}

struct CuratedStamp: Decodable, Hashable, Identifiable {
    let name: String
    let city: String
    let dist: String
    let desig: String
    var id: String { name }
}

struct CuratedLeg: Decodable, Hashable, Identifiable {
    let from: String
    let to: String
    let mi: Int
    let drive: String
    let date: String
    let road: String
    let ev: [String]
    let fly: CuratedFly?

    var id: String { from + to }
}

struct CuratedFly: Decodable, Hashable {
    let via: String
    let time: String
    let note: String
}

/// One day of the seed trip: either a driving leg or a day in a park.
struct CuratedDay: Decodable, Hashable, Identifiable {
    let d: Int
    let date: String
    let long: String
    let kind: String
    let leg: Int?
    let code: String?
    /// Day n of m in this park.
    let n: Int?
    let of: Int?

    var id: Int { d }
    var isPark: Bool { kind == "park" }
    var isLeg: Bool { kind == "leg" }
}

struct PassportUnit: Decodable, Hashable, Identifiable {
    let code: String
    let name: String
    let city: String
    var id: String { code }
}

// MARK: - Permit windows
//
// The design hard-codes the next drop per park, because those release times are real and
// published: Bear Lake at 5 pm MT, Arches timed entry at 7 pm MT, the Angels Landing
// lottery closing at 3 pm MT, Glacier's vehicle reservations at 7 pm MT.

struct PermitDrop: Hashable {
    let what: String
    let when: String
    let countdown: String

    static let byPark: [String: PermitDrop] = [
        "romo": .init(what: "Next-day Bear Lake corridor permits", when: "release 5:00 pm MT", countdown: "7 h 19 m"),
        "arch": .init(what: "Next-day timed-entry tickets", when: "release 7:00 pm MT", countdown: "9 h 19 m"),
        "zion": .init(what: "Angels Landing lottery closes", when: "today 3:00 pm MT", countdown: "5 h 19 m"),
        "glac": .init(what: "Next-day vehicle reservations", when: "release 7:00 pm MT", countdown: "9 h 19 m"),
    ]
}

/// The states, by postal code.
///
/// Only ever used to spell one out: nothing in the app abbreviates a state the reader has
/// given it in full.
enum USState {
    static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
        "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
        "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
        "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
        "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "AS": "American Samoa", "GU": "Guam", "MP": "Northern Mariana Islands",
        "PR": "Puerto Rico", "VI": "US Virgin Islands",
    ]

    /// "CA" → "California"; "ID, MT, WY" → "Idaho, Montana and Wyoming". Anything already
    /// spelled out, or not a code at all, is handed back untouched.
    static func spellOut(_ raw: String) -> String {
        let parts = raw
            .split(whereSeparator: { $0 == "," || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return raw }
        let spelled = parts.map { names[$0.uppercased()] ?? $0 }
        switch spelled.count {
        case 1: return spelled[0]
        case 2: return "\(spelled[0]) and \(spelled[1])"
        default: return spelled.dropLast().joined(separator: ", ") + " and " + (spelled.last ?? "")
        }
    }
}

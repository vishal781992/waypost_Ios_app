import Foundation

// MARK: - The curated field library
//
// This is the dataset the design ships with, converted verbatim by
// `tools/extract-curated.mjs`: eight parks with their own colour identity, August
// normals, gates, campgrounds, day plans and nearby stamps; the four legs of the seed
// trip; the ten days of that trip; and the passport book.
//
// It is *curated*, and the app says so wherever it is shown. The live services in
// `Services/` overlay it when a source answers; nothing here is presented as a
// measurement taken today.

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
    let fee: String
    let hours: String
    let res: Bool
    let resNote: String
    /// The park's OKLCH identity — deep, mid, light. Drives every hero card and thumbnail.
    let c: [String]
    /// Offline pack size, e.g. "112 MB".
    let pack: String
    var wx: CuratedWeather
    let gates: [String]
    let parking: String
    let airports: [CuratedAirport]
    let camping: [CuratedCamp]
    let lodging: [CuratedLodging]
    let fuel: CuratedFuel
    let alerts: [CuratedAlert]
    let days: [CuratedDayPlan]
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

    var id: String { code }

    /// The designation, always in words. Never "Protected area" for something whose own
    /// name says National Park, and never "National Park" for something that isn't one.
    var designationLabel: String {
        if let designation, !designation.isEmpty { return ParkDesignation.tidy(designation) }
        if let inName = ParkDesignation.inName(full) { return inName }
        return source == nil ? "National Park" : "Protected area"
    }
    /// Named wherever the park is shown, so a live record is never read as a curated one.
    var sourceName: String { (source ?? .curated).rawValue }

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

struct CuratedCamp: Decodable, Hashable, Identifiable {
    let name: String
    let whereText: String
    let sites: String
    let price: String
    let status: String
    let src: String
    /// The availability chip the design shows: "3 left", "Full", "Walk-up", "Waitlist"…
    let av: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, sites, price, status, src, av
        case whereText = "where"
    }

    /// Availability colour follows the wording, as in the design.
    var isOpen: Bool { av.contains("left") || av == "Open" }
    var isClosed: Bool { av == "Full" }
}

struct CuratedLodging: Decodable, Hashable, Identifiable {
    let name: String
    let whereText: String
    let price: String
    let note: String
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, price, note
        case whereText = "where"
    }
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

struct CuratedDayPlan: Decodable, Hashable, Identifiable {
    let title: String
    let items: [CuratedPlanItem]
    var id: String { title }
}

struct CuratedPlanItem: Decodable, Hashable, Identifiable {
    let time: String
    let text: String
    var id: String { time + text }
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

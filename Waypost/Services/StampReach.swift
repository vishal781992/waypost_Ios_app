import CoreLocation
import Foundation

/// Somewhere a stamp can be collected, and how near counts as being there.
///
/// Every coordinate the phone holds is one point in the middle of a place. That is fine
/// for ordering a list by distance and useless for deciding whether somebody is *in* a
/// park: Yellowstone is sixty miles across, so four days inside it need never come within
/// thirty miles of its pin, while Hovenweep is half a square mile and a mile around its
/// pin is generous. One radius cannot serve both.
///
/// So the radius is the park's own size. Treat it as a circle of the same area, and add a
/// mile of grace on top — the mile forgives what a mile is good at forgiving: a soft GPS
/// fix, a car park outside the gate, a boundary the data draws roughly. Never less than
/// three miles all in, which covers the smallest monuments and the worst fixes together.
struct Stampable: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case national
        /// Everything else the park service runs — monuments, historic sites, seashores.
        case unit
        case state
    }

    var name: String
    /// "National Park", "National Monument", "State Park".
    var designation: String
    /// The town or the state, as the source that knew about it wrote it down.
    var place: String
    var lat: Double
    var lon: Double
    var kind: Kind
    /// How big it is, where that is known. Nil for every state park and every park-service
    /// unit — nothing on the phone records their size — and those fall to the floor below,
    /// which is the right answer for the small places most of them are.
    var acres: Double?

    var id: String { name + "|" + place }

    /// The stamp's code.
    ///
    /// The same scheme `AppState.stampKey(forName:)` has always used, deliberately: a
    /// park stamped from here and the same park stamped from a park screen's Nearby tab
    /// have to be one stamp, or the book shows it twice and the count is wrong.
    var key: String { Self.key(name) }

    static func key(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[^a-z]", with: "",
                                               options: .regularExpression)
    }

    // MARK: The reach

    /// 640 acres to the square mile.
    private static let acresPerSquareMile: Double = 640
    /// The user's mile, kept as what it is good at.
    static let graceMiles: Double = 1
    /// Never tighter than this, whatever the size says.
    static let floorMiles: Double = 3

    /// How far from the middle still counts as being there.
    var reachMiles: Double {
        let equivalent = acres.map { sqrt(($0 / Self.acresPerSquareMile) / .pi) } ?? 0
        return max(Self.floorMiles, equivalent + Self.graceMiles)
    }

    var reachMetres: CLLocationDistance { reachMiles * 1609.344 }

    /// Miles from a coordinate to the middle of this.
    func miles(from lat: Double, _ lon: Double) -> Double {
        Geo.haversine((lat, lon), (self.lat, self.lon))
    }

}

/// A place, and how far away it is from where the question was asked.
///
/// Top-level rather than nested in `StampCatalogue`, deliberately: a type nested inside a
/// `@MainActor` one is isolated too, and a `Hashable` whose `==` is isolated is a
/// conformance the compiler has to complain about. Nothing about a distance needs an actor.
struct RankedStamp: Identifiable, Hashable {
    var place: Stampable
    /// To the middle.
    var miles: Double
    /// To the edge of its reach — zero when inside.
    var toEdge: Double

    var id: String { place.id }
    var isInReach: Bool { toEdge == 0 }
}

// MARK: - The register

/// Everywhere in the country a stamp can be collected, ordered by how near it is.
///
/// Two sources need no network and cover the whole country: the sixty-two national parks
/// and the three thousand state parks, both already on the phone with coordinates. The
/// park service's other four hundred units — the monuments, the historic sites, the
/// battlefields — come from the register `NearbyUnits` already fetches once per launch,
/// and are folded in when they arrive. Nothing waits on them: the offline list answers
/// immediately and the register only ever adds to it.
@MainActor
enum StampCatalogue {

    // MARK: The sources

    /// The national register, with each park's size against it.
    private static let national: [Stampable] = NationalParks.all.map { park in
        Stampable(name: park.name,
                  designation: park.designation,
                  place: USState.spellOut(park.state),
                  lat: park.lat, lon: park.lon,
                  kind: .national,
                  acres: park.npsCode.flatMap { ParkAcreage.byNPSCode[$0] })
    }

    /// The state parks, deduplicated the way the catalogue screen deduplicates them.
    private static let state: [Stampable] = StateParkTable.all.map { entry in
        Stampable(name: entry.row.n,
                  designation: "State Park",
                  place: USState.spellOut(entry.row.s),
                  lat: entry.row.lat, lon: entry.row.lon,
                  kind: .state,
                  acres: nil)
    }

    /// The park service's other units. Empty until the register answers, and it may never
    /// answer — on a phone with no signal this list is the two above and nothing is
    /// missing that the reader can tell.
    private(set) static var units: [Stampable] = [] {
        didSet { everywhere = national + state + units }
    }

    /// The three sources as one list, joined once rather than on every fix.
    ///
    /// `near` runs on every hundred metres the phone moves. Concatenating three and a half
    /// thousand rows there is an allocation and a copy per update, for a list that changes
    /// once per launch — the same mistake the state catalogue made when it rebuilt its
    /// index inside a redraw.
    private static var everywhere: [Stampable] = national + state

    private static var adopting = false

    /// Fold the park service's register in, once.
    static func adoptServiceUnits() async {
        guard units.isEmpty, !adopting else { return }
        adopting = true
        let rows = await NearbyUnits.shared.serviceUnits()
        units = rows.map { row in
            Stampable(name: row.full.isEmpty ? row.name : row.full,
                      designation: row.designation ?? "National Park Service unit",
                      place: USState.spellOut(row.state),
                      lat: row.lat, lon: row.lon,
                      kind: .unit,
                      acres: nil)
        }
        adopting = false
    }

    // MARK: Asking

    /// The nearest places to a coordinate, nearest edge first.
    ///
    /// Ordered by distance to the *edge* of each reach rather than to its middle, so a
    /// national park you are standing inside comes above a state park whose pin is five
    /// miles nearer. Ties — everything you are inside — fall back to the middle, which
    /// puts the smaller, more specific place first when two overlap.
    static func near(lat: Double, lon: Double, limit: Int = 24) -> [RankedStamp] {
        var out: [RankedStamp] = []
        out.reserveCapacity(limit * 4)
        for place in everywhere {
            let miles = place.miles(from: lat, lon)
            // A cheap gate before the sort. Nothing five hundred miles away is ever an
            // answer here, and skipping it keeps this to one pass over three thousand rows.
            guard miles < 500 else { continue }
            out.append(RankedStamp(place: place, miles: miles,
                              toEdge: max(0, miles - place.reachMiles)))
        }
        out.sort { a, b in
            a.toEdge == b.toEdge ? a.miles < b.miles : a.toEdge < b.toEdge
        }

        // The same place can be in two of the three sources — a national park is in the
        // register as a unit too, and a state park table repeats a few names across
        // sources. One stamp, one row.
        var seen = Set<String>()
        return out.filter { seen.insert($0.place.key).inserted }.prefix(limit).map { $0 }
    }
}

// MARK: - How big each park is

/// The size of every national park, in acres.
///
/// Written down here rather than generated into `national-parks.json`, because the
/// generator that built that file needs the network and the reach rule needs a number
/// today. These are the park service's own published acreages, rounded to the acre.
///
/// The rule tolerates being a little wrong, which is why writing them down is acceptable:
/// the radius is a square root, so a fifth off the area moves the reach by a tenth of
/// itself — a mile at Yosemite, nothing at all anywhere the three-mile floor already
/// governs. Worth checking against the park service's acreage report when the generator
/// can reach the network again.
enum ParkAcreage {
    static let byNPSCode: [String: Double] = [
        "acad": 49_076,     // Acadia
        "arch": 76_679,     // Arches
        "badl": 242_756,    // Badlands
        "bibe": 801_163,    // Big Bend
        "bisc": 172_971,    // Biscayne
        "blca": 30_750,     // Black Canyon of the Gunnison
        "brca": 35_835,     // Bryce Canyon
        "cany": 337_598,    // Canyonlands
        "care": 241_904,    // Capitol Reef
        "cave": 46_766,     // Carlsbad Caverns
        "chis": 249_561,    // Channel Islands
        "cong": 26_476,     // Congaree
        "crla": 183_224,    // Crater Lake
        "cuva": 32_572,     // Cuyahoga Valley
        "deva": 3_408_395,  // Death Valley
        "dena": 4_740_911,  // Denali
        "drto": 64_701,     // Dry Tortugas
        "ever": 1_508_938,  // Everglades
        "gaar": 7_523_897,  // Gates of the Arctic
        "jeff": 192,        // Gateway Arch — the smallest in the register
        "glac": 1_013_126,  // Glacier
        "glba": 3_223_384,  // Glacier Bay
        "grca": 1_201_647,  // Grand Canyon
        "grte": 310_044,    // Grand Teton
        "grba": 77_180,     // Great Basin
        "grsa": 107_342,    // Great Sand Dunes
        "grsm": 522_427,    // Great Smoky Mountains
        "gumo": 86_367,     // Guadalupe Mountains
        "hale": 33_265,     // Haleakalā
        "havo": 325_605,    // Hawaiʻi Volcanoes
        "hosp": 5_554,      // Hot Springs
        "indu": 15_349,     // Indiana Dunes
        "isro": 571_790,    // Isle Royale
        "jotr": 795_156,    // Joshua Tree
        "katm": 3_674_530,  // Katmai
        "kefj": 669_984,    // Kenai Fjords
        // Sequoia and Kings Canyon share a unit code because the park service
        // administers them as one. The reach is the pair's, which is what somebody
        // standing in either of them is inside.
        "seki": 865_964,
        "kova": 1_750_717,  // Kobuk Valley
        "lacl": 2_619_733,  // Lake Clark
        "lavo": 106_589,    // Lassen Volcanic
        "maca": 54_012,     // Mammoth Cave
        "meve": 52_485,     // Mesa Verde
        "mora": 236_381,    // Mount Rainier
        "npsa": 8_257,      // American Samoa
        "neri": 7_021,      // New River Gorge
        "noca": 504_781,    // North Cascades
        "olym": 922_650,    // Olympic
        "pefo": 221_391,    // Petrified Forest
        "pinn": 26_606,     // Pinnacles
        "romo": 265_461,    // Rocky Mountain
        "sagu": 92_867,     // Saguaro
        "shen": 199_224,    // Shenandoah
        "thro": 70_447,     // Theodore Roosevelt
        "viis": 15_052,     // Virgin Islands
        "voya": 218_200,    // Voyageurs
        "whsa": 145_762,    // White Sands
        "wica": 33_970,     // Wind Cave
        "wrst": 8_323_148,  // Wrangell–St. Elias — the largest
        "yell": 2_219_791,  // Yellowstone
        "yose": 761_748,    // Yosemite
        "zion": 147_242,    // Zion
    ]
}

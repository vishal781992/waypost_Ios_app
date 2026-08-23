import Foundation

/// Every national park in the country, on the phone.
///
/// Nine and a half kilobytes buys the whole list: name, full name, state, coordinates and
/// designation for all sixty-two. That is small enough to ship, and it changes what the
/// search is. Before this, finding a park meant asking Apple Maps or Overpass and waiting
/// — offline you could find eight. Now every park answers instantly, with no network, and
/// the live sources become enrichment rather than the only way in.
///
/// Built from Wikidata for the parks and the US Census geocoder for the states, by
/// `tools/build-national-parks.mjs`. It is a list of places, not a claim about any of
/// them: no fees, no hours, no conditions. Those still come from the park.
struct NationalPark: Decodable, Hashable, Identifiable {
    let code: String
    /// The park service's own four-letter unit code — `badl`, `acad`, `seki`.
    ///
    /// Carried in the bundled data rather than looked up, because looking it up did not
    /// work: the app searched NPS for the park's *full* name, and that search matches on
    /// any word in it, so "Badlands National Park" came back as 452 units in alphabetical
    /// order and the ten the app asked for were Abraham Lincoln through Alibates. Every
    /// park failed the same way. Sequoia and Kings Canyon share `seki`, which is how the
    /// park service administers them.
    let npsCode: String?
    let name: String
    let full: String
    let state: String
    let lat: Double
    let lon: Double
    let designation: String

    var id: String { code }
}

enum NationalParks {
    /// The register as `CuratedPark`s, built once for the whole launch.
    ///
    /// `CuratedPark(bundled:)` is not free: it lowercases the full name and scans it for a
    /// terrain word, hashes the code into three OKLCH strings, and allocates four arrays.
    /// Sixty-two of those is nothing once — and the home screen, Discover, Profile and the
    /// atlas were each doing it inside a computed property read from `body`, so it happened
    /// on every redraw of every one of them, several times over on a screen that reads the
    /// list from more than one place. `Discover` built it three times per keystroke.
    ///
    /// Safe to hold, because it is a pure function of a file that cannot change while the
    /// app is running.
    static let allCurated: [CuratedPark] = all.map(CuratedPark.init(bundled:))

    static let all: [NationalPark] = {
        guard let url = Bundle.main.url(forResource: "national-parks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parks = try? JSONDecoder().decode([NationalPark].self, from: data)
        else {
            assertionFailure("national-parks.json missing from the bundle")
            return []
        }
        return parks
    }()

    /// Name, full name or state, matched locally. The whole list is 62 rows, so this is
    /// a linear scan and is still faster than any request could be.
    static func search(_ query: String) -> [NationalPark] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return [] }

        let stateCode = USStates.abbreviation(for: needle)
        return all.filter { park in
            if let stateCode, park.state.contains(stateCode) { return true }
            return park.name.lowercased().contains(needle)
                || park.full.lowercased().contains(needle)
        }
    }

    /// The parks nearest a point, for the shelf and the recommendation.
    static func near(lat: Double, lon: Double, limit: Int = 8) -> [(park: NationalPark, miles: Int)] {
        all.map { ($0, Geo.haversine((lat, lon), ($0.lat, $0.lon))) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (park: $0.0, miles: Int($0.1.rounded())) }
    }

    static func park(code: String) -> NationalPark? { all.first { $0.code == code } }
}

extension CuratedPark {
    /// A bundled park, in the shape the screens draw. Everything a live record leaves
    /// blank is blank here too — this list knows where a park is and what it is called,
    /// and says nothing it does not know.
    init(bundled park: NationalPark) {
        self.init(
            code: park.code,
            name: park.name,
            full: park.full,
            state: park.state,
            lat: park.lat,
            lon: park.lon,
            tag: "Fees, hours and closures come from the park.",
            gw: "",
            region: CuratedPark.region(for: park.full),
            crowd: park.designation,
            c: CuratedPark.palette(for: park.code),
            pack: "Not downloaded",
            gates: [],
            airports: [],
            fuel: CuratedFuel(gas: [], fast: [], slow: []),
            stamps: [],
            source: .onDevice,
            designation: park.designation,
            npsCode: park.npsCode
        )
    }
}


extension CuratedPark {
    /// One of the three thousand state parks that ship with the app.
    ///
    /// These rows carried a name, a state and coordinates and opened nothing — tapping
    /// one produced a toast explaining that a name and a location is all anybody
    /// publishes. That was true of the row and untrue of the park: with coordinates it
    /// gets a photograph, today's weather, the chargers and shops around it, and a way
    /// into the trip builder, all from sources that answer for anywhere.
    init(stateRow row: StateParkRow) {
        // Only `http(s)`, through the same guard every other remote link goes through:
        // these rows are world-editable upstream.
        let site = safeURL(row.w)
        let short = CuratedPark.shortName(row.n)
        self.init(
            code: CuratedPark.stateParkCode(for: row.n),
            name: short,
            full: row.n,
            state: row.s,
            lat: row.lat,
            lon: row.lon,
            tag: "Fees, hours and closures come from the park.",
            gw: "",
            region: CuratedPark.region(for: row.n),
            crowd: ParkDesignation.inName(row.n) ?? "State Park",
            c: CuratedPark.palette(for: row.n),
            pack: "Not downloaded",
            gates: [],
            airports: [],
            fuel: CuratedFuel(gas: [], fast: [], slow: []),
            stamps: [],
            source: .onDevice,
            designation: ParkDesignation.inName(row.n) ?? "State Park",
            website: site,
            photoFile: row.i
        )
    }
}

extension CuratedPark {
    /// The code a shipped state park is filed under.
    ///
    /// One implementation, used by both the record and the index that finds it. Two copies
    /// of a slugging rule drift, and when they drift the lookup does not fail loudly — it
    /// simply never matches, and a saved park stops opening.
    static func stateParkCode(for name: String) -> String {
        "sp-" + name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension Datasets {
    /// A shipped state park by the code the app gives it. A dictionary hit now, not a scan.
    func statePark(code: String) -> CuratedPark? {
        guard code.hasPrefix("sp-") else { return nil }
        return stateParkIndex[code].map(CuratedPark.init(stateRow:))
    }
}

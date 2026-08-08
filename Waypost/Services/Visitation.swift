import Foundation

/// How many people actually visit a park in each month of the year.
///
/// The park service counts every visitor and publishes the monthly totals back to 1979, so
/// "how busy is it in August" has a measured answer for every national park in the country.
/// The app used to guess instead: May through September was hard-coded as the busy season,
/// which is true of Yellowstone and wrong for a quarter of the catalogue. Big Bend is at its
/// emptiest in August, Hawai'i Volcanoes peaks in January, and Great Smoky Mountains peaks
/// in October — none of which a rule about summer can know.
///
/// Bundled rather than fetched: the figures come out of a report viewer with no JSON API
/// (see `tools/build-visitation.mjs`), and a park's shape of the year does not change
/// between one launch and the next. Shipping it means the curve is there with no signal.
enum Visitation {
    struct Profile: Decodable, Hashable {
        /// Twelve monthly visitor counts, January first, averaged over `years`.
        let monthly: [Int]
        /// The complete calendar years the average was taken over.
        let years: [Int]

        var peakIndex: Int {
            monthly.firstIndex(of: monthly.max() ?? 0) ?? 0
        }

        var quietestIndex: Int {
            monthly.firstIndex(of: monthly.min() ?? 0) ?? 0
        }

        /// A month's height against the busiest one, 0...1. The bar chart's y-axis, and the
        /// only honest way to compare a park with four million visitors to one with forty
        /// thousand — the shape is comparable where the counts are not.
        func share(_ index: Int) -> Double {
            guard let peak = monthly.max(), peak > 0,
                  monthly.indices.contains(index) else { return 0 }
            return Double(monthly[index]) / Double(peak)
        }
    }

    /// Keyed by the app's own park code — two parks share the NPS code `seki`, so that one
    /// cannot be the key.
    static let all: [String: Profile] = {
        guard let url = Bundle.main.url(forResource: "visitation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Profile].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// Nil for a park the park service does not count — every state park, and anything
    /// found through the directory rather than bundled.
    ///
    /// Two codes, because the app has two catalogues: the bundled sixty-two call Grand
    /// Canyon `np-grand-canyon` and the curated eight call it `grca`. The file carries both
    /// keys; this tries both in case a park arrives from somewhere that carries only one.
    static func profile(for park: CuratedPark) -> Profile? {
        if let hit = all[park.code] { return hit }
        return park.npsCode.flatMap { all[$0] }
    }

    static let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    static func monthName(_ index: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        return names.indices.contains(index) ? names[index] : ""
    }
}

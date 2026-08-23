import Foundation
import MapKit

/// The outline of a US state, for the one thing the atlas cannot ask MapKit for.
///
/// MapKit vends no administrative boundaries — no map SDK does — so filling Colorado when
/// its last park is collected needs the shape of Colorado on disk. That is the only new
/// asset the atlas wants, and it is optional on purpose: with the file absent the map draws
/// its pins and its tiles exactly as it does with it, and simply fills nothing. An absent
/// boundary is a boundary this app has not been given, not a state nobody has finished, and
/// the two must not look alike.
///
/// The file is `us-states.json` in `Resources`, written by `tools/build-state-shapes.mjs`
/// from the Census Bureau's own cartographic boundary file. Its shape is deliberately
/// dumb — a state code against a list of rings, each ring a flat list of
/// `[longitude, latitude]` — so it is small, decodes without a model, and can be checked by
/// eye. Longitude first, because that is the order GeoJSON uses and translating on the way
/// in is where this sort of file usually goes wrong.
@MainActor
@Observable
final class StateShapes {
    static let shared = StateShapes()

    /// Rings by state code. Empty until `load` has run, and empty afterwards too when
    /// there is no file to read.
    private(set) var rings: [String: [[CLLocationCoordinate2D]]] = [:]
    private(set) var didLoad = false
    private let failures = FailureLog()

    /// Whether any boundary at all is available. The atlas asks before it offers a
    /// completion fill, so the feature is present or absent as a whole rather than
    /// filling the states that happen to be in the file.
    var isAvailable: Bool { !rings.isEmpty }

    /// What went wrong, for the diagnostics panel. Nil where the file simply is not
    /// bundled, which is not a failure.
    var failure: String? { failures.failures["state-shapes"] }

    private init() {}

    /// Reads the file once per launch, off the main thread.
    ///
    /// A quarter of a megabyte of JSON is a few tens of milliseconds to decode and turn
    /// into coordinates — nothing in the abstract, and a visible stall if it happens while
    /// the atlas is being pushed, which is the only moment it would ever be asked for. So
    /// the map opens first and the fills arrive a beat later; there is nothing to see in
    /// between but the state that has not been filled yet.
    ///
    /// Cheap enough to call from a `.task` on every appearance — the second call returns
    /// on the first line.
    func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let url = Bundle.main.url(forResource: "us-states", withExtension: "json") else {
            // Not bundled. Deliberately not a failure: the atlas works without it.
            return
        }
        Task { [weak self] in
            do {
                let decoded = try await Self.decode(url)
                self?.rings = decoded
            } catch {
                self?.failures.note("state-shapes", error)
            }
        }
    }

    /// Off the actor, because none of this touches it.
    private nonisolated static func decode(_ url: URL) async throws -> [String: [[CLLocationCoordinate2D]]] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let raw = try JSONDecoder().decode([String: [[[Double]]]].self, from: data)
        var out: [String: [[CLLocationCoordinate2D]]] = [:]
        out.reserveCapacity(raw.count)
        for (code, shape) in raw {
            let converted = shape.compactMap { ring -> [CLLocationCoordinate2D]? in
                // A ring of fewer than three points is not a polygon, and MapKit draws a
                // hairline artefact rather than refusing it.
                guard ring.count >= 3 else { return nil }
                return ring.compactMap { pair in
                    guard pair.count == 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
            }
            if !converted.isEmpty { out[code.uppercased()] = converted }
        }
        return out
    }

    func polygons(for state: String) -> [[CLLocationCoordinate2D]] {
        rings[state.uppercased()] ?? []
    }
}

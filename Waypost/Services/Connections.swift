import Foundation
import Network
import SwiftUI

/// Every way this app reaches outside the phone, and whether it has worked.
///
/// The Profile screen used to show a green dot beside *NPS · Open-Meteo · Recreation.gov*
/// that was drawn green whatever had happened, and a row reading *Live sources — Re-wiring
/// next pass*. The first was the app's one rule broken in its own settings: it claimed
/// three services were healthy without having asked. This asks.
///
/// Three states, and the difference between them is the whole point. **Not needed yet** is
/// a source nothing has had cause to call this launch, and is not a fault. **Answered** is
/// a request that came back. **Did not answer** carries the reason it did not. A source
/// nobody has used and a source that is down must never look the same.
@MainActor
@Observable
final class Connections {
    static let shared = Connections()

    enum Health: Equatable {
        case untouched
        case answered(Date)
        case failed(String, Date)
    }

    /// One outside dependency, named the way somebody reading it would name it.
    struct Source: Identifiable {
        var name: String
        var what: String
        /// The keys `FailureLog` files its notes under. Transcribed from the `note` calls
        /// in the services themselves, not invented — a key that matches nothing would
        /// leave a source permanently reading *not needed yet*, which is the one answer
        /// this screen must never give wrongly.
        var keys: [String]
        /// The hosts that answer for it. `HTTP` records every response by host, so these
        /// are what turn a source green without any service having to report success.
        var hosts: [String] = []
        /// True where the app cannot do its main job without it.
        var essential: Bool = false
        var id: String { name }
    }

    /// What the app talks to, in the order it matters.
    static let sources: [Source] = [
        Source(name: "Appwrite",
               what: "This app's own backend. Nothing of yours goes through it yet — the only thing it is asked is whether it is there, which is what the ping below does. Not essential: everything the app does today, it does on this phone.",
               keys: [Backend.key],
               hosts: ["sfo.cloud.appwrite.io"]),
        Source(name: "National Park Service",
               what: "Fees, opening times, alerts, campgrounds and things to do — the substance of every park screen. Reached through the Waypost proxy, which holds the key.",
               keys: ["NPS API"],
               hosts: ["waypost-proxy.parkhop.workers.dev"],
               essential: true),
        Source(name: "OSRM",
               what: "The open routing server. It measures the many drives taken to put things in order — which roadside park is the smallest detour, how far the nearest ten are — and stands behind Apple Maps on a trip leg Apple declines to measure. A public server shared by everyone who uses it, which is why the drives a reader is actually shown no longer go through it.",
               keys: ["routing (OSRM)"],
               hosts: ["router.project-osrm.org"]),
        Source(name: "Open-Meteo",
               what: "The forecast for a park on a date, and ten years of the same calendar window beyond the sixteen-day horizon.",
               keys: ["forecast (Open-Meteo)", "climate normals (Open-Meteo archive)"],
               hosts: ["api.open-meteo.com", "archive-api.open-meteo.com"]),
        Source(name: "Recreation.gov",
               what: "How many campsites are free tonight, for the campgrounds that book there.",
               keys: ["campsite availability (Recreation.gov)", "campgrounds (Recreation.gov)"],
               hosts: ["www.recreation.gov", "ridb.recreation.gov"]),
        Source(name: "Apple Maps",
               what: "Every distance and wheel time on a trip leg, and its traffic. Fuel, charging, food and beds near a park; a park's own website and phone number; the pictures of routes and the atlas. On the phone's own framework — it answers without going through this app's network layer, so it shows as heard from only when something asks it. Its allowance is this phone's rather than the app's, so it does not run short because other people are planning trips.",
               keys: ["parks (Apple Maps)", "city lookup", "EV charging", "routing (Apple Maps)"],
               essential: true),
        Source(name: "OpenStreetMap",
               what: "State parks and protected areas Apple Maps has no record of, place lookup and search suggestions.",
               keys: ["protected areas (Overpass)", "place lookup (Nominatim)", "suggestions (Nominatim)", "fuel (OpenStreetMap)"],
               hosts: ["overpass-api.de", "overpass.kumi.systems", "overpass.private.coffee",
                       "nominatim.openstreetmap.org"]),
        Source(name: "Wikimedia Commons",
               what: "The photograph on every park card. Kept on the phone once it has been seen, so this goes quiet after the first look.",
               keys: ["park photographs (Wikipedia)", "park photographs (NPS)"],
               hosts: ["commons.wikimedia.org", "en.wikipedia.org"]),
        Source(name: "Google Places",
               what: "Somewhere to stay near a park, where Apple Maps returns nothing.",
               keys: ["stays (Google Places)"]),
        Source(name: "Apple Weather",
               what: "Switched off in this build: WeatherKit needs a paid developer entitlement, so Open-Meteo answers instead. Listed because the code path is still here.",
               keys: ["Apple Weather (WeatherKit)"]),
        Source(name: "State boundaries",
               what: "The shape of a state, for filling it on the atlas when its last park is collected. Bundled with the app — it reaches nothing, and is listed so a missing file reads as missing rather than as broken.",
               keys: ["state-shapes"]),
    ]

    private(set) var health: [String: Health] = [:]
    /// Whether the phone has a route to the internet at all, from the system rather than
    /// from a request that happened to fail.
    private(set) var isOnline: Bool?
    private(set) var connectionKind: String?
    /// Whether the proxy answered its own health endpoint, and when it was asked.
    private(set) var proxyHealthy: Bool?
    private(set) var proxyCheckedAt: Date?

    private var monitor: NWPathMonitor?

    private init() {}

    // MARK: Recording

    /// Called by `FailureLog` for every source that fails, so nothing has to remember to
    /// report — a catch that notes its failure is already telling this.
    func record(_ key: String, failed reason: String) {
        health[key] = .failed(String(reason.prefix(160)), Date())
    }

    /// Called where a request comes back. Only the successes that matter are wired up:
    /// enough that a working app reads as working, without a call at every line.
    func record(answered key: String) {
        health[key] = .answered(Date())
    }

    /// The state of one row, from whichever of its keys or hosts has the most recent word.
    func health(of source: Source) -> Health {
        var best: Health = .untouched
        var bestAt = Date.distantPast
        for key in source.keys + source.hosts {
            switch health[key] {
            case .answered(let at) where at > bestAt: best = .answered(at); bestAt = at
            case .failed(let why, let at) where at > bestAt: best = .failed(why, at); bestAt = at
            default: continue
            }
        }
        return best
    }

    // MARK: Watching the network

    /// Starts the system's own path monitor. Idempotent — the screen calls it on appear.
    func watch() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.connectionKind = Self.kind(of: path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "us.parkhop.connections"))
    }

    private nonisolated static func kind(of path: NWPath) -> String? {
        guard path.status == .satisfied else { return nil }
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular) { return path.isExpensive ? "Cellular" : "Cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        return "Connected"
    }

    /// Asks the proxy whether it is up, rather than whether its URL parses. The one check
    /// on this screen that goes out and looks.
    func checkProxy(_ config: ProxyConfig) async {
        guard config.isConnected else {
            proxyHealthy = false
            proxyCheckedAt = Date()
            return
        }
        proxyHealthy = await config.health()
        proxyCheckedAt = Date()
    }
}

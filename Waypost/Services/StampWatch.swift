import CoreLocation
import Foundation

/// Where the phone is, and what that means for the passport.
///
/// Three things, and they are deliberately separate:
///
///  * **What is in reach** — everywhere whose own radius you are inside, offered for a tap.
///  * **What is nearby** — the next ones out, so the book is useful before you arrive.
///  * **The dwell** — how long you have been inside one, and whether that is long enough
///    for the phone to stamp it on your behalf.
///
/// The two thresholds are not the same number, and that is the point. A stamp cannot be
/// taken back, so **offering** is loose — if you might be there, the app says so and the
/// tap is yours — while **stamping for you** is tight: inside the reach, fifteen unbroken
/// minutes, and a fix good to a hundred metres. Anything less waits for a thumb.
///
/// ## What the system will and will not do
///
/// iOS does not run a fifteen-minute timer for an app nobody is looking at. What it does
/// do, given *Always*, is wake the app when the phone crosses a boundary we asked it to
/// watch — so the arrival notice is immediate, and the dwell is settled the next time the
/// app runs at all: leaving the boundary, opening the app, a significant-change wake. The
/// stamp is dated to the moment the dwell completed rather than to the moment it was
/// noticed, so it is right even when it is late.
///
/// With *When In Use* everything still works and nothing is silently broken — it simply
/// waits until the app is open.
@MainActor
@Observable
final class StampWatch: NSObject, CLLocationManagerDelegate {
    static let shared = StampWatch()

    /// One place, and when the phone arrived inside it.
    struct Dwell: Equatable {
        var place: Stampable
        var since: Date

        var elapsed: TimeInterval { Date().timeIntervalSince(since) }
        var remaining: TimeInterval { max(0, StampWatch.dwellSeconds - elapsed) }
        var isComplete: Bool { remaining == 0 }
    }

    // MARK: What the screens read

    /// Everywhere the phone is currently inside, nearest edge first. Usually one; two
    /// where a monument sits inside a park's reach.
    private(set) var inReach: [Stampable] = []
    /// The next ones out — near enough to be worth naming, not near enough to stamp.
    private(set) var nearby: [RankedStamp] = []
    /// The one being waited out, if any.
    private(set) var dwell: Dwell?
    /// The last fix, so a row can say how far away something is.
    private(set) var here: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    var isWatching: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// True once the system will wake the app for a boundary crossing. Everything works
    /// without it; only the arriving notice needs it.
    var wakesInBackground: Bool { authorization == .authorizedAlways }

    // MARK: What the app hands in

    /// Which codes are already collected, so nothing already in the book is offered again.
    /// Set by `AppState`, which owns that answer.
    var isCollected: (String) -> Bool = { _ in false }
    /// What a place is called in the book.
    ///
    /// Not the same string as `Stampable.key`, and the difference matters: the twelve
    /// stops shipped in `curated.json` carry their own short codes, and `AppState` maps a
    /// name onto one when it recognises it. Without this the watcher would offer
    /// Canyonlands to somebody who stamped it from a park screen last year, because it
    /// would be asking the book about "canyonlandsnationalpark" and the book would be
    /// holding "cany".
    var stampCode: (Stampable) -> String = { $0.key }
    /// How a stamp actually lands. `AppState` does the collecting; this only decides when.
    var collect: ((Stampable, Date, Bool) -> Void)?
    /// Whether the phone may stamp on its own. Off leaves every offer, notice and nearby
    /// row exactly as they are — it withdraws nothing but the automatic part.
    var stampsItself = true

    // MARK: The rules

    /// Fifteen minutes inside, unbroken.
    static let dwellSeconds: TimeInterval = 15 * 60
    /// A fix this good or better before the phone will stamp without being asked. A
    /// cell-tower fix can be a mile out, which is most of the reach of a small monument.
    static let confidentAccuracy: CLLocationDistance = 100
    /// How many boundaries the system will watch at once. Twenty is the platform's number,
    /// not ours; one is spent on the region we are inside.
    private static let watchedRegions = 20

    private let manager = CLLocationManager()
    private var deadline: Task<Void, Never>?
    /// The dwell survives the app being killed — the clock belongs to the visit, not to
    /// the process that happened to notice it starting.
    private static let dwellKey = "parkhop-stamp-dwell"

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // A hundred metres of movement is the resolution this needs: the tightest reach is
        // three miles, so anything finer is battery spent on a number nobody reads.
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }

    // MARK: Starting and stopping

    /// Begin watching, at whatever permission the app already holds. Never prompts: the
    /// first ask belongs to the moment somebody turns the feature on, not to launch.
    func begin() {
        guard isWatching else { return }
        restoreDwell()
        manager.startUpdatingLocation()
        if wakesInBackground {
            manager.startMonitoringSignificantLocationChanges()
        }
        Task { await StampCatalogue.adoptServiceUnits(); self.refresh() }
    }

    /// Ask for the permission the automatic stamp needs.
    ///
    /// iOS will only consider *Always* after *When In Use* has been granted, and it shows
    /// the second prompt once — so this asks for what it can, in order, and the caller
    /// reads `wakesInBackground` afterwards rather than assuming.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        deadline?.cancel()
        deadline = nil
    }

    /// Called when the app comes back to the front, and on every wake the system grants.
    /// The dwell may have completed while nothing was running.
    func settleUp() {
        guard isWatching else { return }
        restoreDwell()
        // `startUpdatingLocation` rather than `requestLocation`: the two do not mix — a
        // one-shot request issued while a stream is running is documented to interrupt it
        // — and this one is idempotent, so it is safe to say on every wake.
        manager.startUpdatingLocation()
        finishDwellIfDue()
    }

    // MARK: The answer

    private func refresh() {
        guard let here else { return }
        let ranked = StampCatalogue.near(lat: here.coordinate.latitude,
                                         lon: here.coordinate.longitude,
                                         limit: 30)
            .filter { !isCollected(stampCode($0.place)) }

        // Somewhere turned down stays turned down until it is left. Without this the clock
        // restarts on the next fix and the banner comes back, which is the app arguing.
        let within = Set(ranked.filter(\.isInReach).map(\.place.key))
        declined.formIntersection(within)

        inReach = ranked.filter(\.isInReach)
            .filter { !declined.contains($0.place.key) }
            .map(\.place)
        nearby = ranked.filter { !$0.isInReach }.prefix(6).map { $0 }

        watchBoundaries(around: ranked)
        trackDwell()
    }

    /// Hand the nearest boundaries to the system to watch.
    ///
    /// Twenty at a time, so the set has to follow the phone: a significant-change wake in
    /// another state re-registers around wherever it woke up. Regions already being
    /// watched are left alone — re-registering one resets it, and a reset region on the
    /// boundary you are standing on fires an entry you have already had.
    private func watchBoundaries(around ranked: [RankedStamp]) {
        guard wakesInBackground, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        else { return }

        let wanted = ranked.prefix(Self.watchedRegions)
        let wantedIDs = Set(wanted.map(\.place.id))
        for region in manager.monitoredRegions where !wantedIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        let watched = Set(manager.monitoredRegions.map(\.identifier))
        for entry in wanted where !watched.contains(entry.place.id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: entry.place.lat, longitude: entry.place.lon),
                // The system's own ceiling, whatever the park's size says. A reach larger
                // than this is a park you cannot leave by accident anyway.
                radius: min(entry.place.reachMetres, manager.maximumRegionMonitoringDistance),
                identifier: entry.place.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    // MARK: The dwell

    private func trackDwell() {
        // The one being waited out is the first in reach — the nearest edge, then the
        // smaller of two overlapping places. Somewhere you have left stops its own clock.
        guard let candidate = inReach.first else {
            if dwell != nil { clearDwell() }
            return
        }

        // Still inside the one being waited out — however the order came out this time.
        // Two overlapping places tie at zero and the tie-break moves with every fix, so
        // comparing against the *first* would restart the clock on alternate updates.
        if let running = dwell, inReach.contains(where: { $0.key == running.place.key }) {
            finishDwellIfDue()
            return
        }

        // A new place. Any clock running for somewhere else is abandoned rather than
        // carried over: fifteen minutes means fifteen minutes here.
        let started = Dwell(place: candidate, since: Date())
        dwell = started
        saveDwell(started)
        armDeadline()

        Task { await StampNotices.arrived(at: candidate, automatic: stampsItself) }
    }

    /// Stamp it if the fifteen minutes are up and the fix is good enough to be sure.
    private func finishDwellIfDue() {
        guard stampsItself, let dwell, dwell.isComplete else { return }
        guard let here, here.horizontalAccuracy > 0,
              here.horizontalAccuracy <= Self.confidentAccuracy else {
            // Inside, long enough, but the phone does not know where it is well enough to
            // put a thing in the book that cannot be taken out. It waits for a better fix.
            return
        }
        // Cleared before the stamp lands, not after.
        //
        // Collecting comes back round through `stampedByHand`, which clears this clock and
        // starts the next one on whatever else is in reach. Clearing again on the way out
        // would wipe that new clock the moment it started — the bug this ordering exists
        // to prevent.
        let place = dwell.place
        let landed = dwell.since.addingTimeInterval(Self.dwellSeconds)
        clearDwell()
        inReach.removeAll { $0.key == place.key }
        collect?(place, landed, true)
        trackDwell()
    }

    /// A task that wakes exactly when the clock runs out, for the case where the phone is
    /// sitting still in somebody's pocket and Core Location has nothing new to say.
    private func armDeadline() {
        deadline?.cancel()
        guard let dwell, stampsItself else { return }
        let wait = dwell.remaining
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, wait)))
            guard !Task.isCancelled else { return }
            self?.manager.startUpdatingLocation()
            self?.finishDwellIfDue()
        }
    }

    private func clearDwell() {
        dwell = nil
        deadline?.cancel()
        deadline = nil
        UserDefaults.standard.removeObject(forKey: Self.dwellKey)
    }

    private func saveDwell(_ dwell: Dwell) {
        UserDefaults.standard.set([
            "key": dwell.place.key,
            "name": dwell.place.name,
            "designation": dwell.place.designation,
            "place": dwell.place.place,
            "lat": dwell.place.lat,
            "lon": dwell.place.lon,
            "kind": dwell.place.kind.rawValue,
            "since": dwell.since.timeIntervalSince1970,
        ] as [String: Any], forKey: Self.dwellKey)
    }

    private func restoreDwell() {
        guard dwell == nil,
              let stored = UserDefaults.standard.dictionary(forKey: Self.dwellKey),
              let name = stored["name"] as? String,
              let lat = stored["lat"] as? Double,
              let lon = stored["lon"] as? Double,
              let since = stored["since"] as? TimeInterval
        else { return }

        // A clock older than a day is not a visit any more; somebody parked in a valley
        // and came back a week later, and stamping that would be a lie about a Tuesday.
        let started = Date(timeIntervalSince1970: since)
        guard Date().timeIntervalSince(started) < 24 * 60 * 60 else {
            UserDefaults.standard.removeObject(forKey: Self.dwellKey)
            return
        }

        let place = Stampable(name: name,
                              designation: stored["designation"] as? String ?? "",
                              place: stored["place"] as? String ?? "",
                              lat: lat, lon: lon,
                              kind: Stampable.Kind(rawValue: stored["kind"] as? String ?? "") ?? .unit,
                              acres: nil)
        guard !isCollected(stampCode(place)) else {
            UserDefaults.standard.removeObject(forKey: Self.dwellKey)
            return
        }
        dwell = Dwell(place: place, since: started)
        armDeadline()
    }

    /// Whether a place named like this is somewhere the phone can see it standing.
    ///
    /// True when it is in reach — and also true when the app holds no location permission
    /// at all, because a screen cannot honestly refuse on evidence it does not have. That
    /// is the difference between a rule and an obstacle: somebody who declined location
    /// keeps the app they had, and the offer says what it would need to do better.
    func canStamp(_ name: String) -> Bool {
        guard isWatching else { return true }
        let asked = Stampable.key(name)
        // Either way round. A park screen's stamp is often the long form of what the
        // register calls the place — "Canyonlands NP — Island in the Sky" against
        // "Canyonlands" — and refusing on a name that is plainly the same park is the
        // frustration this whole rule exists to avoid.
        return inReach.contains { asked.hasPrefix($0.key) || $0.key.hasPrefix(asked) }
    }

    /// Somebody tapped the stamp themselves, so the clock has nothing left to do.
    ///
    /// Asked in the book's terms, because that is what the caller has: a stamp lands under
    /// a code, and only this knows which place that code came from.
    func stampedByHand(_ code: String) {
        guard let dwell, stampCode(dwell.place) == code else { return }
        StampNotices.withdrawArrival(for: dwell.place.key)
        // Off the plate now, rather than at the next fix. A card still offering a stamp
        // that is already in the book is the app forgetting what it just did.
        inReach.removeAll { $0.key == dwell.place.key }
        clearDwell()
        trackDwell()
    }

    /// Somebody said no to this one. It leaves the offer and the clock alone for the rest
    /// of the visit rather than for ever — a stamp declined at the gate is often collected
    /// at the visitor centre an hour later.
    func decline(_ key: String) {
        guard dwell?.place.key == key else { return }
        deadline?.cancel()
        deadline = nil
        dwell = nil
        UserDefaults.standard.removeObject(forKey: Self.dwellKey)
        declined.insert(key)
        // Now, rather than at the next fix a hundred metres from here — a card that stays
        // on screen after being dismissed is a card that did not hear.
        inReach.removeAll { $0.key == key }
        StampNotices.withdrawArrival(for: key)
        trackDwell()
    }

    /// Places turned down for this visit. Emptied of anything no longer in reach on every
    /// refresh, so declining at the gate and collecting at the visitor centre an hour later
    /// still works — it is a "not now", not a "never".
    private var declined: Set<String> = []

    // MARK: Core Location

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.here = last
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Nothing to do. The last fix stands, the screens keep showing what they showed,
        // and the next update replaces it.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in self.settleUp() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            // Leaving is the commonest moment the app is woken, and the last chance to
            // settle a dwell that completed while nothing was running.
            self.finishDwellIfDue()
            self.manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if self.isWatching {
                self.begin()
            } else {
                self.stop()
            }
        }
    }
}

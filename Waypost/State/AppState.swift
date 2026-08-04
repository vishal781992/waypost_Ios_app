import Foundation
import SwiftUI

// MARK: - Navigation

enum AppTab: String, CaseIterable, Identifiable {
    case today, trips, discover, saved, me
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .trips: return "Trips"
        case .discover: return "Discover"
        case .saved: return "Saved"
        case .me: return "Profile"
        }
    }
}

/// What the Today screen makes of the day. The design ships three takes and lets you
/// switch between them; the switch lives in Profile on device.
enum TodayTake: String, CaseIterable {
    case field, timeline, dash

    var label: String {
        switch self {
        case .field: return "Field card"
        case .timeline: return "Timeline"
        case .dash: return "Dashboard"
        }
    }
}

/// A pushed screen. The design keeps its own stack rather than a NavigationStack so the
/// tab bar stays put and the push animation is its own.
enum PushedScreen: Hashable, Identifiable {
    case park(code: String, segment: ParkSegment = .overview)
    case trip(id: String)

    var id: String {
        switch self {
        case .park(let code, _): return "park:" + code
        case .trip(let id): return "trip:" + id
        }
    }
}

enum ParkSegment: String, CaseIterable, Hashable {
    case overview, weather, stay, plan, near

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .weather: return "Weather"
        case .stay: return "Stay"
        case .plan: return "Plans"
        case .near: return "Nearby"
        }
    }
}

enum TripSegment: String, CaseIterable, Hashable {
    case route, days, stays

    var label: String { rawValue.capitalized }
}

/// The bottom sheets: a park alert, a permit window, a leg, a passport stamp.
enum ActiveSheet: Identifiable {
    case alert(park: String, alert: CuratedAlert)
    case permit(drop: PermitDrop)
    case leg(index: Int, date: String)
    /// A leg the app routed rather than one the seed trip carries — the drive from
    /// where you are, and the drives between the parks of a composed trip.
    case routedLeg(TripRouting.Leg, label: String)
    case stamp(name: String, city: String, dist: String)

    var id: String {
        switch self {
        case .alert(let park, let alert): return "alert:\(park):\(alert.title)"
        case .permit(let drop): return "permit:\(drop.what)"
        case .leg(let index, _): return "leg:\(index)"
        case .routedLeg(let leg, _): return "routed:" + leg.id
        case .stamp(let name, _, _): return "stamp:\(name)"
        }
    }
}

enum PackState: String {
    case none, busy, ready
}

// MARK: - The app model

/// Every piece of state the design's prototype holds, plus persistence so the phone
/// remembers what you ticked, saved, stamped and downloaded.
@MainActor
@Observable
final class AppState {

    // Navigation
    var tab: AppTab = .today
    var stack: [PushedScreen] = []
    var sheet: ActiveSheet?
    var take: TodayTake = .field

    // Which day of the open trip is being read. One, until a trip says otherwise.
    var day: Int = 1

    // Today
    var doneItems: Set<String> = []
    var liveActivityOn = false
    var journalCount = 0

    // Notifications. Off until the system says otherwise — these are a record of what the
    // user asked for, and a fresh install has been asked nothing.
    var notifyPermits = false
    var notifyAlerts = false
    var notifyLive = false

    // Offline packs
    var packs: [String: PackState] = [:]
    var packProgress: [String: Double] = [:]

    // Library. Empty on a clean install: a saved park, a stamp and a downloaded pack are
    // claims about what somebody did, and nobody has done anything yet.
    var saved: [String] = []
    var stamps: Set<String> = []
    var savedShowsPassport = false

    // Discover
    /// Typing here searches the live directory. The trigger lives on the property rather
    /// than in an `onChange` on one screen, so it cannot be missed by whichever view
    /// happens to be on screen — including the state-park side of the toggle.
    var discoverQuery = "" {
        didSet {
            guard discoverQuery != oldValue else { return }
            suggestions.knownParks = directory.hits.map { ($0.park.name, $0.park.state) }
            suggestions.update(discoverQuery)
            directory.search(discoverQuery)
        }
    }

    /// What you might mean, offered while you are still typing it.
    let suggestions = SearchSuggestions()

    /// Set when the app is opened straight into a search, so the field takes the caret
    /// and the suggestions are visible without a tap.
    var focusSearchOnAppear = false

    /// Opens the search behind the home screen's `+`, for capture.
    var showsQuickSearch = false

    /// Picking one searches for the term the sources will recognise, not the two letters
    /// that were typed.
    func takeSuggestion(_ suggestion: SearchSuggestions.Suggestion) {
        discoverQuery = suggestion.query
        suggestions.clear()
        Haptics.tap()
    }
    var discoverChip = "all"
    /// Which catalogue Discover is showing: the NPS registry, or the state-park table
    /// that ships on the phone.
    var discoverShowsState = false

    // Preferences
    var vehicleIsElectric = true
    var unitsMetric = false

    // Per-screen segment memory
    var parkSegment: [String: ParkSegment] = [:]
    var tripSegment: [String: TripSegment] = [:]

    // Trip building
    var builder: TripBuilder?
    var myTrips: [SavedTrip] = []
    /// The seed trip ships with the app rather than living in `myTrips`, so removing it
    /// is remembered as a flag.
    var seedTripHidden = false

    // Transient
    var toast: String?
    private var toastTask: Task<Void, Never>?
    private var packTasks: [String: Task<Void, Never>] = [:]

    let library = CuratedLibrary.shared

    init() {
        restore()
        applyLaunchArguments()
    }

    // MARK: Derived

    var today: CuratedDay {
        let clamped = min(max(day, 1), library.days.count)
        return library.days[clamped - 1]
    }

    var todayPark: CuratedPark? {
        today.code.flatMap { library.park($0) }
    }

    var todayLeg: CuratedLeg? {
        today.leg.flatMap { library.legs.indices.contains($0) ? library.legs[$0] : nil }
    }

    /// The next driving day after today, and its leg — what the Today screen previews.
    var nextLegDay: (day: CuratedDay, leg: CuratedLeg)? {
        guard let next = library.days.first(where: { $0.d > today.d && $0.isLeg }),
              let index = next.leg, library.legs.indices.contains(index) else { return nil }
        return (next, library.legs[index])
    }

    /// The park you arrive at after the next leg — the one worth downloading a pack for.
    var packSuggestion: CuratedPark? {
        guard let next = nextLegDay?.day else { return nil }
        guard let arrival = library.days.first(where: { $0.d > next.d && $0.isPark }),
              let code = arrival.code else { return nil }
        return library.park(code)
    }

    var permitDrop: PermitDrop? {
        todayPark.flatMap { PermitDrop.byPark[$0.code] }
    }

    func packState(_ code: String) -> PackState { packs[code] ?? .none }

    func isStamped(_ unitCode: String) -> Bool { stamps.contains(unitCode) }

    /// The design keys stamps off the unit's name when it meets one on a park screen.
    func stampKey(forName name: String) -> String {
        if let unit = library.passport.first(where: { name.hasPrefix($0.name) }) { return unit.code }
        return name.lowercased().replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
    }

    // MARK: Actions

    func go(_ tab: AppTab) {
        withAnimation(.snappy(duration: 0.22)) {
            self.tab = tab
            stack = []
        }
        persist()
    }

    func push(_ screen: PushedScreen) {
        stack.append(screen)
    }

    func pop() {
        _ = stack.popLast()
    }

    /// A door for screenshots: `-tab discover`, `-open-park arch`.
    ///
    /// Synthetic taps are not available on this simulator, so a pushed screen cannot be
    /// reached any other way when capturing one.
    func applyLaunchArguments() {
        // Debug only. Every one of these hooks writes user state — a tab, an emptied
        // screen, an open sheet, the page colour — so in a release build this function
        // does nothing and the arguments cannot reach anything.
        #if DEBUG
        // Both spellings: the argument list, and the argument domain iOS builds from
        // `-key value` pairs — which is the one that survives however the app was started.
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            if let i = args.firstIndex(of: "-" + flag), i + 1 < args.count { return args[i + 1] }
            return UserDefaults.standard.string(forKey: flag)
        }
        let wantedTab = value("wpTab").flatMap(AppTab.init(rawValue:))
        let wantedPark = value("wpPark")
        guard wantedTab != nil || wantedPark != nil
                || value("wpSearch") != nil || value("wpTrip") != nil
                || value("wpBuilder") != nil || value("wpStateParks") != nil
                || value("wpEmpty") != nil || value("wpSheet") != nil
                || value("wpFind") != nil || value("wpTint") != nil
                || value("wpDemoTrip") != nil || value("wpPlanAround") != nil else { return }

        // Applied after the scene has settled. SwiftUI restores the tab view's own
        // selection on launch and writes it back through the binding, and `go` clears
        // the stack — so anything set here during init is overwritten a moment later.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if let wantedTab { self.tab = wantedTab }
            if let wantedPark {
                let segment = value("wpSeg").flatMap(ParkSegment.init(rawValue:)) ?? .overview
                // The tab view writes its restored selection back through the binding at
                // an unpredictable moment after launch, and `go` clears the stack — so
                // the push is repeated until it sticks.
                // A code the app already knows, or — for a park that only exists once a
                // search has found it, like any state park — the name of one.
                if self.park(wantedPark) == nil {
                    self.directory.search(wantedPark)
                    for _ in 0..<20 where self.directory.hits.isEmpty {
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                }
                let code = self.park(wantedPark) != nil
                    ? wantedPark
                    : self.directory.hits.first(where: {
                        $0.park.name.localizedCaseInsensitiveContains(wantedPark)
                      })?.park.code ?? self.directory.hits.first?.park.code

                if let code {
                    for _ in 0..<5 where self.stack.isEmpty {
                        self.openPark(code, segment: segment)
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            // A trip to look at. Debug only, like everything in this function — the
            // sample itinerary stopped being production state in v2.15.0.
            if value("wpDemoTrip") != nil, !self.myTrips.contains(where: { $0.id == "seed" }) {
                self.myTrips.append(SavedTrip.seed(dayNumber: self.day))
            }
            if let id = value("wpTrip") {
                self.tab = .trips
                if let segment = value("wpTripSeg").flatMap(TripSegment.init(rawValue:)) {
                    self.tripSegment[id] = segment
                }
                self.push(.trip(id: id))
            }
            if let step = value("wpBuilder") {
                self.startBuilder()
                // Steps two and three need parks picked before they will show anything.
                if let typed = value("wpBuilderQuery") { self.builder?.query = typed }
            if let around = value("wpPlanAround") {
                if self.park(around) == nil, self.directory.hits.isEmpty {
                    self.directory.search(around)
                }
                for _ in 0..<20 where self.directory.hits.isEmpty {
                    try? await Task.sleep(for: .milliseconds(400))
                }
                if let park = self.directory.hits.first(where: {
                    $0.park.name.localizedCaseInsensitiveContains(around)
                })?.park ?? self.park(around) {
                    self.startBuilder(around: park)
                }
            }
                if let wanted = Int(step), wanted > 1 {
                    self.builder?.picks = ["romo", "arch", "zion"]
                    self.builder?.step = wanted
                }
            }
            if value("wpStateParks") != nil { self.tab = .discover; self.discoverShowsState = true }
            if let hex = value("wpTint"), PageTint.colour(from: hex) != nil {
                PageTint.shared.hex = hex
            }
            if let term = value("wpFind") {
                self.tab = .today
                self.showsQuickSearch = true
                if term != "1" { self.suggestions.update(term); self.directory.search(term) }
            }

            // The empty states, which are otherwise only reachable by deleting things.
            if let empty = value("wpEmpty") {
                let wanted = Set(empty.split(separator: ",").map(String.init))
                if wanted.contains("trips") { self.seedTripHidden = true; self.myTrips = [] }
                if wanted.contains("saved") { self.saved = [] }
                if wanted.contains("stamps") || wanted.contains("saved") { self.stamps = [] }
            }

            // The four sheets, each of which needs a row tapped to reach.
            if let sheet = value("wpSheet") {
                switch sheet {
                case "alert":
                    if let park = self.library.park("zion"), let alert = park.alerts.first {
                        self.sheet = .alert(park: park.name, alert: alert)
                    }
                case "permit":
                    if let drop = PermitDrop.byPark["arch"] { self.sheet = .permit(drop: drop) }
                case "leg":
                    self.sheet = .leg(index: 0, date: "6 August")
                case "stamp":
                    if let stamp = self.library.park("arch")?.stamps.first {
                        self.sheet = .stamp(name: stamp.name, city: stamp.city, dist: stamp.dist)
                    }
                default: break
                }
            }
            if let term = value("wpSearch") {
                self.tab = .discover
                self.focusSearchOnAppear = true
                // Nothing else: setting the query is what starts a search, exactly as
                // typing into the field does.
                self.discoverQuery = term
            }
        }
        #endif
    }

    /// The live catalogue. The eight curated parks are still the ones with day plans and
    /// campgrounds; everything else in the country comes through here.
    let directory = ParkDirectory()

    /// Real distances and wheel times for the trips the app composed.
    let routing = TripRouting()

    /// Which park leads the home screen today.
    let recommender = Recommender()

    /// Parks with a cancellation stamp against them — the ones you have actually stood
    /// in. Empty until the first is collected, and the screens that show it show nothing
    /// rather than a placeholder.
    var visitedParks: [CuratedPark] {
        let all = library.orderedParks + NationalParks.all.map(CuratedPark.init(bundled:))
        var seen = Set<String>()
        return all
            .filter { stamps.contains(stampKey(forName: $0.name)) && seen.insert($0.name).inserted }
            .sorted { $0.name < $1.name }
    }

    /// Parks you have already been to, one way or another: stamped, saved for later, or
    /// already written into a trip.
    var visitedCodes: Set<String> {
        var codes = Set(saved)
        codes.formUnion(myTrips.flatMap(\.codes))
        codes.formUnion(library.orderedParks.filter { stamps.contains(stampKey(forName: $0.name)) }.map(\.code))
        return codes
    }

    /// The park the home screen leads with. Nil until the recommendation has been worked
    /// out — the screen used to open on whichever park the seed trip happened to be in
    /// and then swap, which read as the app changing its mind in front of you.
    var featuredPark: CuratedPark? { recommender.pick?.park }

    /// True while it is still being worked out, so the screen can say so rather than
    /// showing a park it is about to replace.
    var isChoosingFeature: Bool { recommender.pick == nil }

    /// The line under its name: why this park, or where you are in the trip.
    var featuredReason: String { recommender.pick?.reason ?? "" }

    /// Asks for a fresh recommendation. Called every time the home screen appears, and
    /// the recommender itself holds back the last two so it lands somewhere new.
    func refreshRecommendation() {
        var candidates = library.orderedParks
        // Anything the directory has found is a candidate too, so the screen widens as
        // the app is used rather than circling the same eight.
        candidates += directory.hits.map(\.park).filter { park in
            !candidates.contains { $0.code == park.code }
        }
        recommender.choose(from: candidates, visited: visitedCodes)
    }

    /// A park by code, wherever it came from. The curated library first, because those
    /// records carry more; then whatever the last search found.
    func park(_ code: String) -> CuratedPark? {
        if let curated = library.park(code) { return curated }
        if let found = directory.hits.first(where: { $0.park.code == code })?.park { return found }
        // A park saved from the on-device list still opens after a relaunch, when the
        // search that found it is long gone.
        if let national = NationalParks.park(code: code) { return CuratedPark(bundled: national) }
        return Datasets.shared.statePark(code: code)
    }

    func openPark(_ code: String, segment: ParkSegment = .overview) {
        parkSegment[code] = segment
        push(.park(code: code, segment: segment))
    }

    func show(_ text: String) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.24)) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2100))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.toast = nil }
        }
    }

    func toggleDone(_ key: String) {
        if doneItems.contains(key) {
            doneItems.remove(key)
        } else {
            doneItems.insert(key)
            Haptics.tap()
            show("Ticked · haptic tap")
        }
        persist()
    }

    func toggleSaved(_ code: String) {
        if let index = saved.firstIndex(of: code) {
            saved.remove(at: index)
            show("Removed from saved")
        } else {
            saved.append(code)
            Haptics.tap()
            show((library.park(code)?.name ?? "Park") + " saved")
        }
        persist()
    }

    func collectStamp(_ unitCode: String, name: String) {
        guard !stamps.contains(unitCode) else {
            show("\(name) — collected")
            return
        }
        stamps.insert(unitCode)
        Haptics.success()
        show("Stamp collected · haptic tap")
        persist()
    }

    func toggleLiveActivity() {
        liveActivityOn.toggle()
        show(liveActivityOn ? "Live Activity on the lock screen" : "Live Activity ended")
    }

    func addJournalPhoto() {
        journalCount = min(6, journalCount + 1)
        show("Photo pinned to Day \(today.d)")
        persist()
    }

    func stepDay(_ delta: Int) {
        day = min(max(1, day + delta), library.days.count)
        persist()
    }

    /// Downloads a park pack. The progress is simulated on this pass — the pack format
    /// itself is not built yet, and the Profile screen says so rather than implying the
    /// bytes are on the device.
    func startPack(_ code: String) {
        guard packState(code) != .ready, packTasks[code] == nil else { return }
        packs[code] = .busy
        packProgress[code] = 0.04
        packTasks[code] = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(260))
                guard let self, !Task.isCancelled else { return }
                let next = (packProgress[code] ?? 0) + 0.11
                if next >= 1 {
                    packProgress[code] = 1
                    packs[code] = .ready
                    packTasks[code] = nil
                    persist()
                    show((library.park(code)?.name ?? "Park") + " pack ready — works with no signal")
                    return
                }
                packProgress[code] = next
            }
        }
    }

    var packStorageMB: Int {
        library.orderedParks.filter { packState($0.code) == .ready }.reduce(0) { $0 + $1.packMB }
    }

    // MARK: Trips

    var trips: [SavedTrip] {
        // Only trips the user made. The sample itinerary is a fixture now, reachable in
        // debug builds through the capture hooks and never on a clean install.
        myTrips
    }

    /// Removing a trip is not undoable, so the card asks first.
    func deleteTrip(_ id: String) {
        if id == "seed" {
            seedTripHidden = true
        } else {
            myTrips.removeAll { $0.id == id }
        }
        stack.removeAll { $0.id == "trip:" + id }
        tripSegment[id] = nil
        Haptics.tap()
        show("Trip removed")
        persist()
    }

    func trip(_ id: String) -> SavedTrip? { trips.first { $0.id == id } }

    /// A trip built around one park, from that park's own screen.
    ///
    /// The park is the answer to step one, so the builder opens on step two — when, and
    /// from where. More parks can still be added by stepping back.
    func startBuilder(around park: CuratedPark) {
        startBuilder()
        builder?.liveResults = [park]
        builder?.picks = [park.code]
        builder?.step = 2
        Haptics.tap()
    }

    func startBuilder() {
        let builder = TripBuilder(vehicleIsElectric: vehicleIsElectric)
        // The builder's field drives the same live search Discover uses, and takes the
        // results back as they land.
        builder.onQueryChanged = { [weak self] query in
            guard let self else { return }
            self.directory.search(query)
        }
        self.builder = builder
    }

    /// Hands the directory's findings to the open builder, if there is one.
    func refreshBuilderResults() {
        builder?.liveResults = directory.hits.map(\.park)
    }

    func finishBuilder() {
        guard let builder else { return }
        let trip = builder.compose()
        myTrips.insert(trip, at: 0)
        self.builder = nil
        show("\(trip.title) composed")
        tab = .trips
        persist()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var day: Int
        var done: [String]
        var saved: [String]
        var stamps: [String]
        var packs: [String: String]
        var journal: Int
        var ev: Bool
        var metric: Bool
        var permits: Bool
        var alerts: Bool
        var live: Bool
        var take: String
        var trips: [SavedTrip]
        /// Reopening on the destination you left is what every other app does.
        var tab: String?
        var passport: Bool?
        var seedHidden: Bool?
    }

    private static let key = "waypost-app"

    func persist() {
        let snapshot = Snapshot(
            day: day,
            done: Array(doneItems),
            saved: saved,
            stamps: Array(stamps),
            packs: packs.mapValues(\.rawValue),
            journal: journalCount,
            ev: vehicleIsElectric,
            metric: unitsMetric,
            permits: notifyPermits,
            alerts: notifyAlerts,
            live: notifyLive,
            take: take.rawValue,
            trips: myTrips,
            tab: tab.rawValue,
            passport: savedShowsPassport,
            seedHidden: seedTripHidden
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        day = snapshot.day
        doneItems = Set(snapshot.done)
        saved = snapshot.saved
        stamps = Set(snapshot.stamps)
        packs = snapshot.packs.compactMapValues { PackState(rawValue: $0) }
        journalCount = snapshot.journal
        vehicleIsElectric = snapshot.ev
        unitsMetric = snapshot.metric
        notifyPermits = snapshot.permits
        notifyAlerts = snapshot.alerts
        notifyLive = snapshot.live
        take = TodayTake(rawValue: snapshot.take) ?? .field
        myTrips = snapshot.trips
        tab = snapshot.tab.flatMap(AppTab.init(rawValue:)) ?? .today
        savedShowsPassport = snapshot.passport ?? false
        seedTripHidden = snapshot.seedHidden ?? false
    }
}

// MARK: - Trips

struct SavedTrip: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var dates: String
    var route: String
    var codes: [String]
    var origin: String
    var tag: String
    var live: Bool

    /// The trip that is already under way when the app opens — the design's seed.
    static func seed(dayNumber: Int) -> SavedTrip {
        SavedTrip(
            id: "seed",
            title: "The Colorado Plateau loop",
            dates: "5 – 14 August 2026",
            route: "Denver · Rocky Mountain · Arches · Zion",
            codes: ["romo", "arch", "zion"],
            origin: "den",
            tag: "Day \(dayNumber) · under way",
            live: true
        )
    }

}

/// The three-step new-trip flow: pick parks, set the dates and origin, review.
@Observable
final class TripBuilder {
    var step = 1
    var picks: [String] = []
    var days: [String: Int] = [:]
    var startLabel = "12 September 2026"
    var origin = "den"
    var flyWhenFaster = false
    var vehicleIsElectric: Bool
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            onQueryChanged?(query)
        }
    }
    /// Set by `AppState` so the builder can reach the shared directory without owning it.
    var onQueryChanged: ((String) -> Void)?
    var composeProgress: Double = 0
    var composing = false

    private let candidateStarts = ["12 September 2026", "19 September 2026", "3 October 2026", "17 April 2027"]
    private var startIndex = 0

    init(vehicleIsElectric: Bool) {
        self.vehicleIsElectric = vehicleIsElectric
    }

    var library: CuratedLibrary { .shared }

    func cycleStart() {
        startIndex = (startIndex + 1) % candidateStarts.count
        startLabel = candidateStarts[startIndex]
    }

    func days(for code: String) -> Int { days[code] ?? 2 }

    func toggle(_ code: String) {
        if let index = picks.firstIndex(of: code) {
            picks.remove(at: index)
            days[code] = nil
        } else {
            picks.append(code)
            days[code] = 2
        }
    }

    func adjustDays(_ code: String, by delta: Int) {
        days[code] = min(9, max(1, days(for: code) + delta))
    }

    /// Every park the app can find, not the eight it ships with.
    ///
    /// This read `library.orderedParks` alone, so a trip could only ever be built out of
    /// the curated eight — a park found on Discover could be opened and saved but not
    /// planned around, which is the one place it mattered.
    ///
    /// Three sources, in the order they can answer: the sixty-two on the phone, instantly
    /// and offline; the curated eight, which carry day plans the others do not; and
    /// whatever the live directory has found for the same words.
    var results: [CuratedPark] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        var out = library.orderedParks
        var seen = Set(out.map { $0.name.lowercased() })

        func add(_ parks: [CuratedPark]) {
            for park in parks where seen.insert(park.name.lowercased()).inserted {
                out.append(park)
            }
        }

        if q.isEmpty {
            // Nothing typed: the eight with plans first, then the rest of the country.
            add(NationalParks.all.map(CuratedPark.init(bundled:)))
            return out
        }

        out = out.filter { ($0.name + " " + $0.state + " " + $0.full).lowercased().contains(q) }
        seen = Set(out.map { $0.name.lowercased() })
        add(NationalParks.search(q).map(CuratedPark.init(bundled:)))
        add(liveResults)
        return out
    }

    /// Filled by the directory as it answers. Held rather than read through `AppState` so
    /// the builder keeps working if it is ever presented on its own.
    var liveResults: [CuratedPark] = []

    var totalDays: Int { picks.reduce(0) { $0 + days(for: $1) } }

    var heading: String {
        switch step {
        case 1: return "Which parks?"
        case 2: return "When, and from where?"
        default: return "Does this look right?"
        }
    }

    var subtitle: String {
        switch step {
        case 1: return "Pick them in the order you want to visit. Days in each park are set with the steppers."
        case 2: return "Waypost sizes the legs and the offline packs from these."
        default: return "Composing takes a moment — the order of the legs is worked out from the coordinates."
        }
    }

    var stepLabel: String { "Step \(min(step, 3)) of 3" }

    var nextLabel: String {
        switch step {
        case 1: return picks.isEmpty ? "Pick a park to continue" : "Dates and origin"
        case 2: return "Review"
        default: return "Compose the itinerary"
        }
    }

    var pickNote: String {
        picks.isEmpty
            ? "Nothing picked yet"
            : "\(picks.count) park\(picks.count == 1 ? "" : "s") · \(totalDays) days in the parks"
    }

    var isNextDisabled: Bool { step == 1 && picks.isEmpty }

    var reviewRows: [(label: String, value: String)] {
        let originName = library.city(origin)?.name ?? origin
        return [
            ("Parks", picks.compactMap { library.park($0)?.name }.joined(separator: " → ")),
            ("Days afield", "\(totalDays) in the parks, plus travel"),
            ("First day", startLabel),
            ("Setting out from", originName),
            ("Between stops", flyWhenFaster ? "Fly when it is faster" : "Drive"),
            ("Vehicle", vehicleIsElectric ? "Electric — charge stops added to every leg" : "Gasoline"),
        ]
    }

    static let composeSteps = [
        "Ordering the parks by road distance",
        "Routing the legs",
        "Reading August normals for your dates",
        "Checking campsite availability",
        "Sizing the offline packs",
    ]

    func compose() -> SavedTrip {
        let parks = picks.compactMap { library.park($0) }
        let originName = library.city(origin)?.shortName ?? "Home"
        return SavedTrip(
            id: "trip-\(picks.joined(separator: "-"))-\(startLabel.hashValue)",
            title: parks.count == 1
                ? "\(parks[0].name) in \(startLabel.split(separator: " ").dropFirst().first.map(String.init) ?? "")"
                : "\(parks.first?.name ?? "") to \(parks.last?.name ?? "")",
            dates: startLabel,
            route: ([originName] + parks.map(\.name)).joined(separator: " · "),
            codes: picks,
            origin: origin,
            tag: "Planned",
            live: false
        )
    }
}

// MARK: - Haptics

/// The design leans on haptics — "the phone taps back" when a stamp lands or an item is
/// ticked. This is the one place that fires them.
enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

import Foundation
import SwiftUI

// MARK: - Navigation

enum AppTab: String, CaseIterable, Identifiable {
    /// Discover was a fifth tab. It is reached from the Today header now — the same
    /// catalogue, one tab lighter, and no longer duplicated by a quick-search sheet that
    /// asked the same question in a smaller box.
    case today, trips, saved, me
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .trips: return "Trips"
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
    /// `date` is the day the park is being opened *for* — a trip's arrival date, say. Nil
    /// means today. Without it the weather panel had no way to know it was being read for
    /// a trip next month, so it always asked for today's forecast.
    case park(code: String, segment: ParkSegment = .brief, date: Date? = nil)
    case trip(id: String)
    /// The catalogue, which used to be a tab of its own.
    ///
    /// Pushed rather than presented: it is a place to browse — sixty-two national parks,
    /// three thousand state ones, filters and photographs — and a sheet is a poor room to
    /// wander in. Pushing keeps the back-swipe and lets a park open on top of it, exactly
    /// as it did when Discover was a tab.
    case explore

    var id: String {
        switch self {
        case .park(let code, _, _): return "park:" + code
        case .trip(let id): return "trip:" + id
        case .explore: return "explore"
        }
    }
}

enum ParkSegment: String, CaseIterable, Hashable {
    case brief, overview, weather, stay, plan, near

    var label: String {
        switch self {
        case .brief: return "AI Overview"
        case .overview: return "Overview"
        case .weather: return "Weather"
        case .stay: return "Stay"
        case .plan: return "Plans"
        case .near: return "Nearby"
        }
    }

    /// What the rail's pill calls it. "AI Overview" beside five 44pt discs does not fit
    /// across a phone, and the word that distinguishes it is not "overview".
    var shortLabel: String {
        switch self {
        case .brief: return "Brief"
        case .overview: return "Park"
        case .weather: return "Weather"
        case .stay: return "Stay"
        case .plan: return "Plans"
        case .near: return "Near"
        }
    }

    /// The glyph the rail wears when there is no room for the word — which is every
    /// section but the one being read.
    var icon: String {
        switch self {
        case .brief: return "sparkles"
        case .overview: return "map"
        case .weather: return "cloud.sun"
        case .stay: return "bed.double"
        case .plan: return "calendar"
        case .near: return "location.circle"
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
    /// How the park service says to drive in — its own `directionsInfo`, which the app
    /// has always fetched and never had anywhere to put.
    case directions(park: String, text: String)

    var id: String {
        switch self {
        case .alert(let park, let alert): return "alert:\(park):\(alert.title)"
        case .directions(let park, _): return "directions:\(park)"
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
    /// One navigation path per tab.
    ///
    /// All five `NavigationStack`s were bound to a single array, so five stacks were
    /// driven by one path: a screen pushed on Discover appeared in the history of every
    /// other tab, and popping one of them popped all of them — which is why Back stopped
    /// behaving. Each tab keeps its own history now, and keeps it across tab switches.
    var paths: [AppTab: [PushedScreen]] = [:]

    /// The current tab's path, for the call sites that only ever mean this one.
    var stack: [PushedScreen] {
        get { paths[tab] ?? [] }
        set { paths[tab] = newValue }
    }

    func path(for tab: AppTab) -> [PushedScreen] { paths[tab] ?? [] }

    func setPath(_ screens: [PushedScreen], for tab: AppTab) { paths[tab] = screens }
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
            placeAnchor.locate(discoverQuery)
        }
    }

    /// What you might mean, offered while you are still typing it.
    let suggestions = SearchSuggestions()

    /// Where the typed words are, so the state-park table can be ranked around a city it
    /// has never heard of.
    let placeAnchor = PlaceAnchor()

    /// Set when the app is opened straight into a search, so the field takes the caret
    /// and the suggestions are visible without a tap.
    var focusSearchOnAppear = false

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
    /// Parks the traveller added to the visited rail by hand. Codes only: a park added
    /// this way carries no date, because stamping it with today would be inventing when
    /// they went.
    var manualVisits: [String] = []
    /// Parks taken back off the visited rail by hand.
    ///
    /// A suppression list rather than a deletion, because the rail has three sources and
    /// only one of them can be deleted from: a passport stamp is a fact about where the
    /// phone stood, and a past trip is a whole itinerary. Taking a park off the rail must
    /// not quietly destroy either, and must work the same whichever source put it there.
    var hiddenVisits: Set<String> = []
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

        // `state-parks.json` is 426 KB, decoded lazily behind a lock the first time
        // anything asks for it — and the things that ask are `AppState.park(_:)`, which
        // the shell calls while rendering a pushed screen, and the Discover state list,
        // which reads it from `body`. Either way the decode landed on the main thread
        // between a finger going down and coming up, which cancels the gesture: the tap
        // is eaten and the one after it works because the cache is warm. Warm it off the
        // main thread instead, so the first tap is the one that counts.
        Task.detached(priority: .utility) { _ = Datasets.shared.stateParks }
    }

    // MARK: Derived

    var today: CuratedDay {
        let clamped = min(max(day, 1), library.days.count)
        return library.days[clamped - 1]
    }

    var todayPark: CuratedPark? {
        today.code.flatMap { library.park($0) }
    }

    /// A trip the user is genuinely on right now, by the real calendar — not a fixture.
    ///
    /// The driving-day card used to read its leg from `today`, a curated fixture pinned to
    /// day one (`day` defaults to 1 and nothing moves it), so it showed the seed's Denver
    /// leg on every launch — on a fresh install where no trip had been started, and it would
    /// have kept showing it long after any dates had passed. A driving day is a day somebody
    /// is actually driving, so this is a real trip in `myTrips` whose window contains today.
    /// The pre-seeded demo does not count: nobody planned it, and the dashboard is the
    /// user's day, not the app's showcase.
    var activeTripToday: SavedTrip? {
        let calendar = Calendar.current
        let now = Date()
        return myTrips.first { trip in
            guard let start = trip.startDate else { return false }
            let end = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: start)) ?? start
            return now >= calendar.startOfDay(for: start) && now < end
        }
    }

    /// Today's driving leg, when a real trip is under way and today is one of its driving
    /// days. Curated leg data only exists for the seed, so this is populated only when the
    /// active trip *is* the seed by code — but the seed reaches here through `myTrips`, i.e.
    /// only if the user kept it rather than on a pristine install.
    var todayLeg: CuratedLeg? {
        guard let trip = activeTripToday, trip.id == "seed" else { return nil }
        return today.leg.flatMap { library.legs.indices.contains($0) ? library.legs[$0] : nil }
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
        // This used to empty `paths[tab]` when the incoming tab was the one already
        // showing, to return that tab to its root the way other iOS apps do on a re-tap.
        // But `TabView` writes its selection back through this binding at moments that are
        // not user taps — scene restoration, and re-establishing selection after an update
        // — and each of those carries the *current* tab, so it took the same branch and
        // wiped a stack the user was standing in, mid view-update. That is what made Back
        // do nothing and a push vanish, and it is why `applyLaunchArguments` below has to
        // re-push until the push sticks.
        //
        // Losing re-tap-to-root is the smaller cost: it is a convenience, and Back working
        // every time is not.
        guard self.tab != tab else { return }
        withAnimation(.snappy(duration: 0.22)) {
            self.tab = tab
        }
        persist()
    }

    func push(_ screen: PushedScreen) {
        paths[tab, default: []].append(screen)
    }

    func pop() {
        _ = paths[tab]?.popLast()
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
                || value("wpDemoTrip") != nil || value("wpPlanAround") != nil
                || value("wpPopTest") != nil else { return }

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
                    // Push until it sticks, then stop. Re-checking "is the stack empty"
                    // on every pass meant a Back tapped within the first two seconds was
                    // undone by the next one.
                    var pushed = false
                    for _ in 0..<5 where !pushed {
                        if self.stack.isEmpty {
                            self.openPark(code, segment: segment)
                        } else {
                            pushed = true
                        }
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
            // Opens a park, then pops it, so the back path can be photographed.
            if value("wpPopTest") != nil {
                try? await Task.sleep(for: .seconds(4))
                self.pop()
            }
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
            if value("wpStateParks") != nil {
                self.tab = .today
                self.push(.explore)
                self.discoverShowsState = true
            }
            if let hex = value("wpTint"), PageTint.colour(from: hex) != nil {
                PageTint.shared.hex = hex
            }
            if let term = value("wpFind") {
                self.tab = .today
                self.push(.explore)
                if term != "1" {
                    self.discoverQuery = term
                    self.suggestions.update(term)
                    self.directory.search(term)
                }
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
                    // A fixture, and only ever reachable from the capture flag. This used to
                    // borrow Zion's first bundled alert; alerts are the park service's now,
                    // and a screenshot run cannot wait on the network for one.
                    if let park = self.library.park("zion") {
                        self.sheet = .alert(park: park.name, alert: CuratedAlert(
                            cat: "Danger",
                            title: "Flash flood risk in the narrows",
                            body: "Sample alert for screenshot capture. Live alerts come from the National Park Service."
                        ))
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
                self.tab = .today
                self.push(.explore)
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

    func openPark(_ code: String, segment: ParkSegment = .brief, date: Date? = nil) {
        parkSegment[code] = segment
        push(.park(code: code, segment: segment, date: date))
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
        // `park(_:)` resolves the curated eight, the live directory, the bundled sixty-two
        // and the state list — every code the picker can produce.
        builder.resolvePark = { [weak self] code in self?.park(code) }
        self.builder = builder

        // Asked for once, when the builder opens. The list shows its curated order until
        // this answers and re-sorts, so a refusal or a slow fix costs nothing.
        Task { [weak builder] in
            guard let fix = await LocationService.shared.currentFix() else { return }
            builder?.nearby = (fix.lat, fix.lon)
        }
    }

    /// Reopens a planned trip in the builder, filled in as it was saved.
    func editTrip(_ trip: SavedTrip) {
        startBuilder()
        guard let builder else { return }
        builder.editingID = trip.id
        builder.picks = trip.codes
        builder.days = trip.days ?? [:]
        if let start = trip.startDate { builder.startDate = start }
        builder.origin = trip.origin
        // The searched city, where the trip was planned from one. Without this an edited
        // trip would silently fall back to whichever of the shipped six `origin` names.
        if let name = trip.originName, let lat = trip.originLat, let lon = trip.originLon {
            builder.pickedOrigin = TripOrigin(name: name, lat: lat, lon: lon)
        }
        builder.liveResults = trip.codes.compactMap { park($0) }
        Haptics.tap()
    }

    /// Hands the directory's findings to the open builder, if there is one.
    func refreshBuilderResults() {
        builder?.liveResults = directory.hits.map(\.park)
    }

    func finishBuilder() {
        guard let builder else { return }
        let trip = builder.compose()
        // An edit composes a fresh identity — the id carries the parks, the origin and the
        // date, and the routing cache is keyed on it, so keeping the old one would hand
        // back the legs of the trip as it used to be. The new trip takes the old one's
        // place in the list rather than appearing above it.
        if let editingID = builder.editingID,
           let index = myTrips.firstIndex(where: { $0.id == editingID }) {
            myTrips[index] = trip
            self.builder = nil
            show("\(trip.title) updated")
        } else {
            myTrips.insert(trip, at: 0)
            self.builder = nil
            show("\(trip.title) composed")
        }
        tab = .trips
        persist()
    }

    // MARK: Persistence

    /// A park the traveller has been to, for the Profile rail.
    struct Visit: Identifiable, Hashable {
        var park: CuratedPark
        /// Absent on a park added by hand — see `manualVisits`.
        var date: Date?
        var id: String { park.code }

        /// "October 2025", or nothing at all rather than a guess.
        var when: String? {
            date.map { $0.formatted(.dateTime.month(.wide).year()) }
        }
    }

    /// Everywhere they have been, newest first.
    ///
    /// Three sources, deduplicated by park code: a trip whose dates have passed, a
    /// passport stamp, and anything added by hand. Nothing is invented — a clean install
    /// has none of the three and the rail is empty, which is the true answer.
    var visitRail: [Visit] {
        var seen = Set<String>()
        var out: [Visit] = []

        func add(_ code: String, _ date: Date?) {
            guard !seen.contains(code), !hiddenVisits.contains(code), let park = park(code) else { return }
            seen.insert(code)
            out.append(Visit(park: park, date: date))
        }

        for trip in myTrips {
            guard let start = trip.startDate, start < Date() else { continue }
            for code in trip.codes { add(code, start) }
        }
        for code in stamps { add(code, nil) }
        for code in manualVisits { add(code, nil) }

        return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Adds a park to the rail by hand. Already-visited parks are not added twice.
    func addVisit(_ code: String) {
        // Lifting the suppression comes first: a park taken off the rail and put back is
        // the common case of a mistaken tap, and it has a stamp or a trip behind it that
        // `visitRail` will supply again on its own.
        let wasHidden = hiddenVisits.remove(code) != nil
        let onRail = visitRail.contains { $0.id == code }
        guard !onRail || wasHidden else { return }
        if !onRail { manualVisits.append(code) }
        persist()
        if let park = park(code) {
            ParkPhotos.shared.load(park)
            show("\(park.name) added")
        }
    }

    /// Takes a park back off the visited rail.
    ///
    /// The hand-added entry goes for good; a stamp or a past trip is suppressed rather
    /// than deleted, so the passport count and the itinerary survive being told "I have
    /// not been here". Tapping visited again undoes all of it.
    func removeVisit(_ code: String) {
        manualVisits.removeAll { $0 == code }
        hiddenVisits.insert(code)
        persist()
        if let park = park(code) {
            show("\(park.name) removed from visited")
        }
    }

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
        /// Optional, so a snapshot written before the visited rail existed still decodes.
        var visits: [String]?
        /// Parks taken off the rail by hand. Optional for the same reason.
        var unvisits: [String]?
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
            seedHidden: seedTripHidden,
            visits: manualVisits,
            unvisits: Array(hiddenVisits)
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        day = snapshot.day
        manualVisits = snapshot.visits ?? []
        hiddenVisits = Set(snapshot.unvisits ?? [])
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

/// Somewhere a trip starts from, as coordinates rather than as one of six codes.
struct TripOrigin: Codable, Hashable {
    /// "Dallas, TX"
    var name: String
    var lat: Double
    var lon: Double

    var shortName: String { name.split(separator: ",").first.map(String.init) ?? name }
}

struct SavedTrip: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var dates: String
    var route: String
    var codes: [String]
    var origin: String
    var tag: String
    var live: Bool
    /// The origin as chosen by search. Absent on trips saved before origins could be
    /// anything but the shipped six, and on those `origin` alone still resolves — so an
    /// old snapshot decodes and keeps working rather than losing its starting point.
    var originName: String? = nil
    var originLat: Double? = nil
    var originLon: Double? = nil
    /// Nights in each park, by code. The builder has always collected these and then
    /// thrown them away on compose, so a trip could be planned as two days at Zion and
    /// three at Bryce and remembered as neither. Optional, so a trip saved before this
    /// existed still decodes and simply reopens at the builder's default.
    var days: [String: Int]? = nil

    /// Where this trip actually starts. Prefers the searched city; falls back to the code.
    func resolvedOrigin(_ library: CuratedLibrary) -> TripOrigin? {
        if let originName, let originLat, let originLon {
            return TripOrigin(name: originName, lat: originLat, lon: originLon)
        }
        return library.city(origin).map {
            TripOrigin(name: $0.shortName, lat: $0.lat, lon: $0.lon)
        }
    }

    /// The day the trip starts, recovered from its display label.
    ///
    /// `dates` being a formatted English string rather than a `Date` is its own problem,
    /// but the weather panel needs a real day to ask about — otherwise a park opened from
    /// a trip next month reports today's forecast. Handles both "12 September 2026" and
    /// the seed's "5 – 14 August 2026", taking the first day number in either.
    var startDate: Date? {
        let parts = dates.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard let day = parts.first(where: { $0.allSatisfy(\.isNumber) }),
              let month = parts.first(where: { $0.allSatisfy(\.isLetter) }),
              let year = parts.last(where: { $0.count == 4 && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.date(from: "\(day) \(month) \(year)")
    }

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
    /// The trip being changed, where this is not a new one.
    ///
    /// A planned trip could be deleted and started again and nothing else — so correcting
    /// a date meant re-picking every park. The three questions the builder already asks
    /// are exactly the three a reader wants to change, so it answers both jobs.
    var editingID: String?
    /// The day the trip starts, as a real date. This was a string cycled through four
    /// hard-coded weeks, which is why tapping the field jumped to a random-looking date
    /// rather than opening a calendar.
    var startDate = Calendar.current.startOfDay(for: Date())
    /// The date in the "12 September 2026" form the rest of the app stores and parses.
    var startLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: startDate)
    }
    /// One of the shipped six. Ignored once `pickedOrigin` is set.
    var origin = "den"
    /// A city found by search, which is any city in the country rather than one of six.
    var pickedOrigin: TripOrigin?

    /// Where this trip will start: the searched city if there is one, else the code.
    var resolvedOrigin: TripOrigin? {
        if let pickedOrigin { return pickedOrigin }
        return library.city(origin).map {
            TripOrigin(name: $0.shortName, lat: $0.lat, lon: $0.lon)
        }
    }
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
    /// Set by `AppState` so a pick can be named whatever source it came from. Without it
    /// the builder only knows the curated eight, and every `np-…` or `sp-…` pick resolved
    /// to nothing — a blank review row and a trip titled " to ".
    var resolvePark: ((String) -> CuratedPark?)?
    /// Where the phone is, so the untyped list leads with what is actually near.
    ///
    /// Nil until Core Location answers, and nil for good if it refuses — in which case the
    /// list keeps its curated order rather than pretending to a ranking it cannot make.
    var nearby: (lat: Double, lon: Double)?

    private func resolve(_ code: String) -> CuratedPark? {
        resolvePark?(code) ?? library.park(code)
    }
    var composeProgress: Double = 0
    var composing = false

    init(vehicleIsElectric: Bool) {
        self.vehicleIsElectric = vehicleIsElectric
    }

    var library: CuratedLibrary { .shared }

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
            add(NationalParks.all.map(CuratedPark.init(bundled:)))
            // With nothing typed this was a fixed list — the same eight in the same order
            // whether the phone was in Denver or in Maine, then the other fifty-four in the
            // order they happen to sit in the file. The first thing anybody plans a trip
            // around is what they can reach, so rank by that when the phone will say where
            // it is, and keep the curated order when it will not.
            guard let nearby else { return out }
            return out.sorted {
                Geo.haversine(nearby, ($0.lat, $0.lon)) < Geo.haversine(nearby, ($1.lat, $1.lon))
            }
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
        case 1: return "Pick them in the order you want to visit. How long in each comes next."
        case 2: return "Waypost sizes the legs and the offline packs from these."
        default: return "Composing takes a moment — the order of the legs is worked out from the coordinates."
        }
    }

    var stepLabel: String { "Step \(min(step, 3)) of 3" }

    var nextLabel: String {
        switch step {
        case 1: return picks.isEmpty ? "Pick a park to continue" : "Dates and origin"
        case 2: return "Review"
        // An edit is not a composition: the trip already exists and this replaces it.
        default: return editingID == nil ? "Compose the itinerary" : "Save changes"
        }
    }

    var pickNote: String {
        picks.isEmpty
            ? "Nothing picked yet"
            : "\(picks.count) park\(picks.count == 1 ? "" : "s") · \(totalDays) days in the parks"
    }

    var isNextDisabled: Bool { step == 1 && picks.isEmpty }

    var reviewRows: [(label: String, value: String)] {
        let originName = resolvedOrigin?.name ?? origin
        return [
            ("Parks", picks.compactMap { resolve($0)?.name }.joined(separator: " → ")),
            ("Days afield", "\(totalDays) in the parks, plus travel"),
            ("First day", startLabel),
            ("Setting out from", originName),
            ("Between stops", flyWhenFaster ? "Fly when it is faster" : "Drive"),
            ("Vehicle", vehicleIsElectric ? "Electric — charge stops added to every leg" : "Gasoline"),
        ]
    }

    /// Names the trip from the parks that actually resolved.
    ///
    /// Never composes a title out of empty strings: with nothing resolved the trip is
    /// named rather than left as " to ". The single-park case also stops assuming the date
    /// label has a second word — "Zion in " was the result when it did not.
    private static func title(parks: [CuratedPark], startLabel: String) -> String {
        let names = parks.map(\.name)
        switch names.count {
        case 0:
            return "Untitled trip"
        case 1:
            guard let month = startLabel.split(separator: " ").dropFirst().first else { return names[0] }
            return "\(names[0]) in \(month)"
        default:
            return "\(names[0]) to \(names[names.count - 1])"
        }
    }

    static let composeSteps = [
        "Ordering the parks by road distance",
        "Routing the legs",
        "Reading August normals for your dates",
        "Checking campsite availability",
        "Sizing the offline packs",
    ]

    /// Composes the trip, resolving each pick through the caller's resolver.
    ///
    /// This used to call `library.park`, which only knows the curated eight — but the
    /// picker offers the sixty-two bundled parks (`np-…`) and the state list (`sp-…`) too.
    /// Every pick outside the eight resolved to nothing, so `parks` came back empty and
    /// the title was composed out of two empty strings: a trip literally called " to ".
    func compose() -> SavedTrip {
        let parks = picks.compactMap(resolve)
        let start = resolvedOrigin
        let originName = start?.shortName ?? "Home"
        return SavedTrip(
            // The origin belongs in the identity: without it, changing where a trip starts
            // produced the same id, and the routing cache handed back the old city's legs.
            id: "trip-\(picks.joined(separator: "-"))-\(start?.name ?? origin)-\(startLabel.hashValue)",
            title: Self.title(parks: parks, startLabel: startLabel),
            dates: startLabel,
            route: ([originName] + parks.map(\.name)).joined(separator: " · "),
            codes: picks,
            origin: origin,
            tag: "Planned",
            live: false,
            originName: start?.name,
            originLat: start?.lat,
            originLon: start?.lon,
            days: days
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

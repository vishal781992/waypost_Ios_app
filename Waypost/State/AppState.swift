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
    case stamp(name: String, city: String, dist: String)

    var id: String {
        switch self {
        case .alert(let park, let alert): return "alert:\(park):\(alert.title)"
        case .permit(let drop): return "permit:\(drop.what)"
        case .leg(let index, _): return "leg:\(index)"
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

    // The day you are living in — day 5 of the seed trip, as the design opens.
    var day: Int = 5

    // Today
    var doneItems: Set<String> = ["a0"]
    var liveActivityOn = false
    var journalCount = 2

    // Notifications
    var notifyPermits = true
    var notifyAlerts = true
    var notifyLive = false

    // Offline packs
    var packs: [String: PackState] = ["romo": .ready, "arch": .ready]
    var packProgress: [String: Double] = [:]

    // Library
    var saved: [String] = ["grte", "glac"]
    var stamps: Set<String> = ["cany", "dino", "brca", "flfo", "meve"]
    var savedShowsPassport = false

    // Discover
    var discoverQuery = ""
    var discoverChip = "all"

    // Preferences
    var vehicleIsElectric = true
    var unitsMetric = false

    // Per-screen segment memory
    var parkSegment: [String: ParkSegment] = [:]
    var tripSegment: [String: TripSegment] = [:]

    // Trip building
    var builder: TripBuilder?
    var myTrips: [SavedTrip] = []

    // Transient
    var toast: String?
    private var toastTask: Task<Void, Never>?
    private var packTasks: [String: Task<Void, Never>] = [:]

    let library = CuratedLibrary.shared

    init() { restore() }

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
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            stack.append(screen)
        }
    }

    func pop() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            _ = stack.popLast()
        }
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
        myTrips + [SavedTrip.seed(dayNumber: today.d)]
    }

    func trip(_ id: String) -> SavedTrip? { trips.first { $0.id == id } }

    func startBuilder() {
        builder = TripBuilder(vehicleIsElectric: vehicleIsElectric)
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
            passport: savedShowsPassport
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

    static let past: [(title: String, dates: String, sub: String)] = [
        ("North Cascades & Olympic", "October 2025", "2 parks · 8 days · 1,240 mi"),
        ("Big Bend at New Year", "December 2024", "1 park · 5 days · 890 mi"),
    ]
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
    var query = ""
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

    var results: [CuratedPark] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = library.orderedParks
        guard !q.isEmpty else { return all }
        return all.filter { ($0.name + " " + $0.state + " " + $0.tag).lowercased().contains(q) }
    }

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

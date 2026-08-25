import CoreLocation
import EventKit
import Foundation

/// The trip, against the calendar the traveller already keeps.
///
/// Two jobs, and they need different permissions, which is the thing that shapes this whole
/// file. iOS 17 split calendar access in two: **write-only**, which lets an app add events
/// and read nothing back, and **full**, which lets it look. Putting a trip on the calendar
/// needs the first. Finding out what a trip clashes with needs the second. So the app asks
/// for the smaller one when that is all it needs, and for the larger one only when somebody
/// turns clash-checking on — where there is a switch to explain it next to.
///
/// **Its own calendar.** Everything written goes into a calendar of the app's own, and every
/// query for clashes excludes that calendar. This is what stops a trip clashing with itself
/// the moment it is added — a fault the first sketch of this feature answered by switching
/// the checking off, which throws the feature away exactly when it starts to matter, because
/// once a trip is committed is when other people start booking things into those days. It
/// also means the traveller can hide every trip with one switch in Apple Calendar, and that
/// nothing here depends on `eventIdentifier`, which is not stable across a sync.
///
/// **What counts as a clash.** Not "any event in the window" — everybody's calendar has
/// something in it, and a light that is always on is not a light. An event counts if it is
/// busy time: anything marked free is skipped unless it runs all day, and a declined or
/// cancelled event is skipped outright. Birthday and subscribed calendars are skipped
/// wholesale, because a national holiday is not a commitment and a calendar full of them
/// would make every trip look impossible.
///
/// **Never a green light it has not earned.** With no access, or with write-only, `clashes`
/// stays empty and `access` says why. Nothing in the app may read an empty list as "clear"
/// without checking that too — the difference between "nothing found" and "nothing looked
/// for" is the whole of this app's guiding rule.
@MainActor
@Observable
final class TripCalendar {
    static let shared = TripCalendar()

    /// What the system will currently let the app do.
    enum Access: Equatable {
        case notAsked
        /// Can add events. Cannot read one back, which means it cannot find clashes and
        /// cannot remove what it wrote.
        case writeOnly
        case full
        case denied
        case restricted

        var canWrite: Bool { self == .writeOnly || self == .full }
        var canRead: Bool { self == .full }
    }

    /// Somebody else's claim on one of the trip's days.
    struct Clash: Identifiable, Hashable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool

        var id: String { "\(title)|\(start.timeIntervalSince1970)" }

        /// "all day", or the hour it starts.
        var whenLabel: String {
            allDay ? "all day" : start.formatted(date: .omitted, time: .shortened)
        }

        /// Whether this event runs over any part of the given day.
        func covers(_ day: Date) -> Bool {
            let calendar = Calendar.current
            let from = calendar.startOfDay(for: day)
            guard let to = calendar.date(byAdding: .day, value: 1, to: from) else { return false }
            return start < to && end > from
        }
    }

    /// One day of a trip, as it will be written.
    struct Entry: Hashable, Sendable {
        var day: Date
        var title: String
        var notes: String
        var place: String?
        var lat: Double?
        var lon: Double?
    }

    /// A whole trip, ready to be written. A value type, so it crosses to the vault.
    struct Plan: Hashable, Sendable {
        var tripID: String
        var title: String
        var entries: [Entry]
    }

    private(set) var access: Access = .notAsked
    /// What each trip's days run into, by trip id. Only ever filled where `access` is full.
    private(set) var clashes: [String: [Clash]] = [:]
    /// Trips currently being written, removed or looked over — so a row can say so.
    private(set) var working: Set<String> = []
    /// The last thing that went wrong, in a sentence fit to show.
    private(set) var trouble: String?
    /// The calendar the last trip actually went into.
    ///
    /// Usually the app's own. Where no account on the phone would hold a calendar of ours
    /// — which is what write-only access means in practice — it is whichever calendar new
    /// events already go to, and a screen that went on promising "a calendar of its own"
    /// would be describing something that was never made.
    private(set) var wroteInto: String?

    private let vault = CalendarVault()
    /// The busy time last read, and the window it was read over.
    ///
    /// Kept apart from `clashes` so that a second trip whose days fall inside a window
    /// already read can be sorted out of what is in hand rather than being answered from an
    /// empty table — which is the difference between "this trip is clear" and "nobody has
    /// asked about this trip", and only one of those is true.
    private var found: [Clash] = []
    private var scanned: ClosedRange<Date>?

    private init() {
        readAccess()
        // The calendar changes while the app is open — another device syncs, somebody
        // accepts an invitation — and a check made at launch would be wrong by lunchtime.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.invalidate() }
        }
    }

    // MARK: What we are allowed to do

    /// The status as the system currently reports it. Cheap, and safe to call often.
    func readAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .full
        case .writeOnly: access = .writeOnly
        case .denied: access = .denied
        case .restricted: access = .restricted
        case .notDetermined: access = .notAsked
        @unknown default: access = .notAsked
        }
    }

    /// Ask for the smaller permission: enough to put a trip on the calendar.
    ///
    /// Skipped where full access is already held — asking again would show nothing and
    /// return the same answer.
    @discardableResult
    func askToWrite() async -> Bool {
        if access == .full { return true }
        let granted = await vault.requestWriteOnly()
        readAccess()
        return granted && access.canWrite
    }

    /// Ask for the larger permission: enough to see what the trip runs into.
    @discardableResult
    func askToRead() async -> Bool {
        let granted = await vault.requestFull()
        readAccess()
        if !granted { clashes = [:] }
        return granted && access.canRead
    }

    // MARK: Looking for clashes

    /// Throw away what was found. The next screen that wants it will ask again.
    func invalidate() {
        scanned = nil
        found = []
        clashes = [:]
    }

    /// Look over every day of every trip given, in one pass.
    ///
    /// One query across the whole span rather than one per trip: `events(matching:)` is a
    /// synchronous trawl of the calendar database, and asking it nine times for nine
    /// overlapping weeks is nine times the work for the same answer. The events come back
    /// once and are sorted into trips here.
    ///
    /// Does nothing without full access, and says nothing either — `clashes` staying empty
    /// is not a finding.
    func look(over trips: [String: [Date]]) async {
        guard access.canRead, !trips.isEmpty else { return }
        let allDays = trips.values.flatMap { $0 }
        guard let first = allDays.min(), let last = allDays.max() else { return }

        let calendar = Calendar.current
        let from = calendar.startOfDay(for: first)
        guard let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))
        else { return }
        // The calendar is only read again where the stretch asked about runs outside the
        // one already in hand. `EKEventStoreChanged` throws all of it away, so this cannot
        // go stale behind somebody's back.
        let covered = scanned.map { $0.lowerBound <= from && $0.upperBound >= to } ?? false
        if !covered {
            working.insert(Self.scanning)
            found = await vault.busy(from: from, to: to)
            scanned = from...to
            working.remove(Self.scanning)
        }

        // Answers for trips not asked about here are kept: they were sorted out of a window
        // this one may not cover, and dropping them would turn a checked trip back into an
        // unchecked one on the next screen that reads it.
        var sorted = clashes
        for (trip, days) in trips {
            // Written even when empty, because an empty answer to a question that *was*
            // asked is a finding, and the table is how the app tells the two apart.
            sorted[trip] = found
                .filter { clash in days.contains { clash.covers($0) } }
                .sorted { $0.start < $1.start }
        }
        clashes = sorted
    }

    /// What one trip runs into, if anybody has looked.
    func clashes(for trip: String) -> [Clash] { self.clashes[trip] ?? [] }

    /// Whether this trip has actually been looked over, as against found to be clear.
    func hasLooked(at trip: String) -> Bool {
        access.canRead && self.clashes[trip] != nil
    }

    /// What one day of a trip runs into.
    func clashes(for trip: String, on day: Date?) -> [Clash] {
        guard let day else { return [] }
        return clashes(for: trip).filter { $0.covers(day) }
    }

    // MARK: Writing a trip down

    /// Put a trip on the calendar, one all-day entry per day.
    ///
    /// All-day rather than timed, even though the hours are known. The hours were worked
    /// out in whatever time zone the phone was in when the trip was planned, and a trip
    /// that crosses three of them would drift against a timed event — so the day is the
    /// claim and the hours go in the notes, where being approximate is what they look like.
    @discardableResult
    func add(_ plan: Plan) async -> Bool {
        guard !plan.entries.isEmpty else { return false }
        guard await askToWrite() else {
            trouble = access == .denied
                ? "Calendar access is off for ParkHop. Settings › Privacy › Calendars turns it back on."
                : "Nothing was written: the calendar did not give permission."
            return false
        }
        working.insert(plan.tripID)
        defer { working.remove(plan.tripID) }

        switch await vault.write(plan) {
        case .success(let calendar):
            trouble = nil
            wroteInto = calendar.isEmpty ? nil : calendar
            // What was just written must not come back as a clash with itself. It is in the
            // app's own calendar and so already excluded, but the window has been read.
            invalidate()
            return true
        case .failure(let why):
            trouble = why
            return false
        }
    }

    /// Take a trip back off the calendar.
    ///
    /// Needs full access, because finding what to delete means reading. An app with
    /// write-only can put a trip on the calendar and cannot take it off again — that is the
    /// permission working as designed, and it is said plainly rather than failing quietly.
    @discardableResult
    func remove(_ tripID: String) async -> Bool {
        guard access.canRead else {
            trouble = "Taking a trip back off the calendar means reading it first. Turn on clash-checking, or delete the entries in Calendar."
            return false
        }
        working.insert(tripID)
        defer { working.remove(tripID) }

        switch await vault.erase(tripID: tripID) {
        case .success:
            trouble = nil
            invalidate()
            return true
        case .failure(let why):
            trouble = why
            return false
        }
    }

    /// The name of the calendar everything is written into, for a screen that wants to say
    /// where a trip went.
    static let calendarTitle = "ParkHop trips"

    /// A stand-in trip id, so a scan in progress can be told from a trip being written.
    private static let scanning = "«scan»"

    // MARK: Turning a trip into entries

    /// The trip as the calendar should hold it.
    ///
    /// Built here rather than in the vault so that everything needing the app's own model —
    /// the composed days, the parks, what there is to do — stays on this side, and what
    /// crosses to EventKit is a plain value.
    static func plan(for trip: SavedTrip, days: [TripDays.Day], parks: [CuratedPark]) -> Plan {
        let byCode = Dictionary(parks.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [Entry] = []

        for day in days {
            guard let date = day.date else { continue }
            var title = ""
            var lines: [String] = []
            var place: String?
            var park: CuratedPark?

            switch day.kind {
            case .travel(let from, let to, let miles, let drive, let fly):
                if let fly {
                    title = "Fly \(from) → \(to)"
                    lines.append("\(fly.via) · \(fly.time)")
                    lines.append("\(miles) mi · \(drive) if driven instead")
                } else {
                    title = day.parts > 1
                        ? "Drive \(from) → \(to) · day \(day.part) of \(day.parts)"
                        : "Drive \(from) → \(to)"
                    lines.append("\(miles) mi · \(drive)")
                }
                if let departs = day.departs, let arrives = day.arrives {
                    lines.append("About \(departs.formatted(date: .omitted, time: .shortened)) to "
                                 + arrives.formatted(date: .omitted, time: .shortened) + ".")
                }
                if let arrivalLine = day.arrivalLine { lines.append(arrivalLine) }
                place = to

            case .park(let code, let name, let number, let of):
                title = of > 1 ? "\(name) · day \(number) of \(of)" : name
                park = byCode[code]
                place = park?.full ?? name
                if day.doings.isEmpty {
                    if let note = day.doingsNote { lines.append(note) }
                } else {
                    lines.append(contentsOf: day.doings.map { doing in
                        [doing.title, doing.duration].compactMap { $0 }.joined(separator: " — ")
                    })
                }
            }

            if !day.stops.isEmpty {
                lines.append("Worth stopping for: "
                             + day.stops.map(\.name).joined(separator: ", ") + ".")
            }
            lines.append("Planned in ParkHop · \(trip.title)")

            entries.append(Entry(day: date, title: title,
                                 notes: lines.joined(separator: "\n"),
                                 place: place, lat: park?.lat, lon: park?.lon))
        }
        return Plan(tripID: trip.id, title: trip.title, entries: entries)
    }
}

/// Everything that touches EventKit, off the main actor.
///
/// `events(matching:)` is a synchronous trawl of the calendar database and `commit()` writes
/// to it; neither belongs on the thread drawing the screen. An actor rather than a queue,
/// for the same reason `PhotoStore` is one: it owns a single `EKEventStore` and serialises
/// everything that reaches it, and everything crossing the boundary is a value.
private actor CalendarVault {
    private let store = EKEventStore()
    /// Set once the app's own calendar has been found or made, so a trip with a dozen days
    /// does not look it up a dozen times.
    private var mine: EKCalendar?

    /// Where the app's own calendar is remembered between launches. Its identifier rather
    /// than its title: a traveller may rename it, and a renamed calendar is still theirs.
    private static let key = "waypost.calendar.identifier"

    // MARK: Permission

    func requestFull() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func requestWriteOnly() async -> Bool {
        (try? await store.requestWriteOnlyAccessToEvents()) ?? false
    }

    // MARK: Reading

    /// Busy time between two dates, in every calendar but the app's own.
    func busy(from: Date, to: Date) -> [TripCalendar.Clash] {
        let ours = existingCalendar()?.calendarIdentifier
        let searched = store.calendars(for: .event).filter { calendar in
            // Not the app's own — a trip must never clash with itself.
            guard calendar.calendarIdentifier != ours else { return false }
            // A birthday is not a commitment, and a subscribed calendar of national
            // holidays would put an all-day event on a fifth of the year.
            return calendar.type != .birthday && calendar.type != .subscription
        }
        guard !searched.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: searched)
        return store.events(matching: predicate).compactMap { event -> TripCalendar.Clash? in
            guard event.status != .canceled else { return nil }
            // The app's own entries, wherever they were written. Excluding the app's
            // calendar is not enough on a phone whose account would not hold one.
            if event.url?.scheme == "parkhop" { return nil }
            // Something already turned down is not a clash.
            if let me = event.attendees?.first(where: \.isCurrentUser),
               me.participantStatus == .declined { return nil }
            // Free time is not busy time — except when it runs all day, which is how a
            // conference, a holiday and a wedding are all filed.
            guard event.isAllDay || event.availability != .free else { return nil }
            guard let start = event.startDate, let end = event.endDate else { return nil }
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return TripCalendar.Clash(title: title.isEmpty ? "Busy" : title,
                                      start: start, end: end, allDay: event.isAllDay)
        }
    }

    // MARK: Writing

    enum Outcome {
        /// Written, and the name of the calendar it went into — which is not always the
        /// app's own, so the screen that reports it can say where the trip actually is.
        case success(String)
        case failure(String)
    }

    /// Why the last attempt to get a calendar failed, in the system's own words.
    private var lastTrouble: String?

    func write(_ plan: TripCalendar.Plan) -> Outcome {
        guard let calendar = calendarForWriting() else {
            return .failure(lastTrouble
                            ?? "No calendar on this phone would accept the trip.")
        }
        do {
            for entry in plan.entries {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = entry.title
                event.notes = entry.notes
                event.isAllDay = true
                // A day, exactly: from its first second to its last. Setting both ends to
                // the same instant is read differently by different calendar clients.
                let day = Calendar.current.startOfDay(for: entry.day)
                event.startDate = day
                event.endDate = (Calendar.current.date(byAdding: .day, value: 1, to: day)
                                 ?? day).addingTimeInterval(-1)
                // What ties the event back to the trip. Not `eventIdentifier`, which does
                // not survive a sync — this is written by the app and read by the app.
                event.url = Self.link(to: plan.tripID)
                if let lat = entry.lat, let lon = entry.lon, let place = entry.place {
                    let located = EKStructuredLocation(title: place)
                    located.geoLocation = CLLocation(latitude: lat, longitude: lon)
                    event.structuredLocation = located
                } else if let place = entry.place {
                    event.location = place
                }
                // Held back and committed in one go: a dozen separate commits is a dozen
                // separate writes to the calendar database and a dozen sync notifications.
                try store.save(event, span: .thisEvent, commit: false)
            }
            try store.commit()
            return .success(calendar.title)
        } catch {
            store.reset()
            return .failure("The calendar refused the trip: \(error.localizedDescription)")
        }
    }

    func erase(tripID: String) -> Outcome {
        // Without a link there is nothing to match on, and matching on nothing would delete
        // every entry in the calendar rather than this trip's.
        guard let link = Self.link(to: tripID) else {
            return .failure("That trip has no name the calendar can be searched by.")
        }
        // Every calendar that can be edited, not only the app's own: where no account
        // would accept a calendar of ours the trip was written into the default one, and a
        // removal that only looked in ours would quietly find nothing. The link is what
        // identifies the trip either way.
        let searched = store.calendars(for: .event).filter(\.allowsContentModifications)
        guard !searched.isEmpty else { return .success("") }

        // Wide enough to hold any trip anybody plans in this app, and narrow enough that
        // the predicate is still doing work: four years back, four forward.
        let now = Date()
        let from = now.addingTimeInterval(-4 * 365 * 86_400)
        let to = now.addingTimeInterval(4 * 365 * 86_400)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: searched)
        do {
            for event in store.events(matching: predicate) where event.url == link {
                try store.remove(event, span: .thisEvent, commit: false)
            }
            try store.commit()
            return .success("")
        } catch {
            store.reset()
            return .failure("The calendar refused to remove the trip: \(error.localizedDescription)")
        }
    }

    // MARK: The app's own calendar

    private static func link(to tripID: String) -> URL? {
        URL(string: "parkhop://trip/\(tripID)")
    }

    private func existingCalendar() -> EKCalendar? {
        if let mine { return mine }
        guard let identifier = UserDefaults.standard.string(forKey: Self.key),
              let found = store.calendar(withIdentifier: identifier) else { return nil }
        mine = found
        return found
    }

    /// A calendar this trip can be written into.
    ///
    /// Three things go wrong here on a real phone, and the first version of this handled
    /// none of them:
    ///
    /// - **`sources` comes back empty.** EventKit fetches the accounts lazily, and a store
    ///   that has not refreshed since permission was granted — which is exactly the state
    ///   the very first tap is in — reports none at all. `refreshSourcesIfNecessary()` is
    ///   the fix, and without it every account lookup below returns nothing.
    /// - **Not every account will hold a new calendar.** A subscribed feed and the birthday
    ///   list refuse outright, and some accounts refuse for reasons the API does not expose
    ///   in advance. There is nothing to test, so this asks each in turn and keeps the one
    ///   that says yes.
    /// - **Write-only access can add events but not make calendars.** That is the
    ///   permission working as designed, and it is the likeliest reason to end up here with
    ///   nothing: the app asked for the smaller permission, as it should, and then tried to
    ///   do something the larger one is for.
    ///
    /// So when no account will take a calendar of ours, the trip goes into the calendar new
    /// events already go to rather than failing. It is still tagged with the trip's link, so
    /// it is still found for removal and still excluded from its own clash check — the
    /// separate calendar is a convenience, not the mechanism. The caller is told which
    /// calendar was used so the screen can say so rather than promising one that was never
    /// made.
    private func calendarForWriting() -> EKCalendar? {
        if let existing = existingCalendar() { return existing }

        // Lazily fetched, and empty on a store that has not refreshed since access was
        // granted. Every lookup below depends on this line having run.
        store.refreshSourcesIfNecessary()

        var candidates: [EKSource] = []
        if let preferred = store.defaultCalendarForNewEvents?.source { candidates.append(preferred) }
        candidates += store.sources.filter { $0.sourceType != .birthdays && $0.sourceType != .subscribed }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.sourceIdentifier).inserted }

        for source in candidates {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = TripCalendar.calendarTitle
            // The mark's orange, so the trip reads as this app's in a week of everything else.
            calendar.cgColor = CGColor(red: 0.85, green: 0.45, blue: 0.13, alpha: 1)
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.key)
                mine = calendar
                lastTrouble = nil
                return calendar
            } catch {
                lastTrouble = error.localizedDescription
            }
        }

        // Nothing would take one of ours. Write where new events already go.
        if let fallback = store.defaultCalendarForNewEvents, fallback.allowsContentModifications {
            lastTrouble = nil
            return fallback
        }

        lastTrouble = candidates.isEmpty
            ? "This phone has no calendar account ParkHop is allowed to write into."
            : "No calendar account would accept the trip." + (lastTrouble.map { " \($0)" } ?? "")
        return nil
    }
}

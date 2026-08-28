import MapKit
import SwiftUI

/// Discover — the catalogue, one park at a time, each carrying its own colour.
struct DiscoverScreen: View {
    @Environment(AppState.self) private var app
    @FocusState private var searchFocused: Bool

    /// Flipped by the close button, only so the tap can carry a haptic on its way out.
    @State private var closing = false

    /// Where the phone is. Asked for here rather than read off the recommender, which only
    /// has a fix once the Nearby screen has run — open the app straight onto Discover and it
    /// is nil, which is exactly the case this ordering is for.
    @State private var nearby: (lat: Double, lon: Double)?

    private let chips: [(id: String, label: String)] = [
        ("all", "Everything"), ("Desert", "Desert"), ("Alpine", "Alpine"),
        ("Coast", "Coast"), ("Geothermal", "Geothermal"), ("quiet", "Quieter"),
    ]

    /// The parks on the phone, nearest first.
    ///
    /// This was `orderedParks` alone: the shipped eight, in a hard-coded order, identical
    /// whether the phone was in Denver or in Maine — and the other fifty-four national
    /// parks already on the device were not offered at all until something was typed. With
    /// an empty field it now shows every one of them, ranked by distance from where the
    /// phone says it is, and keeps the curated order when location is refused.
    private var curated: [CuratedPark] {
        var list = app.library.orderedParks
        let query = app.discoverQuery.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            let seen = Set(list.map { $0.name.lowercased() })
            list += NationalParks.allCurated.filter { !seen.contains($0.name.lowercased()) }
            if let fix = nearby ?? app.recommender.fix {
                list.sort {
                    Geo.haversine(fix, ($0.lat, $0.lon)) < Geo.haversine(fix, ($1.lat, $1.lon))
                }
            }
        }

        if app.discoverChip == "quiet" {
            list = list.filter { $0.crowd.contains("Quiet") || $0.crowd.contains("Moderate") }
        } else if app.discoverChip != "all" {
            list = list.filter { $0.region == app.discoverChip }
        }
        let q = query.lowercased()
        if !q.isEmpty {
            list = list.filter { ($0.name + " " + $0.state + " " + $0.full).lowercased().contains(q) }
        }
        return list
    }

    /// Everything else in the country, from NPS and OpenStreetMap. Only while a search is
    /// running — with an empty field the screen still opens on the curated shelf.
    private var live: [CuratedPark] {
        guard !app.discoverQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let already = Set(curated.map { $0.name.lowercased() })
        var list = app.directory.hits.map(\.park).filter { !already.contains($0.name.lowercased()) }
        // A live record does not publish crowding, so it cannot answer "quieter".
        if app.discoverChip == "quiet" {
            list = []
        } else if app.discoverChip != "all" {
            list = list.filter { $0.region == app.discoverChip }
        }
        return list
    }

    private var results: [CuratedPark] { curated + live }

    /// Every national park on the phone: the curated shelf and the bundled register behind
    /// it, without the duplicates.
    private var allNational: [CuratedPark] {
        let shelf = app.library.orderedParks
        let seen = Set(shelf.map { $0.name.lowercased() })
        return shelf + NationalParks.allCurated.filter { !seen.contains($0.name.lowercased()) }
    }

    /// The city the words name, once Apple Maps has put it on the map.
    ///
    /// The state-park side has ranked its table around a typed city since it shipped; the
    /// national side matched park names and state names only, so "Castle Pines" — a real
    /// place with Rocky Mountain up the road — answered with nothing at all. The anchor
    /// was already being fetched for every query, whichever half of the toggle was on; it
    /// simply went unread here.
    private var cityAnchor: PlaceAnchor.Anchor? {
        guard !app.discoverQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return app.placeAnchor.anchor
    }

    /// National parks around that city, nearest first, minus anything the name search
    /// already answered with.
    private var aroundCity: [(park: CuratedPark, miles: Int)] {
        guard let anchor = cityAnchor else { return [] }
        let shown = Set(results.map { $0.name.lowercased() })
        let point = (lat: anchor.lat, lon: anchor.lon)
        return allNational
            .filter { !shown.contains($0.name.lowercased()) }
            .map { ($0, Geo.haversine(point, ($0.lat, $0.lon))) }
            .sorted { $0.1 < $1.1 }
            .prefix(6)
            .map { (park: $0.0, miles: Int($0.1.rounded())) }
    }

    /// What to say over that list.
    ///
    /// Two different answers wear the same heading: parks genuinely near the city, and —
    /// when the nearest is hours away — the nearest one in the city's own state, which is
    /// the honest answer to "what can I see from here" for most of the country.
    private var aroundCityNote: String? {
        guard let anchor = cityAnchor, let nearest = aroundCity.first else { return nil }
        let place = anchor.label
        if nearest.miles <= 120 {
            return "No national park is in \(place) itself. \(nearest.park.name) is \(nearest.miles) miles away."
        }
        let inState = aroundCity.first { anchor.state != nil && $0.park.stateName == anchor.state }
        if let inState, let state = anchor.state {
            return "No national park is near \(place). The nearest in \(state) is \(inState.park.name), \(inState.miles) miles away."
        }
        return "No national park is near \(place). The nearest is \(nearest.park.name), \(nearest.miles) miles away."
    }

    /// What the line over the masthead is counting — the catalogue the toggle is on.
    private var kicker: String {
        app.discoverShowsState
            ? "\(StateParkList.table.count.formatted()) state parks, one at a time"
            : "Sixty-three parks, one at a time"
    }

    /// The line under the chips now has to say where the parks came from: a search only
    /// OpenStreetMap answered is a different thing from one NPS answered, and neither is
    /// the shelf that ships with the app.
    private var note: String {
        let count = results.count
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces)
        let plural = count == 1 ? "park" : "parks"
        if q.isEmpty {
            let tail = app.discoverChip == "all"
                ? "the ParkHop catalogue"
                : app.discoverChip.lowercased() + " country"
            return "\(count) \(plural) · \(tail)"
        }
        switch app.directory.phase {
        case .searching:
            return "Searching NPS and OpenStreetMap for “\(q)”…"
        case .unanswered(let why):
            return why
        case .idle, .ready:
            let sources = app.directory.answered.map(\.rawValue).sorted().joined(separator: " · ")
            let from = sources.isEmpty ? "the ParkHop catalogue" : sources
            return "\(count) \(plural) matching “\(q)” · \(from)"
        }
    }

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // The state catalogue is three thousand parks from a table on the phone; the
            // national one is sixty-three from a register. Nothing said which of the two
            // you were in except the lime pill, and a pill is the control rather than the
            // state. The light behind the Island is the state.
            ScreenHeader(glow: app.discoverShowsState ? WP.lime : nil) {
                // A way out that does not depend on knowing about the back-swipe. This was
                // a tab, so it never needed one; reached from the Nearby header it does.
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        // The kicker counts whichever catalogue is on screen. It said
                        // sixty-three on both, which is the national count and a lie about
                        // the other three thousand.
                        Text(kicker).kickerStyle()
                        Text("Explore").font(WP.displayBold(44)).tracking(-0.4).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    GlassDisc(icon: "xmark", size: 44) {
                        closing = true
                        app.pop()
                    }
                    .accessibilityLabel("Close")
                    .sensoryFeedback(.impact(weight: .light), trigger: closing)
                    .padding(.top, 2)
                }
                .padding(.bottom, 10)

                // Two catalogues with different guarantees: the NPS registry, and the
                // state-park table that ships on the phone.
                SegmentedTrough(
                    options: [(false, "National"), (true, "State")],
                    selection: Binding(get: { app.discoverShowsState },
                                       set: { app.discoverShowsState = $0 })
                )
                .padding(.bottom, 10)

                TextField(app.discoverShowsState ? "State park, city or state…" : "Park or state…",
                          text: $app.discoverQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(WP.body(16))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .focused($searchFocused)
                    .searchFieldSurface(focus: $searchFocused)
                    .submitLabel(.search)
                    .onSubmit { app.suggestions.clear() }

                // What you might mean, while you are still typing it. Two letters is
                // enough — "te" offers Tennessee and Texas before any search has run, and
                // "au" offers Austin while the letters are still going in.
                if searchFocused, !app.suggestions.offered.isEmpty {
                    SuggestionList(items: app.suggestions.offered) { suggestion in
                        app.takeSuggestion(suggestion)
                        searchFocused = false
                    }
                    .padding(.top, 6)
                }

                if !app.discoverShowsState {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(chips, id: \.id) { chip in
                            let active = app.discoverChip == chip.id
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { app.discoverChip = chip.id }
                            } label: {
                                // The mark's orange rather than the lime the other selected
                                // controls wear: these chips filter the list under them
                                // rather than switching between two of anything, and they
                                // sit directly under the National / State trough, which is
                                // the control they were being mistaken for.
                                Text(chip.label)
                                    .font(WP.body(12.5))
                                    .padding(.horizontal, 15)
                                    .frame(minHeight: 44)
                                    .modifier(SelectedChip(active: active))
                            }
                            .buttonStyle(PressStyle(scale: 0.96))
                        }
                    }
                    .padding(.horizontal, WP.gutter)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, -WP.gutter)
                .padding(.top, 10)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    if app.discoverShowsState {
                        StateParkList(fix: nearby ?? app.recommender.fix)
                    } else {
                        // What is actually within reach today, before the catalogue.
                        NearbyCard()

                        Text(note).font(WP.bodyItalic(12)).opacity(0.6)

                        ForEach(results) { park in
                            DiscoverCard(park: park).liftOnScroll()
                        }

                        // A city is not a park name, so the catalogue above has nothing to
                        // say about one. This is the same question the state-park side has
                        // always answered: what is near the place you typed.
                        if let anchor = cityAnchor, !aroundCity.isEmpty {
                            SectionRule(dot: WP.accent, tint: WP.accent800,
                                        title: "Around \(anchor.label)",
                                        tail: "nearest first")
                                .padding(.top, results.isEmpty ? 0 : 8)

                            if let aroundCityNote {
                                Text(aroundCityNote)
                                    .font(WP.bodyItalic(12)).lineSpacing(3).opacity(0.65)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(aroundCity, id: \.park.id) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    DiscoverCard(park: entry.park).liftOnScroll()
                                    Text("\(entry.miles) miles from \(anchor.label)")
                                        .font(WP.body(11.5)).opacity(0.6).tnum()
                                }
                            }
                        } else if app.placeAnchor.isLocating {
                            Text("Finding “\(app.discoverQuery)” on the map…")
                                .font(WP.bodyItalic(11.5)).opacity(0.55)
                        }

                        if results.isEmpty, aroundCity.isEmpty, !app.placeAnchor.isLocating {
                            NothingByThatName()
                        }
                    }
                }
                .panelTransition(id: app.discoverShowsState)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 14)
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .captureScrollPosition()
            .task {
                guard nearby == nil else { return }
                if let fix = await LocationService.shared.currentFix() {
                    nearby = (fix.lat, fix.lon)
                }
            }
        }
        .onAppear {
            if app.focusSearchOnAppear {
                app.focusSearchOnAppear = false
                searchFocused = true
            }
        }
    }
}

struct DiscoverCard: View {
    /// The fee, from the park service, for any park — not from a bundled record that
    /// happens to exist for six of them.
    static func feeLine(_ park: CuratedPark) -> String {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park), let fee = facts.fee {
            return fee
        }
        return "Fees and hours from the park"
    }

    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    var park: CuratedPark
    /// Set when the card is in a list ranked by distance. How far it is answers the
    /// question that list is asking; the fee does not.
    var miles: Int?

    private var isSaved: Bool { app.saved.contains(park.code) }

    private var factLine: String {
        if let miles { return miles == 1 ? "1 mile away" : "\(miles) miles away" }
        return Self.feeLine(park)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.openPark(park.code)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    // A photograph where the park has one; the pinned monochrome map where
                    // it does not, so a picture-less state park is a located tile rather
                    // than a blank colour field.
                    if park.usesMapHero {
                        PinnedMap(lat: park.lat, lon: park.lon)
                    } else {
                        ParkImage(park: park)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        // State, then what kind of unit it is. The designation is the
                        // thing that tells a national park from a state park from a
                        // wildlife area, so it goes here rather than in a subtitle.
                        Text([park.stateName, park.designationLabel].filter { !$0.isEmpty }
                                .joined(separator: " · ").uppercased())
                            .font(WP.body(9)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.88))
                        Text(park.name)
                            .font(WP.display(28))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .shadow(color: Color(hex: 0x181008, opacity: 0.26), radius: 9, y: 1)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(.onPhoto, radius: 16)
                    .padding(9)
                }
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x1E1208, opacity: 0.18), radius: 15, y: 12)
                // The card grows into the park screen it opens.
                .zoomSource("park:" + park.code, in: zoom, clip: .card(22))
            }
            .buttonStyle(PressStyle(scale: 0.995))
            .contextMenu {
                Button {
                    app.openPark(park.code)
                } label: {
                    Label("Open \(park.name)", systemImage: "arrow.up.forward.square")
                }
                Button {
                    app.toggleSaved(park.code)
                } label: {
                    Label(isSaved ? "Remove from saved" : "Save this park",
                          systemImage: isSaved ? "bookmark.slash" : "bookmark")
                }
                Button {
                    app.startPack(park.code)
                } label: {
                    Label("Download the offline pack · \(park.pack)", systemImage: "arrow.down.circle")
                }
            }
            .sensoryFeedback(.selection, trigger: isSaved)

            // "Protected area" is the terrain rail's catch-all, not a description of the
            // landscape — it says nothing, so it does not get printed as though it did. A
            // state park carries no tagline at all, so the line is dropped rather than left
            // as an empty gap above the fee row.
            let tagLine = park.source == nil || park.region == "Protected area"
                ? park.tag
                : "\(park.region) · \(park.tag)"
            if !tagLine.isEmpty {
                Text(tagLine)
                    .font(WP.body(13))
                    .lineSpacing(2)
                    .opacity(0.82)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 9)
            }

            HStack(spacing: 10) {
                // `source == nil` meant "one of the six parks written by hand", and those
                // six were the only ones that printed a fee and a temperature here — a
                // hard-coded price and a hard-coded August average, neither dated nor
                // checked, while every other park in the country said nothing. Same
                // treatment for all of them now: the park service's fee when it has
                // answered, and otherwise a line that says where the number will come from.
                Text(factLine)
                    .font(WP.body(11.5)).opacity(0.6).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    app.toggleSaved(park.code)
                } label: {
                    Text(isSaved ? "Saved" : "Save for later")
                        .font(WP.headingUI(13))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .limeControl(shadow: false)
                }
                .buttonStyle(PressStyle(scale: 0.96))
            }
            .padding(.top, 9)
        }
    }
}


/// Nothing matched in the NPS catalogue. The design answers with what the app actually
/// holds, and points at the other catalogue rather than leaving a dead end.
struct NothingByThatName: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nothing by that name.").font(WP.display(22))
            Text("Nothing in the national-park catalogue matches those words. State parks are searched separately.")
                .font(WP.body(13)).lineSpacing(3).opacity(0.75).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                app.discoverShowsState = true
            } label: {
                Text("Try state parks")
                    .font(WP.headingUI(15))
                    .padding(.horizontal, WP.gutter)
                    .frame(minHeight: 44)
                    .glassControl()
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .padding(.top, 14)
        }
        .padding(.top, 26)
    }
}

/// The state-park table: a name and a location for every unit, and nothing else. It is
/// on the phone, so it answers with no network — and the note says plainly that hours,
/// fees and campsites are a link rather than a number.
struct StateParkList: View {
    @Environment(AppState.self) private var app

    /// A row and how far it is from whatever the list is ranked around.
    struct Ranked: Identifiable {
        var row: StateParkRow
        var miles: Int
        var id: String { StateParkList.key(row) }
    }

    /// The table, with the same park listed once.
    ///
    /// The shipped file holds 3,003 rows and several dozen of them are repeats: "Ray
    /// Roberts Lake" and "Ray Roberts Lake State Park" are one park in Denton County,
    /// "Lake Dardanelle State Park" is in there three times. Repeats read as a mistake in
    /// a distance-ordered list — the same park twice, forty-three miles away, twice — and
    /// two rows with one name are also two identical `ForEach` ids, which is a list that
    /// animates wrongly on top of reading wrongly.
    static let table: [StateParkRow] = {
        var seen = Set<String>()
        return Datasets.shared.stateParks.filter { seen.insert(key($0)).inserted }
    }()

    /// A park's identity: its state, and its name with the designation and the
    /// punctuation taken off — "Alfred B. Maclay Gardens State Park" and "Alfred B Maclay
    /// Gardens State Park" are the same gardens.
    static func key(_ row: StateParkRow) -> String {
        var name = row.n.lowercased()
        for suffix in [" state park & recreation area", " state park and recreation area",
                       " state recreation area", " state park"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return row.s + "|" + name.filter { $0.isLetter || $0.isNumber }
    }

    /// Where the phone is. Handed down from the screen, which has asked for it once —
    /// asking again here would put a second prompt on the same view.
    var fix: (lat: Double, lon: Double)?

    private var query: String { app.discoverQuery.trimmingCharacters(in: .whitespaces) }

    /// The shipped table matched the only two ways it can be: a park's own name, or its
    /// state. A city is not in the table at all, which is what `ranked` is for.
    private var named: [StateParkRow] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        let abbreviation = USStates.abbreviation(for: query)
        let hits = Self.table.filter { row in
            if let abbreviation, row.s == abbreviation { return true }
            return row.n.lowercased().contains(q)
        }
        return Array(hits.prefix(40))
    }

    /// The point the table is ranked around: the city that was typed, or — with the field
    /// empty — wherever the phone is.
    private var anchor: (label: String, lat: Double, lon: Double)? {
        if query.isEmpty {
            guard let fix else { return nil }
            return ("you", fix.lat, fix.lon)
        }
        guard let place = app.placeAnchor.anchor else { return nil }
        return (place.label, place.lat, place.lon)
    }

    /// The table by distance from that point, nearest first.
    ///
    /// A city keeps what is within a couple of hours of it; "near me" keeps the forty
    /// nearest at whatever distance, because in Nevada the closest one is a long way off
    /// and is still the answer to the question.
    private var ranked: [Ranked] {
        guard let anchor else { return [] }
        let skip = Set(named.map { Self.key($0) })
        let point = (lat: anchor.lat, lon: anchor.lon)
        var out = Self.table
            .filter { !skip.contains(Self.key($0)) }
            .map { (row: $0, miles: Geo.haversine(point, ($0.lat, $0.lon))) }
        out.sort { $0.miles < $1.miles }
        if !query.isEmpty { out = out.filter { $0.miles <= 200 } }
        return out.prefix(40).map { Ranked(row: $0.row, miles: Int($0.miles.rounded())) }
    }

    /// What the live directory found for the same words, minus anything already listed.
    private var liveRows: [CuratedPark] {
        guard !query.isEmpty else { return [] }
        var already = Set(named.map { $0.n.lowercased() })
        already.formUnion(ranked.map { $0.row.n.lowercased() })
        return app.directory.hits.map(\.park)
            .filter { !already.contains($0.full.lowercased()) }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if query.isEmpty {
                nearMe
            } else {
                matching
                aroundPlace
            }

            // The shipped table can only match a park's own name or its state. These are
            // the ones OpenStreetMap found around the place that was typed.
            if !liveRows.isEmpty {
                HStack(spacing: 7) {
                    Circle().fill(WP.accent).frame(width: 6, height: 6)
                    Text("Found around this place".uppercased())
                        .font(WP.body(10)).tracking(1.3)
                        .foregroundStyle(WP.accent800)
                    Rectangle().fill(WP.divider).frame(height: 1)
                    Text("OpenStreetMap")
                        .font(WP.bodyItalic(10.5)).opacity(0.5)
                }
                .padding(.top, 20)
                .padding(.bottom, 12)

                ForEach(liveRows) { park in
                    Button {
                        app.openPark(park.code)
                    } label: {
                        DividedRow(vertical: 13) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(park.name)
                                        .font(WP.rowTitle(17))
                                        .multilineTextAlignment(.leading)
                                    Text("\(park.state.isEmpty ? "—" : park.stateName) · \(park.designationLabel)")
                                        .font(WP.body(12)).opacity(0.6)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WP.accent700)
                            }
                        }
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            } else if case .searching = app.directory.phase {
                Text("Asking OpenStreetMap about \u{201C}\(app.discoverQuery)\u{201D}\u{2026}")
                    .font(WP.bodyItalic(11.5)).opacity(0.55).padding(.top, 18)
            }

            Text("Opening one gives you its photograph, today's weather, and what is around it. Fees, hours and campsites come from the park itself.")
                .font(WP.body(11.5)).lineSpacing(3).opacity(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    // MARK: The sections

    /// An empty field is a question about here: every state park in the country, the
    /// nearest first, with how far away each one is.
    @ViewBuilder
    private var nearMe: some View {
        if fix != nil {
            SectionRule(dot: WP.live, tint: Color(oklch: 0.40, 0.10, 150),
                        title: "Near me", tail: "nearest first")
            cards(ranked)
        } else {
            SectionRule(dot: WP.live, tint: Color(oklch: 0.40, 0.10, 150),
                        title: "State parks", tail: "\(Self.table.count) units")
            VStack(spacing: 20) {
                ForEach(Array(Self.table.prefix(40)), id: \.self) { row in
                    DiscoverCard(park: CuratedPark(stateRow: row)).liftOnScroll()
                }
            }
            .padding(.top, 4)

            Text("These are not in distance order: this iPhone has not given a location. Allow it and the nearest come first.")
                .font(WP.bodyItalic(11.5)).lineSpacing(3).opacity(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    /// The rows whose own name or state matches the words.
    @ViewBuilder
    private var matching: some View {
        if !named.isEmpty {
            SectionRule(dot: WP.live, tint: Color(oklch: 0.40, 0.10, 150),
                        title: "Matching \u{201C}\(query)\u{201D}",
                        tail: named.count == 1 ? "1 unit" : "\(named.count) units")
            cards(named.map { Ranked(row: $0, miles: 0) }, showMiles: false)
        }
    }

    /// The rows around the place that was typed. This is the city half: the table holds
    /// no city, so the words are put on the map first and the table ranked around that.
    @ViewBuilder
    private var aroundPlace: some View {
        if let anchor, !ranked.isEmpty {
            SectionRule(dot: WP.accent, tint: WP.accent800,
                        title: "Around \(anchor.label)", tail: "within 200 miles")
                .padding(.top, named.isEmpty ? 0 : 20)
            cards(ranked)
        } else if app.placeAnchor.isLocating {
            Text("Finding \u{201C}\(query)\u{201D} on the map\u{2026}")
                .font(WP.bodyItalic(11.5)).opacity(0.55)
                .padding(.top, named.isEmpty ? 0 : 16)
        }
    }

    private func cards(_ rows: [Ranked], showMiles: Bool = true) -> some View {
        VStack(spacing: 20) {
            ForEach(rows) { entry in
                DiscoverCard(park: CuratedPark(stateRow: entry.row),
                             miles: showMiles ? entry.miles : nil)
                    .liftOnScroll()
            }
        }
        .padding(.top, 4)
    }
}

/// The ruled heading over a section: a coloured dot, the name, a hairline, and what the
/// section is counting.
private struct SectionRule: View {
    var dot: Color
    var tint: Color
    var title: String
    var tail: String

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(WP.body(10)).tracking(1.3)
                .foregroundStyle(tint)
                .lineLimit(1)
            Rectangle().fill(WP.divider).frame(height: 1)
            Text(tail)
                .font(WP.bodyItalic(10.5)).opacity(0.5)
                .lineLimit(1)
        }
        .padding(.bottom, 12)
    }
}

/// A monochrome map with the park at its centre — the same desaturated basemap the
/// trip screen draws, so it belongs to the Classical palette. The pin is the one colour on
/// it, and sits at the centre because the region is centred on the park.
struct PinnedMap: View {
    var lat: Double
    var lon: Double

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    }

    /// A larger pin on the full-bleed card, a small one on a thumbnail.
    var pinSize: CGFloat = 22

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [])
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .saturation(0)
            .contrast(1.04)
            .overlay {
                // The one colour on the plate, at the centre because the region is.
                Image(systemName: "mappin")
                    .font(.system(size: pinSize, weight: .semibold))
                    .foregroundStyle(WP.accent)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
            }
            .overlay(alignment: .bottom) {
                // The basemap is light, so white type on it needs a floor to read against —
                // the same job the scrim does on a photograph.
                LinearGradient(
                    colors: [Color(hex: 0x161008, opacity: 0.60), .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: 96)
            }
            .allowsHitTesting(false)
    }
}


/// The suggestion drop-down under the search field.
///
/// Deliberately small: a glyph for what kind of thing it is, the name, and where it is.
/// Picking one is a search, so the rows read as actions rather than as results.
struct SuggestionList: View {
    var items: [SearchSuggestions.Suggestion]
    var onPick: (SearchSuggestions.Suggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { index, item in
                Button { onPick(item) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.kind.glyph)
                            .font(.system(size: 13))
                            .foregroundStyle(WP.accent700)
                            .frame(width: 18)
                        Text(item.title)
                            .font(WP.body(15))
                            .foregroundStyle(WP.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.subtitle)
                            .font(WP.body(11.5))
                            .opacity(0.55)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.995))

                if index < min(items.count, 8) - 1 { Hairline() }
            }
        }
        .liquidGlass(.pill, radius: 18)
        .shadow(color: Color(hex: 0x181008, opacity: 0.13), radius: 12, y: 7)
        .transition(.opacity.combined(with: .offset(y: -6)))
        .animation(Motion.panel, value: items)
    }
}

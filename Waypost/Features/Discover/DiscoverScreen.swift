import SwiftUI

/// Discover — the catalogue, one park at a time, each carrying its own colour.
struct DiscoverScreen: View {
    @Environment(AppState.self) private var app
    @FocusState private var searchFocused: Bool

    private let chips: [(id: String, label: String)] = [
        ("all", "Everything"), ("Desert", "Desert"), ("Alpine", "Alpine"),
        ("Coast", "Coast"), ("Geothermal", "Geothermal"), ("quiet", "Quieter"),
    ]

    /// The eight parks that ship with the app, filtered the way they always were.
    private var curated: [CuratedPark] {
        var list = app.library.orderedParks
        if app.discoverChip == "quiet" {
            list = list.filter { $0.crowd.contains("Quiet") || $0.crowd.contains("Moderate") }
        } else if app.discoverChip != "all" {
            list = list.filter { $0.region == app.discoverChip }
        }
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
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
            ScreenHeader {
                Text("Sixty-three parks, one at a time").kickerStyle()
                Text("Discover").font(WP.displayBold(44)).tracking(-0.4).padding(.top, 2).padding(.bottom, 10)

                // Two catalogues with different guarantees: the NPS registry, and the
                // state-park table that ships on the phone.
                SegmentedTrough(
                    options: [(false, "National"), (true, "State")],
                    selection: Binding(get: { app.discoverShowsState },
                                       set: { app.discoverShowsState = $0 })
                )
                .padding(.bottom, 10)

                TextField(app.discoverShowsState ? "State park or state…" : "Park or state…",
                          text: $app.discoverQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(WP.body(16))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .liquidGlass(.pill, radius: 999)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { app.suggestions.clear() }

                // What you might mean, while you are still typing it. Two letters is
                // enough — "te" offers Tennessee and Texas before any search has run.
                if searchFocused, !app.suggestions.items.isEmpty {
                    SuggestionList(items: app.suggestions.items) { suggestion in
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
                                Text(chip.label)
                                    .font(WP.body(12.5))
                                    .padding(.horizontal, 15)
                                    .frame(minHeight: 34)
                                    .modifier(SelectedControl(active: active))
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
                        StateParkList()
                    } else {
                        // What is actually within reach today, before the catalogue.
                        NearbyCard()

                        Text(note).font(WP.bodyItalic(12)).opacity(0.6)

                        ForEach(results) { park in
                            DiscoverCard(park: park).liftOnScroll()
                        }

                        if results.isEmpty { NothingByThatName() }
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
    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    var park: CuratedPark

    private var isSaved: Bool { app.saved.contains(park.code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.openPark(park.code)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    ParkImage(park: park)

                    VStack(alignment: .leading, spacing: 2) {
                        // State, then what kind of unit it is. The designation is the
                        // thing that tells a national park from a state park from a
                        // wildlife area, so it goes here rather than in a subtitle.
                        Text([park.state, park.designationLabel].filter { !$0.isEmpty }
                                .joined(separator: " · ").uppercased())
                            .font(WP.body(9)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.88))
                        Text(park.name)
                            .font(WP.display(28))
                            .foregroundStyle(.white)
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
                .zoomSource("park:" + park.code, in: zoom)
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
            // landscape — it says nothing, so it does not get printed as though it did.
            Text(park.source == nil || park.region == "Protected area"
                 ? park.tag
                 : "\(park.region) · \(park.tag)")
                .font(WP.body(13))
                .lineSpacing(2)
                .opacity(0.82)
                .multilineTextAlignment(.leading)
                .padding(.top, 9)

            HStack(spacing: 10) {
                // A live record publishes neither a fee nor a temperature; saying so is
                // the whole point, and "0° in August" is the failure this app refuses.
                Text(park.wx.isPublished || park.source == nil
                     ? "\(park.fee) · \(park.wx.hi)° in August"
                     : park.fee)
                    .font(WP.body(11.5)).opacity(0.6).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    app.toggleSaved(park.code)
                } label: {
                    Text(isSaved ? "Saved" : "Save")
                        .font(WP.headingUI(13))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .glassControl(shadow: false)
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
                    .padding(.horizontal, 20)
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

    /// What the live directory found for the same words, minus anything the shipped
    /// table already lists.
    private var liveRows: [CuratedPark] {
        guard !app.discoverQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let already = Set(rows.map { $0.n.lowercased() })
        return app.directory.hits.map(\.park)
            .filter { !already.contains($0.full.lowercased()) }
            .prefix(30)
            .map { $0 }
    }

    private var rows: [StateParkRow] {
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let all = Datasets.shared.stateParks
        guard !q.isEmpty else { return Array(all.prefix(40)) }
        let abbreviation = USStates.abbreviation(for: q)
        return all.filter { row in
            if let abbreviation, row.s == abbreviation { return true }
            return row.n.lowercased().contains(q)
        }
        .prefix(40)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(WP.live).frame(width: 6, height: 6)
                Text("State parks".uppercased())
                    .font(WP.body(10)).tracking(1.3)
                    .foregroundStyle(Color(oklch: 0.40, 0.10, 150))
                Rectangle().fill(WP.divider).frame(height: 1)
                Text("470 units")
                    .font(WP.bodyItalic(10.5)).opacity(0.5)
            }
            .padding(.bottom, 12)

            ForEach(rows, id: \.n) { row in
                Button {
                    app.show("\(row.n) — a name and a location is all any nationwide source publishes")
                } label: {
                    DividedRow(vertical: 13) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.n.replacingOccurrences(of: " State Park", with: ""))
                                    .font(WP.rowTitle(17))
                                    .multilineTextAlignment(.leading)
                                Text("\(row.s.isEmpty ? "—" : row.s) · state park")
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

            // The shipped table can only match a park's own name or its state, so it has
            // no answer for a city. These are the ones OpenStreetMap found around the
            // place that was typed — and unlike the table's rows, they open.
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
                                    Text("\(park.state.isEmpty ? "—" : park.state) · \(park.designationLabel)")
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

            Text("ParkHop holds a name and a location for every state-park unit, and nothing else. Hours, fees and campsites come from the park's own site — so those are a link, not a number.")
                .font(WP.body(11.5)).lineSpacing(3).opacity(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
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

import SwiftUI

/// Discover — the catalogue, one park at a time, each carrying its own colour.
struct DiscoverScreen: View {
    @Environment(AppState.self) private var app

    private let chips: [(id: String, label: String)] = [
        ("all", "Everything"), ("Desert", "Desert"), ("Alpine", "Alpine"),
        ("Coast", "Coast"), ("Geothermal", "Geothermal"), ("quiet", "Quieter"),
    ]

    private var results: [CuratedPark] {
        var list = app.library.orderedParks
        if app.discoverChip == "quiet" {
            list = list.filter { $0.crowd.contains("Quiet") || $0.crowd.contains("Moderate") }
        } else if app.discoverChip != "all" {
            list = list.filter { $0.region == app.discoverChip }
        }
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { ($0.name + " " + $0.state + " " + $0.tag).lowercased().contains(q) }
        }
        return list
    }

    private var note: String {
        let count = results.count
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces)
        let tail: String
        if !q.isEmpty { tail = "matching “\(q)”" }
        else if app.discoverChip == "all" { tail = "all of them, alphabetical by nothing in particular" }
        else { tail = app.discoverChip.lowercased() + " country" }
        return "\(count) \(count == 1 ? "park" : "parks") · \(tail)"
    }

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                Text("Sixty-three parks, one at a time").kickerStyle()
                Text("Discover").font(WP.display(31)).padding(.top, 4).padding(.bottom, 10)

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
                        Text("\(park.state) · \(park.region)".uppercased())
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

            Text(park.tag)
                .font(WP.body(13))
                .lineSpacing(2)
                .opacity(0.82)
                .multilineTextAlignment(.leading)
                .padding(.top, 9)

            HStack(spacing: 10) {
                Text("\(park.fee) · \(park.wx.hi)° in August")
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
            Text("Sixty-three parks and 470 units are in the catalogue; this build carries eight of them. State parks are searched separately — and on this phone.")
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
                Text("On this phone".uppercased())
                    .font(WP.body(10)).tracking(1.3)
                    .foregroundStyle(Color(oklch: 0.40, 0.10, 150))
                Rectangle().fill(WP.divider).frame(height: 1)
                Text("470 units · no network")
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

            Text("ParkHop holds a name and a location for every state-park unit, and nothing else. Hours, fees and campsites come from the park's own site — so those are a link, not a number.")
                .font(WP.body(11.5)).lineSpacing(3).opacity(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }
}

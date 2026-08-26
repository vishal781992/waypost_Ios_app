import SwiftUI

/// The profile as a front page.
///
/// It was a scroll: a heading, a monogram beside a line of counts, the atlas as a card, a
/// settings row, two paragraphs of small print. Everything on it was true and none of it
/// was the point. The point is the country and how much of it has been stood in — so the
/// country is the screen now, in black and white under a black tint, and everything else
/// rests on a sheet that rises off the bottom of it.
///
/// The map is still a door. Tapping it opens the atlas exactly as the card it replaced did.
struct ProfileScreen: View {
    @Environment(AppState.self) private var app

    @State private var adding = false
    @State private var editing = false
    @State private var loggingOut = false
    @State private var parkQuery = ""
    @FocusState private var parkFieldFocused: Bool

    /// How much of the display the sheet takes.
    ///
    /// A fraction rather than the height of whatever is in it: the map above has to be laid
    /// out against a number that does not move when a park is added or a name is typed, or
    /// the country would slide up the screen every time the sheet grew a line.
    private func sheetHeight(_ available: CGFloat) -> CGFloat {
        max(430, available * 0.56)
    }

    var body: some View {
        GeometryReader { proxy in
            let sheetTall = sheetHeight(proxy.size.height)

            ZStack(alignment: .bottom) {
                AtlasBackdrop(band: proxy.size.height - sheetTall)
                    .ignoresSafeArea()

                sheet.frame(height: sheetTall)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $editing) {
            ProfileIdentityEditor()
                .environment(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Log out?", isPresented: $loggingOut) {
            Button("Cancel", role: .cancel) {}
            Button("Log out", role: .destructive) { StubAuthService.shared.signOut() }
        } message: {
            Text("You come back to the opening screen. Nothing on this phone is deleted — your trips, stamps and saved parks are all still here when you come back in.")
        }
    }

    // MARK: The sheet

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(WP.text.opacity(0.18))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    identity
                    rows.padding(.top, 22)

                    if adding { addField.padding(.top, 12) }

                    logOut.padding(.top, 14)
                    versionBadge.padding(.top, 16)

                    Text("Every panel says where its rows came from. Where a source has not answered, the panel says so rather than filling the gap. Always confirm campsites, permits and closures with the park before you travel — ParkHop is a planner, not a promise.")
                        .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, WP.gutter)
                // Clear of the floating tab bar, which this screen sits under.
                .padding(.bottom, WP.tabBarHeight + 26)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 30,
                                   style: .continuous)
                .fill(WP.onInk)
                .shadow(color: Color(hex: 0x000000, opacity: 0.34), radius: 22, y: -10)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Who this is

    /// The circle, the name, and what the phone is holding.
    ///
    /// The circle straddles the sheet's top edge — which is why it is drawn with a negative
    /// top inset rather than inside the flow: half of it belongs to the map. Both it and the
    /// name open the same editor, because a reader who wants to change one of them has no
    /// reason to know they are two settings.
    private var identity: some View {
        Button {
            editing = true
            Haptics.tap()
        } label: {
            VStack(spacing: 9) {
                avatar.padding(.top, -46)

                if let name = app.profileName, !name.isEmpty {
                    Text(name)
                        .font(WP.display(31))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    // Never a name nobody entered. An invitation instead, which stops being
                    // one the moment there is something to show.
                    Text("Add your name")
                        .font(WP.display(31)).opacity(0.45)
                }

                Text(holdings)
                    .font(WP.body(12)).opacity(0.6)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .foregroundStyle(WP.text)
        .accessibilityLabel("Your name and emoji. Opens the editor.")
    }

    private var avatar: some View {
        Group {
            if let emoji = app.profileEmoji {
                Text(emoji).font(.system(size: 44))
            } else {
                Text(monogram).font(WP.heading(34)).foregroundStyle(WP.accent800)
            }
        }
        .frame(width: 96, height: 96)
        .background(WP.accent100, in: Circle())
        // The ring is the sheet's own colour, so the circle reads as cut out of the sheet
        // rather than laid on top of it.
        .overlay { Circle().stroke(WP.onInk, lineWidth: 4) }
        .shadow(color: Color(hex: 0x000000, opacity: 0.26), radius: 12, y: 5)
    }

    /// Initials of the parks on the rail, or a compass rose before there are any. Derived,
    /// because until somebody picks an emoji there is nothing else to put in the circle.
    private var monogram: String {
        let initials = app.visitRail.prefix(2).compactMap { $0.park.name.first }
        return initials.isEmpty ? "◆" : String(initials).uppercased()
    }

    /// What the phone is actually holding, counted rather than claimed.
    private var holdings: String {
        let rail = app.visitRail
        let states = Atlas.states(Atlas.parks(rail))
        let filled = states.filter(\.isFilled).count
        let trips = app.myTrips.count
        var parts = ["\(rail.count) of \(NationalParks.all.count) parks",
                     "\(filled) of \(states.count) states"]
        if trips > 0 { parts.append("\(trips) \(trips == 1 ? "trip" : "trips")") }
        return parts.joined(separator: " · ")
    }

    // MARK: The rows

    private var rows: some View {
        Grouped {
            row("Preferences", "Notifications, travel, calendar, downloads") {
                app.push(.preferences)
            }
            Hairline()
            row("Add a park you have visited", adding ? "Searching" : "By hand, if we missed one") {
                withAnimation(.snappy(duration: 0.2)) { adding.toggle() }
                if !adding { parkQuery = "" }
            }
        }
    }

    private func row(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(WP.body(14))
                Spacer(minLength: 0)
                Text(detail).font(WP.body(11.5)).opacity(0.55).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WP.accent700)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.995))
        .foregroundStyle(WP.text)
    }

    /// Low, quiet, and behind a question — the same shape the erase button in Preferences
    /// takes, at a lower weight because this one deletes nothing.
    private var logOut: some View {
        Button(role: .destructive) { loggingOut = true } label: {
            Text("Log out")
                .font(WP.headingUI(15))
                .foregroundStyle(WP.danger)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay {
                    Capsule().stroke(WP.danger.opacity(0.38), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    /// Which build this is, for a tester writing it into a bug report — selectable so it
    /// can be copied rather than transcribed.
    private var versionBadge: some View {
        Text(AppVersion.full)
            .font(WP.mono(11))
            .tracking(0.6)
            .foregroundStyle(WP.accent800)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(WP.accent100, in: Capsule())
            .textSelection(.enabled)
            .accessibilityLabel("Version \(AppVersion.full)")
    }

    // MARK: Adding a park by hand

    /// The search that appears under the rows once the add row is tapped.
    private var addField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold)).opacity(0.45)
                TextField("Search a national park", text: $parkQuery)
                    .font(WP.body(15))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($parkFieldFocused)
                Button("Done") {
                    withAnimation(.snappy(duration: 0.2)) { adding = false }
                    parkQuery = ""
                }
                .font(WP.headingUI(14))
                .foregroundStyle(WP.accent700)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .searchFieldSurface(focus: $parkFieldFocused)

            if parkQuery.trimmingCharacters(in: .whitespaces).count == 1 {
                Text("One more character and the parks appear.")
                    .font(WP.bodyItalic(11.5)).opacity(0.55).padding(.top, 8)
            } else if !parkMatches.isEmpty {
                Grouped {
                    ForEach(Array(parkMatches.enumerated()), id: \.element.code) { index, park in
                        let already = app.visitRail.contains { $0.id == park.code }
                        Button {
                            guard !already else { return }
                            app.addVisit(park.code)
                            parkQuery = ""
                            withAnimation(.snappy(duration: 0.2)) { adding = false }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(park.name).font(WP.body(14)).lineLimit(1)
                                    Text([park.stateName, park.designationLabel]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(WP.body(11)).opacity(0.55)
                                }
                                Spacer(minLength: 0)
                                if already {
                                    Text("Added")
                                        .font(WP.body(11)).tracking(1.1)
                                        .foregroundStyle(WP.accent700).opacity(0.7)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.995))
                        .disabled(already)
                        if index < parkMatches.count - 1 { Hairline() }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// The bundled sixty-two first — instant and offline — then anything the live
    /// directory has found for the same words, so a unit that is not on the phone can
    /// still be added.
    private var parkMatches: [CuratedPark] {
        let q = parkQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }

        var out = NationalParks.allCurated
            .filter { $0.name.lowercased().contains(q) || $0.state.lowercased().contains(q) }
        var seen = Set(out.map { $0.name.lowercased() })
        for park in app.directory.hits.map(\.park)
        where seen.insert(park.name.lowercased()).inserted {
            out.append(park)
        }
        return Array(out.prefix(6))
    }
}

/// The grouped-inset card iOS uses for settings, in the Classical palette.
struct Grouped<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(WP.neutral100.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(WP.divider, lineWidth: 1)
            }
    }
}

/// A hex field that repaints the app as it is typed.
///
/// Here while the colour is being decided, not forever — which is why it says so on the
/// label above it rather than pretending to be a preference.
struct PageTintRow: View {
    @Environment(AppState.self) private var app
    @State private var typed = PageTint.shared.hex
    @FocusState private var focused: Bool

    private var parsed: Color? { PageTint.colour(from: typed) }

    var body: some View {
        Grouped {
            HStack(spacing: 12) {
                // The colour as it will actually be, not as a name for it.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(parsed ?? PageTint.shared.colour)
                    .frame(width: 42, height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(WP.divider, lineWidth: 1))

                HStack(spacing: 2) {
                    Text("#").font(WP.mono(15)).opacity(0.4)
                    TextField(PageTint.defaultHex, text: $typed)
                        .textFieldStyle(.plain)
                        .font(WP.mono(15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($focused)
                        .submitLabel(.done)
                        .onChange(of: typed) { _, new in
                            // Applied the moment it is valid, so the colour can be judged
                            // against the photographs rather than against a swatch.
                            if PageTint.colour(from: new) != nil {
                                PageTint.shared.hex = new
                            }
                        }
                }

                Spacer(minLength: 0)

                if !PageTint.shared.isDefault {
                    Button {
                        PageTint.shared.reset()
                        typed = PageTint.defaultHex
                        focused = false
                        app.show("Page colour back to #\(PageTint.defaultHex)")
                    } label: {
                        Text("Reset")
                            .font(WP.headingUI(12.5))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .glassControl(shadow: false)
                    }
                    .buttonStyle(PressStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Hairline()

            Text(parsed == nil
                 ? "Three or six hex digits — that is not one, so the page is unchanged."
                 : "Every screen takes this colour as you type. It survives a relaunch, and Reset puts it back.")
                .font(WP.bodyItalic(11.5)).opacity(0.6).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
        }
    }
}

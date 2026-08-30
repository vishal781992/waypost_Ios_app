import Combine
import SwiftUI
import UIKit

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

    /// How much of the display the keyboard is covering.
    ///
    /// Read from the system rather than from a safe-area inset, because this screen ignores
    /// the safe area outright — that is what holds the map and the sheet to one set of
    /// numbers instead of two, and it switched off SwiftUI's own keyboard avoidance along
    /// with everything else. `.ignoresSafeArea()` with no argument ignores *every* region,
    /// and `.keyboard` is one of them. So the search field was drawn where it had always
    /// been drawn, and the keyboard came up over the top of it.
    ///
    /// iPhone only — `TARGETED_DEVICE_FAMILY` is 1 — so there is no floating or split
    /// keyboard to reason about and the frame's height is the whole answer.
    @State private var keyboard: CGFloat = 0

    /// Where the search field is scrolled to when it takes focus.
    private static let searchAnchor = "profile.search"

    /// How much of the display the sheet takes.
    ///
    /// A fraction rather than the height of whatever is in it: the map above has to be laid
    /// out against a number that does not move when a park is added or a name is typed, or
    /// the country would slide up the screen every time the sheet grew a line.
    private func sheetHeight(_ available: CGFloat) -> CGFloat {
        max(430, available * 0.56)
    }

    var body: some View {
        // The reader ignores the safe area, not the stack inside it — which is the whole
        // fix for the pale band that used to sit between the map and the sheet. A
        // `GeometryReader` reports the size *inside* the safe area; with the stack ignoring
        // it instead, the map was sized against 785 points while the sheet was placed
        // against 844, and the difference showed as a gap neither of them covered.
        GeometryReader { proxy in
            let full = proxy.size
            let sheetTall = sheetHeight(full.height)

            ZStack(alignment: .top) {
                // `underlap` extra, so the ground runs on behind the sheet's rounded
                // corners instead of showing the page through them.
                //
                // Sized against the *resting* sheet, never the raised one: growing the
                // sheet into this number would shrink the card to a strip and grow it back
                // again on dismissal, which reads as the pass being thrown away.
                YearPassBackdrop(
                    size: CGSize(width: full.width,
                                 height: full.height - sheetTall + YearPassBackdrop.underlap),
                    onAtlas: { app.push(.atlas); Haptics.tap() }
                )

                // Typing raises the sheet over the map rather than resizing anything under
                // it: a search with a keyboard under it has about a hundred and thirty
                // points to live in at the resting height, which is the field and nothing
                // it finds.
                sheet(clearing: proxy.safeAreaInsets.bottom)
                    .frame(height: parkFieldFocused ? full.height : sheetTall)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .animation(Motion.panel, value: parkFieldFocused)
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification)) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            keyboard = frame?.height ?? 0
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard = 0
        }
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

    /// - Parameter clearing: the home indicator's own inset. The sheet runs to the real
    ///   bottom of the display now, so its content has to clear both the floating tab bar
    ///   and the strip iOS keeps under it — and that strip is the phone's number, not one
    ///   to write down here.
    private func sheet(clearing bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        // Room for the half of the circle that belongs to the sheet. The circle
                        // itself is an overlay, not a row: a scroll view clips its own content,
                        // so drawn in here its top half was cut clean off.
                        identity.padding(.top, 56)
                        rows.padding(.top, 22)

                        if adding { addField.padding(.top, 12).id(Self.searchAnchor) }

                        logOut.padding(.top, 14)
                        versionBadge.padding(.top, 16)
                        // The paragraph that used to close this sheet said two things. The
                        // first — that every panel names its sources — is a claim the panels
                        // make themselves, on every screen, which is the only place it means
                        // anything. The second is the travel warning, and it belongs on the
                        // settings screen with the rest of the small print rather than under
                        // somebody's own name.
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, WP.gutter)
                    // Clear of the floating tab bar, which this screen sits under — or, while
                    // the keyboard is up, clear of that instead. The tab bar is behind it and
                    // no longer the thing to miss, and this is also the slack the scroll needs:
                    // a scroll view will not run past the end of its content, so without a
                    // keyboard's worth of room below the field there is nowhere for the field
                    // to travel to.
                    .padding(.bottom, keyboard > 0
                             ? keyboard + 24
                             : WP.tabBarHeight + 26 + bottomInset)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                // Reading down puts the keyboard away, which is what every list with a search
                // on it does.
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: parkFieldFocused) { _, focused in
                    guard focused else { return }
                    withAnimation(Motion.panel) {
                        scroller.scrollTo(Self.searchAnchor, anchor: .top)
                    }
                }
            }
        }
        // Half on the sheet and half on the map, which is the whole idea — so it hangs off
        // the top edge rather than sitting inside anything that could clip it.
        .overlay(alignment: .top) {
            avatarButton
                .offset(y: -48)
                // The circle straddles the sheet's top edge. Raised, that edge is the top
                // of the display and half of it would be off the screen — and a face is
                // not what somebody typing a park's name is looking at.
                .opacity(parkFieldFocused ? 0 : 1)
                .animation(Motion.panel, value: parkFieldFocused)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 30,
                                   style: .continuous)
                .fill(WP.onInk)
                .shadow(color: Color(hex: 0x000000, opacity: 0.34), radius: 22, y: -10)
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

    /// The circle, and the tap that opens the editor from it.
    private var avatarButton: some View {
        Button {
            editing = true
            Haptics.tap()
        } label: {
            avatar
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel("Your emoji. Opens the editor.")
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
                if !adding {
                    parkQuery = ""
                    parkFieldFocused = false
                }
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
                    parkFieldFocused = false
                    withAnimation(.snappy(duration: 0.2)) { adding = false }
                    parkQuery = ""
                }
                .font(WP.headingUI(14))
                .foregroundStyle(WP.accent700)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .searchFieldSurface(focus: $parkFieldFocused)
            .task {
                // Tapping the row is asking to type. Set in a `task` rather than beside
                // the insertion: focus does not land on a view that is not on screen yet.
                parkFieldFocused = true
            }

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
                            parkFieldFocused = false
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

import SwiftUI

/// Profile — notifications, offline packs, travel defaults, and what the app is holding.
struct ProfileScreen: View {
    @Environment(AppState.self) private var app

    @State private var adding = false
    @State private var parkQuery = ""
    @FocusState private var parkFieldFocused: Bool


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

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        // The version moved to the badge on the right, so it is not stated
                        // twice on one header.
                        Text("ParkHop · a field planner").kickerStyle()
                        Text("Profile").font(WP.displayBold(44)).tracking(-0.4).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    versionBadge
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    identity

                    visited

                    // Everything that was here is one push away now. A profile is you and
                    // where you have been; the machinery is a settings screen, and a
                    // settings screen is where somebody goes looking for it.
                    sectionLabel("Settings")
                    Grouped {
                        Button { app.push(.preferences) } label: {
                            HStack(spacing: 10) {
                                Text("Preferences").font(WP.body(14))
                                Spacer(minLength: 0)
                                Text("Notifications, travel, downloads, connections")
                                    .font(WP.body(11.5)).opacity(0.55).lineLimit(1)
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
                    .padding(.top, 4)

                    Text("Every panel says where its rows came from. Where a source has not answered, the panel says so rather than filling the gap.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3)
                        .padding(.top, 22)

                    Text("Always confirm campsites, permits and closures with the park before you travel. ParkHop is a planner, not a promise.")
                        .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 18)
                .padding(.bottom, WP.rootScrollBottom)
            }
            .tracksTabBarMinimize()
            .scrollIndicators(.hidden)
            .captureScrollPosition()
        }
    }

    // MARK: Parks visited

    /// Everywhere they have been, as one picture rather than a rail of tiles.
    ///
    /// The rail showed the last few parks and hid the rest behind a sideways scroll nobody
    /// reaches the end of — and it said nothing at all about the sixty-two-park register
    /// those visits are a share of. `AtlasCard` is the whole country at a glance and a door
    /// to the screen where it can be read properly; the control to add a park by hand comes
    /// out of the rail and sits in this heading, which is the only place left with room for
    /// it and the place a heading's control belongs.
    private var visited: some View {
        let visits = app.visitRail
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Parks visited with ParkHop".uppercased())
                    .font(WP.body(11)).tracking(1.3).opacity(0.55)
                Rectangle().fill(WP.divider).frame(height: 1)
                Text("\(visits.count) \(visits.count == 1 ? "park" : "parks")")
                    .font(WP.display(17))
                    .foregroundStyle(WP.accent700)
                addControl
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            AtlasCard()

            if adding {
                addField.padding(.top, 12)
            }
        }
    }

    /// Add a park by hand, at the top right of its own heading.
    ///
    /// It was a dashed tile at the far end of the rail, which a deck or a map has no
    /// equivalent of — there is no end to flick to. Here it is where a section's control
    /// goes everywhere else in the app, and it says what it does rather than what it is.
    private var addControl: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { adding.toggle() }
            if !adding { parkQuery = "" }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: adding ? "xmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(adding ? "Close" : "Add").font(WP.headingUI(12.5))
            }
            .foregroundStyle(WP.accent700)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(WP.accent100, in: Capsule())
            .overlay(Capsule().stroke(WP.accent.opacity(0.34), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(adding ? "Close the park search" : "Add a park you have visited")
    }

    /// The search that appears under the rail once the add control is tapped.
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

    /// Initials of the parks on the rail, or a compass rose before there are any. Derived,
    /// because there is no account and therefore no name to show.
    private var monogram: String {
        let initials = app.visitRail.prefix(2).compactMap { $0.park.name.first }
        return initials.isEmpty ? "◆" : String(initials).uppercased()
    }

    /// What the phone is actually holding, counted rather than claimed.
    private var holdings: String {
        let trips = app.myTrips.count
        let parks = app.visitRail.count
        let saved = app.saved.count
        let parts = [
            trips > 0 ? "\(trips) \(trips == 1 ? "trip" : "trips")" : nil,
            parks > 0 ? "\(parks) visited" : nil,
            saved > 0 ? "\(saved) saved" : nil,
        ].compactMap { $0 }
        return parts.isEmpty
            ? "Stored on this iPhone · nothing yet"
            : parts.joined(separator: " · ") + " · stored on this iPhone"
    }

    private var identity: some View {
        HStack(spacing: 13) {
            Text(monogram)
                // 82 from 54, with the initials scaled by the same factor so the monogram
                // keeps its proportions rather than sitting small in a bigger circle.
                .font(WP.heading(32))
                .foregroundStyle(WP.accent800)
                .frame(width: 82, height: 82)
                .background(WP.accent100, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Your parks").font(WP.heading(20))
                // Was "Miriam Halloran · Trips synced by iCloud · 3 devices" on every
                // install — a name nobody entered, and a sync that does not exist. There is
                // no account and nothing leaves the phone, so this counts what is actually
                // held and says where it is held.
                Text(holdings).font(WP.body(12)).opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(WP.body(10)).tracking(1.4).opacity(0.5)
            .padding(.top, 22).padding(.bottom, 8)
    }

}

/// The grouped-inset card iOS uses for settings, in the Classical palette.
struct Grouped<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
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

import SwiftUI

/// Profile — notifications, offline packs, travel defaults, and what the app is holding.
struct ProfileScreen: View {
    @Environment(AppState.self) private var app


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

                    sectionLabel("Tell me when")
                    Grouped {
                        toggleRow("Permit windows drop",
                                  "Timed entry, lotteries, next-day releases",
                                  isOn: app.notifyPermits) {
                            app.notifyPermits.toggle()
                            app.show(app.notifyPermits ? "Notifications on" : "Notifications off")
                            app.persist()
                        }
                        Hairline()
                        toggleRow("Park alerts on my route",
                                  "Closures, fire, flash flood, road work",
                                  isOn: app.notifyAlerts) {
                            app.notifyAlerts.toggle()
                            app.persist()
                        }
                        Hairline()
                        toggleRow("Live Activity on drive legs",
                                  "Arrival time and next charge on the lock screen",
                                  isOn: app.notifyLive) {
                            app.notifyLive.toggle()
                            app.persist()
                        }
                    }

                    sectionLabel("Park packs for no signal")
                    Grouped {
                        ForEach(Array(app.library.orderedParks.enumerated()), id: \.element.code) { index, park in
                            packRow(park)
                            if index < app.library.orderedParks.count - 1 { Hairline() }
                        }

                    }

                    sectionLabel("Page colour · while testing")
                    PageTintRow()

                    sectionLabel("Travel defaults")
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vehicle").font(WP.body(12)).opacity(0.65)
                            SegmentedTrough(
                                options: [(false, "Gasoline"), (true, "Electric")],
                                selection: Binding(get: { app.vehicleIsElectric },
                                                   set: { app.vehicleIsElectric = $0; app.persist() })
                            )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Units").font(WP.body(12)).opacity(0.65)
                            SegmentedTrough(
                                options: [(false, "Miles · °F"), (true, "Km · °C")],
                                selection: Binding(get: { app.unitsMetric },
                                                   set: { app.unitsMetric = $0; app.persist() })
                            )
                        }
                    }

                    sectionLabel("Data & offline")
                    Grouped {
                        HStack(spacing: 10) {
                            Circle().fill(WP.live).frame(width: 7, height: 7)
                            Text("Park records").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text("NPS · Open-Meteo · Recreation.gov")
                                .font(WP.body(11.5)).opacity(0.55).lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        Hairline()
                        HStack {
                            Text("Field journal").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text("\(app.journalCount) photographs").font(WP.body(11.5)).opacity(0.55)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        Hairline()
                        HStack {
                            Text("Live sources").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text("Re-wiring next pass").font(WP.body(11.5)).opacity(0.55)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                    }

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
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .captureScrollPosition()
        }
    }

    private var identity: some View {
        HStack(spacing: 13) {
            Text("MH")
                // 82 from 54, with the initials scaled by the same factor so the monogram
                // keeps its proportions rather than sitting small in a bigger circle.
                .font(WP.heading(32))
                .foregroundStyle(WP.accent800)
                .frame(width: 82, height: 82)
                .background(WP.accent100, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Miriam Halloran").font(WP.heading(20))
                Text("Trips synced by iCloud · 3 devices").font(WP.body(12)).opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(WP.body(10)).tracking(1.4).opacity(0.5)
            .padding(.top, 22).padding(.bottom, 8)
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(WP.body(14))
                    Text(subtitle).font(WP.body(11.5)).opacity(0.6).lineSpacing(1)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                WPSwitch(isOn: isOn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.995))
    }

    private func packRow(_ park: CuratedPark) -> some View {
        let state = app.packState(park.code)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(park.name).font(WP.body(14))
                Text(park.pack).font(WP.body(11.5)).opacity(0.55)
            }
            Spacer(minLength: 0)
            Button {
                app.startPack(park.code)
            } label: {
                Text(state == .ready ? "On device"
                     : state == .busy ? "\(Int((app.packProgress[park.code] ?? 0) * 100))%"
                     : "Get")
                    .font(WP.headingUI(12.5))
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .glassControl(shadow: false)
            }
            .buttonStyle(PressStyle(scale: 0.95))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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

import SwiftUI

/// Everything the profile used to carry below the fold.
///
/// The profile is a profile again — you, and where you have been. This is the machinery,
/// one push away, where a settings screen is expected to be.
struct PreferencesScreen: View {
    @Environment(AppState.self) private var app
    @State private var erasing = false

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ParkHop · a field planner").kickerStyle()
                        Text("Preferences").font(WP.displayBold(40)).tracking(-0.4).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    GlassDisc(icon: "chevron.left", size: 44) { app.pop() }
                        .accessibilityLabel("Back to Profile")
                        .padding(.top, 2)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
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

                    sectionLabel("Your calendar")
                    Grouped {
                        toggleRow("Check my days for clashes",
                                  calendarAccessLine,
                                  isOn: app.checksCalendar && TripCalendar.shared.access.canRead) {
                            toggleCalendarChecking()
                        }
                        Hairline()
                        HStack {
                            Text("Trips added to the calendar").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text(app.calendarTrips.isEmpty
                                 ? "None yet"
                                 : "\(app.calendarTrips.count) \(app.calendarTrips.count == 1 ? "trip" : "trips")")
                                .font(WP.body(11.5)).opacity(0.55)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                    }

                    Text("A trip is added from its own Days tab, into a calendar of its own called “\(TripCalendar.calendarTitle)” — so the whole trip can be hidden or deleted in one move, and so a trip never counts as a clash with itself. Adding needs only permission to write; looking for clashes is the one that needs permission to read, which is why it has a switch of its own.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3)
                        .padding(.top, 10)

                    sectionLabel("Travel defaults")
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vehicle").font(WP.body(12)).opacity(0.65)
                            SegmentedTrough(
                                options: [(false, "Gasoline"), (true, "Electric")],
                                selection: Binding(get: { app.vehicleIsElectric },
                                                   set: { app.vehicleIsElectric = $0; app.persist() }),
                                haptic: { Haptics.vehicle(isElectric: $0) }
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

                    sectionLabel("On this phone")
                    Grouped {
                        pushRow("Offline packs",
                                ParkPack.shared.isEmpty
                                    ? "Nothing downloaded"
                                    : "\(ParkPack.shared.stored.count) \(ParkPack.shared.stored.count == 1 ? "park" : "parks") · \(ParkPack.shared.totalLabel)") {
                            app.push(.packs)
                        }
                        Hairline()
                        pushRow("Connections", connectionsSummary) { app.push(.connections) }
                        Hairline()
                        HStack {
                            Text("Field journal").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text(app.journalCount == 0
                                 ? "No photographs yet"
                                 : "\(app.journalCount) \(app.journalCount == 1 ? "photograph" : "photographs")")
                                .font(WP.body(11.5)).opacity(0.55)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                    }

                    sectionLabel("Page colour · while testing")
                    PageTintRow()

                    // Low, quiet, and behind a question. Destructive, immediate and with no
                    // undo — so it sits at the foot of the last section rather than
                    // anywhere a thumb rests on the way past.
                    eraseButton.padding(.top, 30)

                    Text("Every panel in the app says where its rows came from. Where a source has not answered, the panel says so rather than filling the gap.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3)
                        .padding(.top, 26)

                    Text("Always confirm campsites, permits and closures with the park before you travel. ParkHop is a planner, not a promise.")
                        .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 6)
                .padding(.bottom, WP.rootScrollBottom)
            }
            .scrollIndicators(.hidden)
        }
        .background(WP.bg)
        .task { Connections.shared.watch() }
        // The permission can be changed in Settings while the app is in the background, so
        // the switch is read off the system each time this screen opens rather than
        // remembered from when it was last set.
        .task { TripCalendar.shared.readAccess() }
    }

    /// What the connections row says without opening it: the shortest true sentence.
    private var connectionsSummary: String {
        let down = Connections.sources.filter {
            if case .failed = Connections.shared.health(of: $0) { return true }
            return false
        }
        if Connections.shared.isOnline == false { return "This phone is offline" }
        if down.isEmpty { return "Nothing has reported a problem" }
        if down.count == 1 { return "\(down[0].name) did not answer" }
        return "\(down.count) sources did not answer"
    }

    // MARK: Erasing

    private var eraseButton: some View {
        Button(role: .destructive) { erasing = true } label: {
            VStack(spacing: 3) {
                Text("Erase everything on this phone")
                    .font(WP.headingUI(15))
                Text("Trips, stamps, saved parks and downloads")
                    .font(WP.body(11.5)).opacity(0.8)
            }
            .foregroundStyle(WP.onInk)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(WP.danger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .alert("Erase everything?", isPresented: $erasing) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) { app.eraseEverything() }
        } message: {
            Text("Every trip you have planned, every stamp you have collected, every park you have saved and every offline pack goes. Nothing here has left this phone, so there is nothing to restore it from. Your vehicle, units and notification switches stay. Trips already added to your calendar stay too — those are in your calendar account rather than on this phone, and “\(TripCalendar.calendarTitle)” deletes the lot in one move.")
        }
    }

    // MARK: The calendar

    /// What the system will currently let the app do, in a sentence.
    ///
    /// Never "on" where the permission is missing: a switch that reads as on while the app
    /// can see nothing is the app claiming to have checked.
    private var calendarAccessLine: String {
        switch TripCalendar.shared.access {
        case .full:
            return app.checksCalendar
                ? "Days you already have something on are marked on the trip"
                : "Allowed — turn this on to mark days that are already spoken for"
        case .writeOnly:
            return "ParkHop may add trips but not read your days. Allow full access to find clashes."
        case .denied:
            return "Calendar access is off. Settings › Privacy & Security › Calendars turns it on."
        case .restricted:
            return "Calendar access is restricted on this phone."
        case .notAsked:
            return "Asks for permission to read your calendar when you turn this on"
        }
    }

    private func toggleCalendarChecking() {
        if app.checksCalendar {
            app.checksCalendar = false
            TripCalendar.shared.invalidate()
            app.persist()
            return
        }
        Task {
            let allowed = await TripCalendar.shared.askToRead()
            app.checksCalendar = allowed
            app.persist()
            if !allowed {
                app.show(TripCalendar.shared.access == .denied
                         ? "Calendar access is off in Settings"
                         : "Calendar access was not given")
            }
        }
    }

    // MARK: Rows

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(WP.body(10)).tracking(1.4).opacity(0.5)
            .padding(.top, 22).padding(.bottom, 8)
    }

    private func pushRow(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(WP.body(14))
                Spacer(minLength: 0)
                Text(detail).font(WP.body(11.5)).opacity(0.55)
                    .lineLimit(1).multilineTextAlignment(.trailing)
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

    /// Transcribed from the profile's own, not redrawn. `WPSwitch` is the design's
    /// switch and the one this row has always used — a hand-rolled capsule here would be
    /// two switches in one app inside a release.
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
}

// MARK: - Offline packs

/// The parks kept on this phone, and what they weigh.
///
/// A manager, not a catalogue. A pack is made where somebody is already looking at the
/// park — the park screen and Discover both offer it — so a list here that also downloaded
/// would be a second place to browse sixty-two parks, and the app already has one.
struct OfflinePacksScreen: View {
    @Environment(AppState.self) private var app
    @State private var removing: ParkPack.Stored?

    private var packs: [ParkPack.Stored] { ParkPack.shared.list }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(packs.isEmpty
                             ? "Nothing downloaded"
                             : "\(packs.count) \(packs.count == 1 ? "park" : "parks") · \(ParkPack.shared.totalLabel)")
                            .kickerStyle()
                        Text("Offline packs").font(WP.displayBold(38)).tracking(-0.4).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    GlassDisc(icon: "chevron.left", size: 44) { app.pop() }
                        .accessibilityLabel("Back to Preferences")
                        .padding(.top, 2)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if packs.isEmpty { empty } else { list }

                    SourceLine("A pack holds what the park service publishes about the park, its photograph and a picture of the ground around it — the three things a park screen cannot draw without a signal. Nothing else is stored, and nothing leaves this phone.",
                               ruled: packs.isEmpty)
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 8)
                .padding(.bottom, WP.rootScrollBottom)
            }
            .scrollIndicators(.hidden)
        }
        .background(WP.bg)
        .task { ParkPack.shared.reload() }
        .alert("Remove this pack?", isPresented: Binding(get: { removing != nil },
                                                         set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) {
                if let pack = removing {
                    let freed = ParkPack.shared.remove(pack.code)
                    app.show("\(pack.name) removed — \(ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file)) back")
                }
                removing = nil
            }
        } message: {
            Text("\(removing?.name ?? "This park") comes off the phone. You can download it again from the park's own screen whenever you have a signal.")
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No parks are on this phone yet.")
                .font(WP.heading(20))
            Text("Open a park and press **Get pack**. What it downloads is the park service's own record, the photograph and a map of the ground around it — enough for the screen to read whole on a road with no bars.")
                .font(WP.body(13)).lineSpacing(3).opacity(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 22)
    }

    private var list: some View {
        Grouped {
            ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                row(pack)
                if index < packs.count - 1 { Hairline() }
            }
        }
    }

    private func row(_ pack: ParkPack.Stored) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.name).font(WP.body(14.5))
                // What is in it and how old it is. A record fetched in April is worth
                // having and worth knowing the age of — that is the difference between an
                // offline pack and a stale one nobody was told about.
                Text("\(pack.sizeLabel) · \(pack.parts.joined(separator: " · "))")
                    .font(WP.body(11.5)).opacity(0.55).tnum()
                Text("Downloaded \(pack.packedAt.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(WP.bodyItalic(11)).opacity(0.45)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { removing = pack } label: {
                Text("Remove")
                    .font(WP.headingUI(12.5))
                    .foregroundStyle(WP.danger)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.95))
            .accessibilityLabel("Remove the \(pack.name) pack")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// MARK: - Connections

/// Every way this app reaches outside the phone, and whether it has worked.
///
/// What this replaces was a green dot beside three service names, drawn green whatever had
/// happened, and a row reading *Live sources — Re-wiring next pass*. The dot was the app's
/// one rule broken in its own settings: it claimed three services were healthy without
/// having asked any of them.
struct ConnectionsScreen: View {
    @Environment(AppState.self) private var app
    @State private var checking = false

    private var connections: Connections { Connections.shared }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What the app reaches for").kickerStyle()
                        Text("Connections").font(WP.displayBold(38)).tracking(-0.4).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    GlassDisc(icon: "chevron.left", size: 44) { app.pop() }
                        .accessibilityLabel("Back to Preferences")
                        .padding(.top, 2)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    internetRow
                    proxyRow.padding(.top, 12)

                    Text("Sources".uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.5)
                        .padding(.top, 24).padding(.bottom, 8)

                    Grouped {
                        ForEach(Array(Connections.sources.enumerated()), id: \.element.id) { index, source in
                            sourceRow(source)
                            if index < Connections.sources.count - 1 { Hairline() }
                        }
                    }

                    SourceLine("Read from the app itself, not from a status page. A source is marked heard from when a request to it came back, and did not answer when one failed — with the reason. Not needed yet means nothing has had cause to ask since the app opened, which is not a fault: a park screen nobody opened asks the park service nothing.",
                               ruled: false)
                        .padding(.top, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 8)
                .padding(.bottom, WP.rootScrollBottom)
            }
            .scrollIndicators(.hidden)
        }
        .background(WP.bg)
        .task {
            connections.watch()
            await connections.checkProxy(ProxyConfig())
        }
    }

    // MARK: The two that are asked directly

    /// The phone's own view of whether it has a route out, from `NWPathMonitor` rather
    /// than from a request that happened to fail. A request can fail for a dozen reasons
    /// that are not the network, and being told the wrong one wastes somebody's evening.
    private var internetRow: some View {
        HStack(spacing: 12) {
            dot(connections.isOnline == false ? WP.danger
                : connections.isOnline == true ? WP.live : WP.neutral400)
            VStack(alignment: .leading, spacing: 2) {
                Text("This phone").font(WP.body(14.5))
                Text(connections.isOnline == nil ? "Checking…"
                     : connections.isOnline == true
                        ? "Online over \(connections.connectionKind ?? "a connection")"
                        : "Offline — everything below will be unreachable, and the app falls back to what is stored here")
                    .font(WP.body(11.5)).opacity(0.6).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
    }

    /// The proxy holds the park service's key, so nothing from NPS arrives without it.
    /// Asked rather than inferred — `health()` calls its own endpoint and waits.
    private var proxyRow: some View {
        HStack(spacing: 12) {
            dot(connections.proxyHealthy == false ? WP.danger
                : connections.proxyHealthy == true ? WP.live : WP.neutral400)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waypost proxy").font(WP.body(14.5))
                Text(connections.proxyHealthy == nil ? "Asking…"
                     : connections.proxyHealthy == true
                        ? "Answering. It holds the park service's key — without it the NPS panels are empty."
                        : "Not answering. Fees, hours, alerts and campgrounds will be blank; weather, routing and the map do not go through it and carry on.")
                    .font(WP.body(11.5)).opacity(0.6).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                checking = true
                Task {
                    await connections.checkProxy(ProxyConfig())
                    checking = false
                }
            } label: {
                Group {
                    if checking { ProgressView().controlSize(.small) }
                    else { Text("Check").font(WP.headingUI(12.5)).foregroundStyle(WP.accent700) }
                }
                .frame(minWidth: 52, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.95))
            .disabled(checking)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
    }

    // MARK: One source

    private func sourceRow(_ source: Connections.Source) -> some View {
        let health = connections.health(of: source)
        return HStack(alignment: .top, spacing: 12) {
            dot(colour(health)).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(source.name).font(WP.body(14.5))
                    if source.essential {
                        Text("needed")
                            .font(WP.body(9.5)).tracking(0.9)
                            .foregroundStyle(WP.accent800)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(WP.accent100, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Text(label(health)).font(WP.body(11)).foregroundStyle(colour(health))
                }
                Text(source.what)
                    .font(WP.body(11.5)).opacity(0.6).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let why, _) = health {
                    Text(why)
                        .font(WP.mono(10.5)).foregroundStyle(WP.danger).lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func dot(_ colour: Color) -> some View {
        Circle().fill(colour).frame(width: 7, height: 7)
    }

    private func colour(_ health: Connections.Health) -> Color {
        switch health {
        case .untouched: return WP.neutral400
        case .answered: return WP.live
        case .failed: return WP.danger
        }
    }

    private func label(_ health: Connections.Health) -> String {
        switch health {
        case .untouched: return "Not needed yet"
        case .answered(let at): return "Heard from \(Self.ago(at))"
        case .failed(_, let at): return "Did not answer \(Self.ago(at))"
        }
    }

    /// Relative, and coarse. "Two minutes ago" is what somebody wants to know; the second
    /// it happened on is not.
    private static func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3600) h ago"
    }
}

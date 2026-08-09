import SwiftUI
import UIKit

/// One park, pushed over whatever opened it. The web app's six in-park tabs become one
/// screen with a scrolling segment rail.
struct ParkScreen: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark
    var initialSegment: ParkSegment
    /// The day this park is being read for — a trip's arrival date. Nil means today.
    var date: Date?

    @State private var segment: ParkSegment = .brief
    /// Which way the next page comes in from.
    @State private var forward = true
    /// Where the in-flow rail is on the display, and the line it turns into a header at.
    @State private var railTop: CGFloat = .greatestFiniteMagnitude
    /// Whether the page was pinned when the section was last changed.
    @State private var heldPinned = false

    /// 0 while the rail is part of the park page, 1 once it has become the page's header.
    /// Everything that changes between the two states reads this, so the swap happens over
    /// 56 points of scrolling rather than snapping at a line.
    private var pinned: CGFloat {
        min(max((Self.statusBarInset + Self.barHeight + 56 - railTop) / 56, 0), 1)
    }

    /// The page header: a row for the title, a row for the discs. One row cannot hold
    /// both — a 24pt serif title and six 42pt discs come to more than a phone is wide.
    static let barHeight: CGFloat = 46 + 42 + 14

    /// The status bar's height. Asked of the window rather than of a `GeometryReader`:
    /// this screen's scroll view ignores the top safe area, and the proxy inside it
    /// reports zero — which put the pinned header under the clock.
    static var statusBarInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let inset = scenes.flatMap(\.windows).first { $0.isKeyWindow }?.safeAreaInsets.top
        return inset ?? 47
    }

    private var packState: PackState { app.packState(park.code) }
    private var isSaved: Bool { app.saved.contains(park.code) }

    /// What the park service publishes today, in preference to anything bundled.
    private var facts: ParkFacts.Facts? {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park) { return facts }
        return nil
    }
    private var liveFee: String? { facts?.fee }
    private var liveHours: String? { facts?.hours }

    /// Fees and hours, and where the park service stands on them.
    ///
    /// This showed `park.fee` and `park.hours` whatever happened, so a national park whose
    /// bundled record carries nothing and whose NPS record never arrived read "Not
    /// published · Not published" — which states that the park publishes no fees and no
    /// hours, when what actually happened is that the app failed to ask. A request in
    /// flight now says so, and one that failed says so instead of inventing an absence.
    @ViewBuilder
    private var factsRow: some View {
        switch ParkFacts.shared.state(for: park) {
        case .loading:
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Pulling NPS data…").font(WP.bodyItalic(12.5)).opacity(0.7)
            }
        case .failed:
            factsUnavailable
        case .notCovered where park.designationLabel.localizedCaseInsensitiveContains("National"):
            // NPS answering "no such park" about a National anything — park, monument,
            // seashore — means this app could not work out its code, not that the unit is
            // absent from the register. A state park not being covered is simply true, and
            // says nothing here.
            factsUnavailable
        default:
            // Stacked, not side by side. The hours run to several sentences and the fee is
            // two words, so in two columns the fee sat alone against a paragraph and the
            // eye had to work out which was which. One labelled block each reads straight
            // down.
            VStack(alignment: .leading, spacing: 11) {
                labelledFact("Entrance fee", feeText, fromNPS: liveFee != nil)
                labelledFact("Park hours", hoursText, fromNPS: liveHours != nil)
            }
        }
    }

    /// One fact, with what it is above it and where it came from beside that.
    ///
    /// The attribution is per field rather than per park: NPS can answer with hours and no
    /// fee, and saying the whole block came from the park service would then be wrong
    /// about half of it.
    private func labelledFact(_ label: String, _ value: String, fromNPS: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fromNPS ? "\(label) · NPS".uppercased() : label.uppercased())
                .font(WP.body(10)).tracking(1.4)
                .foregroundStyle(WP.accent800)
            Text(value)
                .font(WP.body(12.5)).opacity(0.85).lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The park service's figure, or nothing.
    ///
    /// This fell back to `park.fee`, which exists for the six parks written by hand and for
    /// nobody else — so those six showed a hard-coded price that no source had confirmed
    /// while every other park showed "Not published". A fee is either what the park service
    /// says it is or it is not known.
    private var feeText: String { liveFee ?? "Not published" }

    private var hoursText: String { liveHours ?? "Not published" }

    /// The two things Apple Maps will hand a third-party app, and a way to the rest.
    ///
    /// `MKMapItem` carries a phone number and a time zone and nothing else of substance —
    /// the hours, ratings and photographs on the Maps place card are licensed from
    /// Tripadvisor, Foursquare and Wikipedia and are not vended through MapKit. So: offer
    /// the number, which answers "what are the hours" better than any guess would, note
    /// the park's own clock when it differs from the phone's, and hand the park to Maps
    /// for everything this app is not allowed to draw.
    @ViewBuilder
    private var parkContactRow: some View {
        if let details = ParkWebsite.shared.details(for: park) {
            VStack(alignment: .leading, spacing: 8) {
                if let phone = details.phone,
                   let dial = URL(string: "tel://" + phone.filter { $0.isNumber || $0 == "+" }) {
                    Link(destination: dial) {
                        contactRow(glyph: "phone", text: phone, trailing: "arrow.up.right")
                    }
                    .accessibilityLabel("Call the park on \(phone)")
                }

                if let zone = details.timeZone, zone.identifier != TimeZone.current.identifier {
                    // A park two zones away opens and closes on its own clock, and the
                    // sunrise and sunset this screen shows are its, not the phone's.
                    contactRow(glyph: "clock",
                               text: "Park time \(Self.clock(in: zone)) · \(zone.abbreviation() ?? zone.identifier)",
                               trailing: nil)
                }

                Button {
                    details.mapItem.openInMaps()
                } label: {
                    contactRow(glyph: "map", text: "See it in Apple Maps", trailing: "arrow.up.right")
                }
                .buttonStyle(PressStyle(scale: 0.99))
            }
            .padding(.top, 8)
        }
    }

    private func contactRow(glyph: String, text: String, trailing: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
            Text(text).font(WP.body(12.5)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing).font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(WP.accent700)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WP.accent.opacity(0.45), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func clock(in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }

    /// Where the park itself publishes, for the parks no register covers.
    ///
    /// A state park has no NPS record, so fee and hours read "Not published" and the screen
    /// had nowhere to send anybody — two words and a dead end. The park's own page is the
    /// answer to "then where do I look", and Apple Maps knows the address.
    @ViewBuilder
    private var parkWebsiteRow: some View {
        if case .found(let url) = ParkWebsite.shared.state(for: park) {
            Link(destination: url) {
                HStack(spacing: 9) {
                    Image(systemName: "safari")
                        .font(.system(size: 13, weight: .semibold))
                    Text(liveFee == nil
                         ? "Fees, hours and closures — on the park's own site"
                         : "The park's own site")
                        .font(WP.body(12.5))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(WP.accent700)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WP.accent.opacity(0.45), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 12)
            .accessibilityLabel("Open the park's own website")
        }
    }

    private var factsUnavailable: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WP.accent700)
            Text("Unable to pull NPS data — fees and hours are not available for this park right now.")
                .font(WP.bodyItalic(12.5)).lineSpacing(2).opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        // The photograph runs to the very top of the display — under the status bar and
        // around the island — so opening a park feels like arriving at it rather than
        // reading a page about it. Only the scroll view ignores the safe area; the back
        // control sits inside it, floating over the picture.
        ZStack(alignment: .topLeading) {
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        masthead
                        actions

                        SegmentDiscRail(options: railOptions, selection: segmentBinding)
                            .id(Self.railAnchor)
                            .padding(.horizontal, WP.gutter)
                            .padding(.top, 14)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                Rectangle().fill(WP.bg.opacity(0.94))
                                    .overlay(alignment: .bottom) { Hairline() }
                            }
                            // Where the rail is on the display, which is what decides
                            // whether the section is still part of the park page or has
                            // become a page of its own.
                            .modifier(TracksTopEdge { railTop = $0 })
                            // It does not scroll away so much as hand over: the pinned bar
                            // above is fading in on the same movement.
                            .opacity(1 - pinned)

                        section
                            .padding(.horizontal, WP.gutter)
                            .padding(.top, Self.sectionTop)
                            .padding(.bottom, WP.tabBarClearance)
                            // Every section is at least a screen tall, so a short one —
                            // weather is six figures and a line — can still be scrolled
                            // into the pinned state the long ones reach.
                            .frame(minHeight: Self.pageHeight, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .captureScrollPosition()
                // Turning the page while pinned puts the new section's first line under
                // the header — the scroll offset is wherever the reading left it. Put the
                // rail back at the top and the stand-in above does the rest.
                .onChange(of: segment) { _, _ in
                    guard heldPinned else { return }
                    Task { @MainActor in
                        withAnimation(.snappy(duration: 0.2)) {
                            scroller.scrollTo(Self.railAnchor, anchor: .top)
                        }
                    }
                }
            }

                // Back floats over the photograph until the bar takes the job over.
                backControl.opacity(1 - pinned)

                pinnedBar
                    .opacity(pinned)
                    .allowsHitTesting(pinned > 0.5)
        }
        .simultaneousGesture(pageTurn)
        .overlay(alignment: .bottom) { pageDots }
        .onPreferenceChange(RailTopKey.self) { railTop = $0 }
        .background(WP.bg)
        .toolbar(.hidden, for: .navigationBar)
        // The brief is what a park screen opens on. It was whichever section was read
        // last, which meant opening a park you had once checked the campgrounds for put
        // you in the campgrounds rather than at the top of the page.
        .onAppear { segment = initialSegment }
        .task(id: park.code) {
            ParkFacts.shared.load(park)
            ParkWebsite.shared.load(park)
        }
        .onChange(of: segment) { _, new in app.parkSegment[park.code] = new }
    }

    /// The rail, as something the scroll view can be told to go back to.
    private static let railAnchor = "park-sections"

    /// The rail's own height: a 44pt disc with 14 above it and 10 below.
    private static let railHeight: CGFloat = 68

    /// The air above a section.
    ///
    /// 34 of it is spent standing in for the header, which is two rows deep where the rail
    /// it replaces is one — so a section anchored under the header keeps the other 34 as
    /// actual space between the hairline and the first line it prints.
    private static let sectionTop: CGFloat = 68

    /// A section's minimum height: the display, less the pinned header.
    ///
    /// This is what holds the page pinned when it is turned. Every section being at least
    /// a screen tall means switching to a shorter one — weather is six figures and a line
    /// — cannot make the scroll view spring back to the photograph, so nothing has to be
    /// scrolled back into place afterwards.
    static var pageHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        let height = window?.bounds.height ?? 852
        return max(320, height - statusBarInset - barHeight)
    }

    private var railOptions: [(value: ParkSegment, label: String, short: String, icon: String)] {
        ParkSegment.allCases.map { ($0, $0.label, $0.shortLabel, $0.icon) }
    }

    /// Picking a section, from a disc or from a swipe. The direction is worked out here,
    /// before the change lands, so the outgoing page leaves the way the incoming one
    /// arrives rather than both sliding the same way.
    private var segmentBinding: Binding<ParkSegment> {
        Binding(
            get: { segment },
            set: { new in
                guard new != segment else { return }
                heldPinned = pinned > 0.5
                let all = ParkSegment.allCases
                forward = (all.firstIndex(of: new) ?? 0) > (all.firstIndex(of: segment) ?? 0)
                withAnimation(.snappy(duration: 0.28)) { segment = new }
                Haptics.tap()
            }
        )
    }

    /// The section itself: one page, the full width of the screen, scrolling as far as it
    /// needs to. A horizontal drag moves to the next one.
    private var section: some View {
        Group {
            switch segment {
            case .brief: AIBriefSection(park: park, date: date)
            case .overview: OverviewSection(park: park)
            case .weather: WeatherSection(park: park, date: date)
            case .stay: StaySection(park: park)
            case .plan: PlansSection(park: park)
            case .near: NearbySection(park: park)
            }
        }
        .id(segment)
        .transition(.asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        ))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Turning the page with a sideways drag.
    ///
    /// Simultaneous and screen-wide, so a vertical drag still scrolls and a sideways one
    /// anywhere on the page turns it. Drags that begin at the left edge are left alone:
    /// that is the system's back-swipe, and stealing it would strand anybody who leaves a
    /// park the way they leave every other screen.
    private var pageTurn: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { drag in
                guard drag.startLocation.x > 32 else { return }
                let across = drag.translation.width
                guard abs(across) > 48, abs(across) > abs(drag.translation.height) * 1.4 else { return }
                let all = ParkSegment.allCases
                guard let here = all.firstIndex(of: segment) else { return }
                let next = here + (across < 0 ? 1 : -1)
                guard all.indices.contains(next) else { return }
                segmentBinding.wrappedValue = all[next]
            }
    }

    /// The page header: what the old rail turns into once it reaches the top. The section
    /// gives the page its name, the discs stay within reach on the right.
    private var pinnedBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { app.pop() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.9))

                // The same 24pt serif every other pushed screen puts its name in.
                Text(segment.label)
                    .font(WP.display(24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)

                Spacer(minLength: 0)
            }
            .foregroundStyle(WP.text)
            .padding(.horizontal, WP.gutter)
            .frame(height: 46)

            SegmentDiscRail(options: railOptions, selection: segmentBinding, compact: true)
                .padding(.horizontal, WP.gutter)
                .padding(.bottom, 14)

            Hairline()
        }
        // No top padding: the ZStack already places this below the status bar, and adding
        // the inset again put the header a second status bar down the screen. Only the
        // plate behind it runs up under the clock.
        .background {
            Rectangle().fill(WP.bg).ignoresSafeArea(edges: .top)
        }
    }

    /// Which page of six this is — the one thing the discs alone do not say, because a
    /// glyph does not tell you how many are left.
    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(ParkSegment.allCases, id: \.self) { page in
                Capsule()
                    .fill(page == segment ? WP.ink : WP.text.opacity(0.22))
                    .frame(width: page == segment ? 15 : 5, height: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(.pill, radius: 999)
        .padding(.bottom, 18)
        .opacity(pinned)
        .allowsHitTesting(false)
    }

    /// The photograph, full-bleed, dissolving into the page rather than stopping at an
    /// edge — so the name below it reads as being written on the same sheet.
    private var hero: some View {
        ParkImage(park: park, showsScrim: false, topLight: false)
            // Taller than its layout by the height of the status bar, then pulled up by
            // the same amount: the photograph runs under the clock and the island as it
            // always did, but the scroll view below it keeps its safe area — which is what
            // lets a page turn land the section's first line under the header instead of
            // 93 points above it.
            .frame(height: 372 + Self.statusBarInset)
            .padding(.top, -Self.statusBarInset)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: WP.bg, location: 0),
                        .init(color: WP.bg.opacity(0.72), location: 0.38),
                        .init(color: WP.bg.opacity(0), location: 1),
                    ],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: 150)
                .allowsHitTesting(false)
            }
    }

    /// The name, on the page, under the photograph.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text([park.state, park.designationLabel, park.source == nil ? park.crowd : park.region]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ").uppercased())
                .font(WP.body(10)).tracking(1.4)
                .foregroundStyle(WP.accent800)
            Text(park.name)
                .font(WP.display(38))
            Text(park.tag)
                .font(WP.bodyItalic(12.5))
                .opacity(0.7)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 2)
    }

    /// Back, floating on glass over the photograph — the only chrome above the fold.
    private var backControl: some View {
        Button { app.pop() } label: {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                Text("Back").font(WP.body(18))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 17)
            .frame(minHeight: 44)
            .glassControl()
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .padding(.leading, WP.gutter)
        .padding(.top, 6)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Button { app.toggleSaved(park.code) } label: {
                    Text(isSaved ? "Saved" : "Save this park")
                        .font(WP.headingUI(14))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .glassControl()
                }
                .buttonStyle(PressStyle(scale: 0.98))

                Button { app.startPack(park.code) } label: {
                    Text(packState == .ready ? "Pack on device"
                         : packState == .busy ? "Downloading \(Int((app.packProgress[park.code] ?? 0) * 100))%"
                         : "Offline pack · \(park.pack)")
                        .font(WP.headingUI(14))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .glassControl()
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }

            // The park in front of somebody is the likeliest first stop of a trip, whatever
            // its designation — so the builder opens from here on every park screen, not
            // only the state ones.
            Button {
                app.startBuilder(around: park)
            } label: {
                Text("Plan a trip here")
                    .font(WP.headingUI(14))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .glassControl()
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .padding(.top, 9)

            factsRow.padding(.top, 13)
            parkWebsiteRow
            parkContactRow

            // A live record often has no gateway town, and "Gateway town" followed by
            // nothing reads as a bug rather than as an absence.
            if !park.gw.isEmpty {
                Text("Gateway town \(park.gw)")
                    .font(WP.bodyItalic(12.5)).opacity(0.62).padding(.top, 3)
            }
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 14)
    }
}

// MARK: - Overview

struct OverviewSection: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The park service's own timed-entry line when it has one — the real answer, in
            // the park's words. It reads from the `feespasses` endpoint, which the app did
            // not call before, so this used to be a hard-coded "reservations not listed"
            // note whatever the park actually required.
            if let reservation = facts?.reservation {
                reserveBlock(reservation, label: "Timed entry · NPS")
            } else if park.res {
                reserveBlock(park.resNote, label: "Reserve before you arrive")
            } else {
                Text(park.resNote)
                    .font(WP.bodyItalic(13)).lineSpacing(3).opacity(0.75)
            }

            // An empty alert list used to hide this section outright, so a park with a
            // closure the app failed to fetch looked exactly like a park with nothing to
            // report. Of everything the screen can be quietly wrong about, this is the one
            // that matters on the road.
            if alertsUnavailable {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle("Know before you go")
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WP.accent700)
                        Text("Current alerts could not be checked. Ask the park before you travel.")
                            .font(WP.bodyItalic(12.5)).lineSpacing(2).opacity(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
            }

            if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Know before you go")
                ForEach(alerts) { alert in
                    Button {
                        app.sheet = .alert(park: park.name, alert: alert)
                    } label: {
                        DividedRow(vertical: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(alert.cat)
                                        .font(WP.body(10))
                                        .padding(.horizontal, 9).padding(.vertical, 2)
                                        .overlay(Capsule().stroke(WP.accent, lineWidth: 1))
                                        .foregroundStyle(WP.accent700)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(WP.accent700)
                                }
                                Text(alert.title).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                Text(alert.body).font(WP.body(12.5)).lineSpacing(2).opacity(0.75)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            }
            }

            if !park.gates.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Entry gates")
                ForEach(park.gates, id: \.self) { gate in
                    DividedRow(vertical: 9) {
                        Text(gate).font(WP.body(13.5)).lineSpacing(2)
                    }
                }
                if !park.parking.isEmpty {
                    Text(park.parking)
                        .font(WP.bodyItalic(12.5)).lineSpacing(3).opacity(0.7)
                        .padding(.top, 9)
                }
            }
            }

            if !park.airports.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Fly-in airports")
                ForEach(park.airports) { airport in
                    DividedRow(vertical: 11) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(airport.code)
                                .font(WP.mono(16))
                                .tracking(2.8)
                                .foregroundStyle(WP.accent800)
                                .frame(minWidth: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(airport.name).font(WP.body(13)).lineSpacing(1)
                                Text(airport.drive).font(WP.body(12)).opacity(0.6)
                                Text(airport.note).font(WP.bodyItalic(11.5)).opacity(0.6).lineSpacing(1)
                            }
                            Spacer(minLength: 0)
                            if airport.best == true {
                                Text("Best")
                                    .font(WP.body(10))
                                    .padding(.horizontal, 9).padding(.vertical, 2)
                                    .background(WP.accent100, in: Capsule())
                                    .foregroundStyle(WP.accent800)
                            }
                        }
                    }
                }
            }

            }

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Fuel & charging")
                // Apple Maps knows every charger and pump in the country; the curated
                // lists covered four parks. Tapping a row opens directions to it.
                PlaceRows(park: park, kind: .charger, title: "Charging")
                PlaceRows(park: park, kind: .fuel, title: "Gasoline")

                // The reason a camper looks at this screen at all: the last shop before
                // the gate.
                PlaceRows(park: park, kind: .store, title: "Shops & supplies")
            }

            SourceLine(overviewSource)
        }
    }

    private var facts: ParkFacts.Facts? {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park) { return facts }
        return nil
    }

    private func reserveBlock(_ text: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(WP.body(10)).tracking(1.4)
                .foregroundStyle(WP.accent800)
            Text(text)
                .font(WP.body(13)).lineSpacing(3)
                .foregroundStyle(WP.accent900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(WP.accent100, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.accent300, lineWidth: 1))
    }

    /// The fee the park service publishes today, in preference to anything bundled.
    private var liveFee: String? { facts?.fee }
    private var liveHours: String? { facts?.hours }

    /// Alerts the park is posting right now — closures, fire, road work — ahead of the
    /// bundled ones, which are editorial rather than current.
    private var alerts: [CuratedAlert] {
        if let live = facts?.alerts, !live.isEmpty { return live }
        return park.alerts
    }

    /// True when the park service refused the alerts request, as distinct from answering
    /// that this park has none posted.
    private var alertsUnavailable: Bool {
        facts?.unavailable.contains("alerts") == true && alerts.isEmpty
    }

    /// Which of the two catalogues this park's overview is being read out of, and which
    /// of the live services filled in the rest.
    private var overviewSource: String {
        let base = park.source == nil
            ? "Overview from ParkHop's own records."
            : "Overview from \(park.sourceName) — fees, hours and closures come from the park itself."
        return base + " Charging, fuel and shops from Apple Maps, measured from the park's own coordinates."
    }
}

// MARK: - Weather

struct WeatherSection: View {
    var park: CuratedPark
    /// The day being asked about. Nil means today.
    var date: Date?

    private var day: Date { date ?? Date() }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// How the day reads in a sentence: "today", or the date itself when it is not.
    private var dayLabel: String {
        isToday ? "today" : day.formatted(.dateTime.day().month(.wide))
    }

    /// Live weather for a park the curated library has never heard of — and, once it has
    /// come back, for the eight it has. Open-Meteo needs no key, so this works on any
    /// phone with a network; blended with the National Weather Service where it covers.
    @State private var live: WeatherDay?

    /// What the panel is actually reading: the live forecast if one arrived, otherwise
    /// the curated normals — and if the park has neither, nothing at all.
    private var wx: CuratedWeather {
        if let live { return park.withWeather(live).wx }
        return park.wx
    }

    private var hasNumbers: Bool { live != nil || park.wx.isPublished || park.source == nil }

    private var light: WeatherLight { WeatherLight(high: wx.hi) }

    /// A dash, not a zero. A park whose forecast has not arrived is not a park at 0°.
    private func value(_ text: @autoclosure () -> String) -> String {
        hasNumbers ? text() : "—"
    }

    private var cells: [(label: String, value: String, sub: String, dot: Color)] {
        [
            ("High", value("\(wx.hi)°"), live == nil ? "bundled normal" : dayLabel, light.color),
            ("Low", value("\(wx.lo)°"), "overnight", wx.lo <= 32 ? Color(oklch: 0.66, 0.13, 70) : Color(oklch: 0.60, 0.13, 150)),
            ("UV index", value(wx.uvIndex), wx.uvWord, uvColor),
            ("Wind", value(wx.wind), "max sustained", windColor),
            ("Sunrise", value(wx.sr.clockPadded), "first light", Color(oklch: 0.60, 0.13, 150)),
            ("Sunset", value(wx.ss.clockPadded), "last light", Color(oklch: 0.60, 0.13, 150)),
        ]
    }

    private var uvColor: Color {
        let uv = Int(wx.uvIndex) ?? 0
        if uv >= 11 { return Color(oklch: 0.55, 0.16, 30) }
        if uv >= 8 { return Color(oklch: 0.66, 0.13, 70) }
        return Color(oklch: 0.55, 0.09, 150)
    }

    private var windColor: Color {
        let numbers = wx.wind.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        let peak = numbers.max() ?? 0
        if peak >= 35 { return Color(oklch: 0.55, 0.16, 30) }
        if peak >= 20 { return Color(oklch: 0.66, 0.13, 70) }
        return Color(oklch: 0.55, 0.09, 150)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle().fill(light.color).frame(width: 10, height: 10)
                Text(light.label).font(WP.bodyItalic(13)).opacity(0.8)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                ForEach(cells, id: \.label) { cell in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(cell.dot).frame(width: 6, height: 6)
                            Text(cell.label.uppercased())
                                .font(WP.body(10)).tracking(1.4).opacity(0.6)
                        }
                        Text(cell.value).font(WP.statValue(22)).tnum().lineLimit(1).minimumScaleFactor(0.7)
                        Text(cell.sub).font(WP.body(10.5)).opacity(0.55)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 12)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            // No rule under the verdict line. The grid's own row hairlines already say
            // where the readings start, and a second one directly above them read as an
            // underline struck through the sentence.
            .padding(.top, 18)

            Text(hasNumbers ? wx.note : "No forecast has come back for this park yet.")
                .font(WP.bodyItalic(13)).lineSpacing(3).opacity(0.8)
                .padding(.top, 14)

            SourceLine(sourceLine)
                .padding(.top, 16)
        }
        // Keyed on the day as well as the park: this asked for `Date()` regardless, so a
        // trip being planned for next month still read today's forecast.
        .task(id: "\(park.code)|\(WPDate.iso(day))") {

            live = await WeatherService(failures: FailureLog())
                .forecast(lat: park.lat, lon: park.lon, iso: WPDate.iso(day))
        }
    }

    private var sourceLine: String {
        if let live {
            return isToday
                ? "Today at this park, from \(live.source)."
                : "\(dayLabel) at this park, from \(live.source)."
        }
        if park.wx.isPublished || park.source == nil {
            return "Bundled normals. The forecast for \(dayLabel) is being fetched; when it answers, this panel says so."
        }
        return "\(park.sourceName) does not publish weather. Open-Meteo is being asked for this park's forecast — until it answers there is nothing here to read."
    }
}

// MARK: - Stay

struct StaySection: View {
    var park: CuratedPark

    private var liveCampgrounds: [ParkFacts.Campground] {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park) { return facts.campgrounds }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // What the park service publishes, and what Recreation.gov says is free.
            if !liveCampgrounds.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle("Campgrounds")
                    ForEach(liveCampgrounds) { camp in
                        LiveCampgroundRow(camp: camp)
                    }
                }
            }

            if liveCampgrounds.isEmpty, !park.camping.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Campgrounds")
                ForEach(park.camping) { camp in
                    DividedRow(vertical: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(camp.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(camp.av)
                                    .font(WP.body(10))
                                    .padding(.horizontal, 9).padding(.vertical, 2)
                                    .background(chipBackground(camp), in: Capsule())
                                    .foregroundStyle(chipForeground(camp))
                            }
                            Text("\(camp.whereText) · \(camp.sites) · \(camp.price)")
                                .font(WP.body(12)).opacity(0.7).lineSpacing(2).tnum()
                            Text("\(camp.status) · \(camp.src)")
                                .font(WP.bodyItalic(12)).foregroundStyle(WP.accent700)
                        }
                    }
                }
            }
            }

            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Lodges & hotels")
                ForEach(park.lodging) { stay in
                    DividedRow(vertical: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(stay.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(stay.price).font(WP.body(12.5)).foregroundStyle(WP.accent700)
                            }
                            Text("\(stay.whereText) · \(stay.note)")
                                .font(WP.body(12)).opacity(0.7).lineSpacing(2)
                        }
                    }
                }
            }

            // The curated lists cover the campgrounds inside four parks. Everything
            // around every other park in the country comes from Apple Maps.
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Camping & RV around the park")
                PlaceRows(park: park, kind: .campground, limit: 6)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Beds nearby")
                PlaceRows(park: park, kind: .lodging, limit: 5)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Eating")
                PlaceRows(park: park, kind: .food, limit: 5)
            }

            SourceLine(staySource)
        }
    }

    /// Two catalogues, named separately: what is inside the park, and what is around it.
    private var staySource: String {
        (park.camping.isEmpty
            ? "No in-park campground list ships for this park."
            : "In-park campgrounds and lodges from ParkHop's own records.")
        + " Everything under them is Apple Maps, within thirty miles of the park, nearest first."
        + " Campgrounds and nightly availability from the National Park Service and Recreation.gov."
    }

    private func chipBackground(_ camp: CuratedCamp) -> Color {
        if camp.isClosed { return WP.neutral200 }
        if camp.isOpen { return WP.accent100 }
        return WP.neutral100
    }

    private func chipForeground(_ camp: CuratedCamp) -> Color {
        camp.isOpen ? WP.accent800 : WP.neutral800
    }
}

// MARK: - Plans

struct PlansSection: View {
    var park: CuratedPark

    private var thingsToDo: [ParkFacts.Activity] {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park) { return facts.thingsToDo }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(park.days.enumerated()), id: \.element.title) { index, plan in
                VStack(alignment: .leading, spacing: 0) {
                    Kicker(text: "Day \(index + 1) in park")
                    Text(plan.title).font(WP.rowTitle(18)).padding(.top, 5)
                        .multilineTextAlignment(.leading)
                    VStack(spacing: 0) {
                        ForEach(plan.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Text(item.time.clockPadded)
                                    .font(WP.body(11.5))
                                    .foregroundStyle(WP.accent700)
                                    .frame(width: 52, alignment: .leading)
                                Text(item.text).font(WP.body(12.5)).lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .top) { Hairline() }
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
            }

            if !thingsToDo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle("Things to do")
                    ForEach(thingsToDo) { activity in
                        DividedRow(vertical: 11) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(activity.title)
                                        .font(WP.rowTitle(16)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    if let duration = activity.duration {
                                        Text(duration).font(WP.body(11.5)).opacity(0.6)
                                    }
                                }
                                if let note = activity.note {
                                    Text(note).font(WP.body(12)).opacity(0.7).lineSpacing(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            SourceLine(thingsToDo.isEmpty
                       ? "Day plans written around the light and the crowds."
                       : "Day plans written around the light and the crowds; the list under them is what the National Park Service publishes for this park.")
        }
    }
}

// MARK: - Nearby

struct NearbySection: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Passport pages beyond the big park — monuments, historic sites and memorials within striking distance. A cancellation stamp waits at each visitor centre.")
                .font(WP.body(13)).lineSpacing(3).opacity(0.8)
                .padding(.bottom, 6)

            ForEach(park.stamps) { stamp in
                Button {
                    app.sheet = .stamp(name: stamp.name, city: stamp.city, dist: stamp.dist)
                } label: {
                    DividedRow(vertical: 12) {
                        HStack(spacing: 12) {
                            Text(stamp.dist)
                                .font(WP.body(12)).foregroundStyle(WP.accent700)
                                .frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stamp.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                Text("\(stamp.city) · \(stamp.desig)")
                                    .font(WP.bodyItalic(11.5)).opacity(0.6)
                            }
                            Spacer(minLength: 0)
                            if app.isStamped(app.stampKey(forName: stamp.name)) {
                                Text("Stamped")
                                    .font(WP.body(10))
                                    .padding(.horizontal, 9).padding(.vertical, 2)
                                    .background(WP.accent100, in: Capsule())
                                    .foregroundStyle(WP.accent800)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WP.accent700)
                        }
                    }
                }
                .buttonStyle(PressStyle(scale: 0.99))
            }

            SourceLine("Passport units near this park.")
                .padding(.top, 16)
        }
    }
}

// MARK: - Shared bits

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        // 14, not 12: at a point and a half of tracking these are the only signposts in a
        // long page of readings, and they were reading as captions rather than headings.
        Text(text.uppercased())
            .font(WP.body(14))
            .tracking(1.5)
            .foregroundStyle(WP.accent700)
            .padding(.bottom, 4)
    }
}

/// Every panel names where its rows came from — the discipline the web app keeps.
struct SourceLine: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(WP.body(11.5))
            .lineSpacing(3)
            .opacity(0.5)
            .padding(.top, 12)
            .overlay(alignment: .top) { Hairline() }
    }
}


/// One campground: what the park service says about it, and what Recreation.gov says is
/// free tonight.
///
/// The two are different questions and the row keeps them apart — a campground with 184
/// sites and none free is not the same as one that takes no reservations at all, and
/// neither is the same as a request that failed.
struct LiveCampgroundRow: View {
    var camp: ParkFacts.Campground

    private var availability: Recreation.State? {
        camp.facilityID.map { Recreation.shared.state(facility: $0) }
    }

    private var tonight: String {
        guard let id = camp.facilityID else { return "" }
        switch Recreation.shared.state(facility: id) {
        case .loaded:
            guard let free = Recreation.shared.freeSites(facility: id, on: Date()) else {
                return "No calendar for tonight"
            }
            return free == 0 ? "Full tonight" : "\(free) free tonight"
        case .loading, .idle: return "Checking…"
        case .notBookable: return "First-come, no calendar"
        case .failed: return "Availability unavailable"
        }
    }

    private var chipColour: Color {
        guard let id = camp.facilityID,
              case .loaded = Recreation.shared.state(facility: id),
              let free = Recreation.shared.freeSites(facility: id, on: Date())
        else { return WP.neutral200 }
        return free == 0 ? WP.neutral200 : WP.accent100
    }

    var body: some View {
        DividedRow(vertical: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(camp.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if camp.facilityID != nil {
                        Text(tonight)
                            .font(WP.body(10))
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .background(chipColour, in: Capsule())
                            .foregroundStyle(WP.accent800)
                    }
                }

                // The record is the park service's; the nightly count beside it is not.
                // A facility id means this campground books through Recreation.gov, and
                // that is where the chip above came from — said here rather than left to
                // a footnote at the bottom of the panel covering four different sources.
                Text([camp.sites.map { "\($0) sites" }, camp.fee,
                      camp.facilityID != nil ? "Availability from Recreation.gov" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(WP.body(12)).opacity(0.7).tnum()

                if let note = camp.reservationNote {
                    Text(note)
                        .font(WP.bodyItalic(12)).opacity(0.65).lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .task(id: camp.facilityID) {
            if let id = camp.facilityID { Recreation.shared.load(facility: id) }
        }
    }
}

/// Reports where a view's top edge is on the display, as it scrolls.
///
/// `onGeometryChange` writes straight to the state that reads it. The preference-key path
/// below it is the iOS 17 fallback and nothing more — a preference published from inside
/// this screen's scroll view did not reach the root, and chasing why was not worth it when
/// the newer API says the same thing in one line.
private struct TracksTopEdge: ViewModifier {
    var onChange: (CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                onChange(top)
            }
        } else {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: RailTopKey.self,
                                           value: proxy.frame(in: .global).minY)
                }
            }
        }
    }
}

/// Where the section rail sits on the display, reported up out of the scroll view.
private struct RailTopKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

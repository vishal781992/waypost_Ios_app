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
    /// 0 while the rail is part of the park page, 1 once it has become the page's header.
    /// Everything that changes between the two states reads this, so the swap happens over
    /// 56 points of scrolling rather than snapping at a line.
    private var pinned: CGFloat {
        min(max((Self.statusBarInset + Self.barHeight + 56 - railTop) / 56, 0), 1)
    }

    /// The in-flow rail's fade and the pinned bar's — staggered, rather than crossed.
    ///
    /// Both used to read `pinned` straight: the rail at `1 - pinned`, the bar at `pinned`.
    /// Halfway through the handover that put two rails on the display at half strength, in
    /// two different places, and the discs of one read through the words of the other. The
    /// rail now finishes fading out before the bar has much of itself drawn, so only one of
    /// them is ever substantially on the page and the swap reads as a hand-over instead of
    /// a double exposure.
    private var railFade: CGFloat { 1 - min(1, pinned / 0.62) }
    private var barFade: CGFloat { min(max((pinned - 0.38) / 0.62, 0), 1) }

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

    /// Whether this park is already on the visited rail — stamped on the ground, written
    /// into a trip that has been, or added here by hand.
    private var hasVisited: Bool { app.visitRail.contains { $0.id == park.code } }

    /// "I have been here." The mark's orange when it is still an action; a settled state
    /// once it is a fact, because a filled control that does nothing is a trap.
    @ViewBuilder
    private var visitButton: some View {
        if hasVisited {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("Visited").font(WP.headingUI(14))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(WP.text.opacity(0.55))
            .background {
                Capsule().stroke(WP.text.opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel("\(park.name) is on your visited list")
        } else {
            Button {
                app.addVisit(park.code)
            } label: {
                Text("Visited")
                    .font(WP.headingUI(14))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .markControl()
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Mark \(park.name) as visited")
        }
    }

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
                            // above is fading in behind it, a beat later.
                            .opacity(railFade)

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
                // Picking a section makes it the page, wherever the rail was picked from.
                //
                // This used to fire only when the page was already pinned, so choosing
                // Weather from halfway down the overview swapped the content somewhere
                // below the fold and left the reader looking at park hours — the section
                // they asked for was on screen, but not the part of it that says so. The
                // rail rides to the top on the same movement that changes the content, and
                // the pinned bar fades in behind it.
                .onChange(of: segment) { _, _ in
                    Task { @MainActor in
                        withAnimation(.snappy(duration: 0.32)) {
                            scroller.scrollTo(Self.railAnchor, anchor: .top)
                        }
                    }
                }
            }

                // Back floats over the photograph until the bar takes the job over.
                backControl.opacity(railFade)

                pinnedBar
                    .opacity(barFade)
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
            Text([park.stateName, park.designationLabel, park.source == nil ? park.crowd : park.region]
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

            // Two things a reader wants from a park screen: to plan going, and to say they
            // have already been. Planning ran the full width and being-there had nowhere to
            // be said at all — the visited rail could only be filled from the Profile
            // screen, or by standing in the park with the geofence running.
            //
            // 65/35 rather than half and half: planning is the larger errand and the one
            // most readers came for, and "Visited" is a word where the other is four.
            GeometryReader { geo in
                let gap: CGFloat = 9
                let usable = geo.size.width - gap
                HStack(spacing: gap) {
                    Button {
                        app.startBuilder(around: park)
                    } label: {
                        Text("Plan a trip here")
                            .font(WP.headingUI(14))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .glassControl()
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .frame(width: usable * 0.65)

                    visitButton
                        .frame(width: usable * 0.35)
                }
            }
            .frame(height: 46)
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
            } else {
                // Two bundled lines used to stand in here — a written-down reservation note
                // for the eight parks in `curated.json`, and "not listed" for everywhere
                // else. A reservation rule that changes between seasons is not something to
                // ship in a build.
                Text(facts == nil
                     ? "Asking the park service whether an entry reservation is required…"
                     : "The park service lists no entry reservation for \(park.name).")
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
                    // Red for a danger or a closure, amber for a caution, green for an
                    // information notice. The tag was one brass outline whatever it said,
                    // so a flash-flood warning and a car-park notice were the same object
                    // on the page and the reader had to read every row to find the one
                    // that mattered.
                    let tone = AlertSeverity(category: alert.cat).color
                    Button {
                        app.sheet = .alert(park: park.name, alert: alert)
                    } label: {
                        DividedRow(vertical: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(alert.cat)
                                        .font(WP.body(10))
                                        .padding(.horizontal, 9).padding(.vertical, 2)
                                        .background(tone.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().stroke(tone, lineWidth: 1))
                                        .foregroundStyle(tone)
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
                // The park service's own car parks. A single written-down sentence used to
                // sit here — "Midway Geyser Basin and Grand Prismatic fill 9 am–4 pm" —
                // true of one summer and shipped for eight parks.
                ForEach(facts?.parking ?? [], id: \.self) { lot in
                    Text(lot)
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

    /// Alerts the park is posting right now — closures, fire, road work. Only the park
    /// service's; there used to be a bundled list behind these for eight parks, and an
    /// alert that is out of date is worse than no alert.
    ///
    /// Most serious first: dangers, then closures, then cautions, then information. These
    /// arrive in whatever order the park service returns them, which is neither severity
    /// nor date — so a flash-flood danger could sit fourth, below two car-park notices, on
    /// the one list in the app that exists to be read top-down before setting off. Sorting
    /// is stable, so alerts of equal severity keep the park's own order.
    private var alerts: [CuratedAlert] {
        (facts?.alerts ?? []).enumerated()
            .sorted {
                let (a, b) = (AlertSeverity(category: $0.element.cat), AlertSeverity(category: $1.element.cat))
                return a == b ? $0.offset < $1.offset : a < b
            }
            .map(\.element)
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

    /// The day the screen was opened on — today, or the trip's day where there is one.
    private var base: Date { date ?? Date() }

    /// How many days past `base` is being read. A forecast is worth having in advance of
    /// the trip as much as on it: the question this panel is really asked is not "what is
    /// the weather" but "should I go on a different day", and that cannot be answered by a
    /// panel that only ever shows one.
    @State private var offset: Int = 0

    /// Five days out, and no further. Open-Meteo carries about a fortnight and the
    /// climatology carries the rest, but past a few days a forecast stops being a forecast
    /// — and a week of arrows is a control nobody reaches the end of.
    private static let horizon = 5

    private var day: Date {
        Calendar.current.date(byAdding: .day, value: offset, to: base) ?? base
    }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// How the day reads in a sentence: "today", or the date itself when it is not.
    private var dayLabel: String {
        isToday ? "today" : day.formatted(.dateTime.day().month(.wide))
    }

    /// How the day reads as a heading, where it is the subject rather than an aside.
    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The line under the day, where there is one worth adding. "Today" and "Tomorrow" do
    /// not say which date they are; a date already has, and printing it twice in two
    /// formats is the sort of thing that reads as a placeholder nobody finished.
    private var daySubtitle: String? {
        let calendar = Calendar.current
        guard calendar.isDateInToday(day) || calendar.isDateInTomorrow(day) else { return nil }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Live weather for a park the curated library has never heard of — and, once it has
    /// come back, for the eight it has. Open-Meteo needs no key, so this works on any
    /// phone with a network; blended with the National Weather Service where it covers.
    @State private var live: WeatherDay?

    /// Which tile has been opened for its extra line. One at a time: the point of the
    /// gesture is that the rest of the slab steps back while you read one reading.
    @State private var openTile: String?

    /// What the panel is actually reading: the live forecast if one arrived, otherwise
    /// the curated normals — and if the park has neither, nothing at all.
    private var wx: CuratedWeather {
        if let live { return park.withWeather(live).wx }
        return park.wx
    }

    /// Whether a service has actually answered for this day.
    ///
    /// `park.source == nil` used to be enough — a curated park was assumed to have numbers
    /// because eight of them shipped a written-down August day. There are no bundled
    /// numbers now, so this asks the only question that matters: has a forecast arrived.
    private var hasNumbers: Bool { live != nil || park.wx.isPublished }

    private var light: WeatherLight { WeatherLight(high: wx.hi) }

    /// A dash, not a zero. A park whose forecast has not arrived is not a park at 0°.
    private func value(_ text: @autoclosure () -> String) -> String {
        hasNumbers ? text() : "—"
    }

    /// The five tiles, in the order the slab lays them out.
    ///
    /// Every string here comes off a service or off the bundled record. Where a number has
    /// not arrived the tile shows a dash and its fill stays empty — a tile drawn at zero
    /// is a reading, and "no forecast yet" is not one.
    private var tiles: [WeatherTileModel] {
        [
            WeatherTileModel(
                id: "temp",
                value: value("\(wx.hi)"),
                unit: hasNumbers ? "°F" : "",
                label: live == nil ? "High · bundled normal" : "High \(dayLabel)",
                detail: live?.shortForecast,
                foot: hasNumbers ? "Low \(wx.lo)° overnight" : nil,
                fill: hasNumbers
                    ? .mercury(WeatherScale.fraction(Double(wx.hi), in: WeatherScale.temperature), light.color)
                    : .empty
            ),
            WeatherTileModel(
                id: "uv",
                value: value(wx.uvIndex),
                label: hasNumbers ? "UV · \(wx.uvWord)" : "UV index",
                detail: live?.uvModelled == true
                    ? "Modelled from the sun's angle here — the archive carries no UV."
                    : nil,
                fill: uvValue.map {
                    .scale($0 / WeatherScale.uvCeiling,
                           stops: WeatherScale.uvStops,
                           marks: WeatherScale.uvMarks)
                } ?? .empty
            ),
            WeatherTileModel(
                id: "humidity",
                value: humidity.map { "\($0)" } ?? "—",
                unit: humidity == nil ? "" : "%",
                label: "Humidity",
                detail: humidity == nil
                    ? "No humidity in this park's record — only the live forecast carries one."
                    : "Read at midday.",
                fill: humidity.map { .wave(Double($0) / 100, WeatherScale.water) } ?? .empty
            ),
            WeatherTileModel(
                id: "wind",
                value: windSustained.map { "\(Int($0))" } ?? "—",
                unit: windSustained == nil ? "" : " mph",
                label: windGust == nil ? "Wind" : "Wind · gusts \(Int(windGust!))",
                detail: hasNumbers ? "Highest sustained wind of the day." : nil,
                fill: windSustained.map {
                    .dial($0 / WeatherScale.windCeiling,
                          gust: windGust.map { $0 / WeatherScale.windCeiling },
                          windColor)
                } ?? .empty
            ),
            WeatherTileModel(
                id: "rain",
                value: precip.map { "\($0)" } ?? "—",
                unit: precip == nil ? "" : "%",
                label: "Rain chance",
                detail: precip == nil
                    ? "No chance of rain in this park's record — only the live forecast carries one."
                    : "The likeliest hour of the day, not the whole of it.",
                fill: precip.map { .wave(Double($0) / 100, WeatherScale.water) } ?? .empty
            ),
            WeatherTileModel(
                id: "sun",
                value: value(wx.ss.clockPadded),
                label: sunLabel,
                detail: live?.isNormals == true
                    ? "A ten-year average for this week, not a forecast."
                    : nil,
                foot: hasNumbers ? "First light \(wx.sr.clockPadded)" : nil,
                fill: hasNumbers ? .band(daylightSpent, WP.mark) : .empty
            ),
        ]
    }

    private var uvValue: Double? {
        guard hasNumbers else { return nil }
        return Double(wx.uvIndex)
    }

    /// Wind is rated on its own speed, not on the day's heat: a 40 mph gust is a reason to
    /// turn round whether the afternoon is 60° or 103°.
    private var windColor: Color {
        let peak = windNumbers.max() ?? 0
        if peak >= 35 { return Color(oklch: 0.55, 0.16, 30) }
        if peak >= 20 { return Color(oklch: 0.66, 0.13, 70) }
        return Color(oklch: 0.60, 0.13, 150)
    }

    /// `64%` as published, back to a number the wave can be filled to.
    private var humidity: Int? {
        guard let text = live?.humidity else { return nil }
        return Int(text.filter(\.isNumber))
    }

    /// The day's highest hourly chance of rain. Fetched all along and never shown.
    private var precip: Int? {
        guard let text = live?.precip else { return nil }
        return Int(text.filter(\.isNumber))
    }

    /// `9 mph, gusts 23` — the sustained speed first, the gust as the larger of the two.
    private var windNumbers: [Double] {
        guard hasNumbers else { return [] }
        return wx.wind.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Double.init)
    }

    private var windSustained: Double? { windNumbers.first }
    private var windGust: Double? {
        guard let peak = windNumbers.max(), peak != windSustained else { return nil }
        return peak
    }

    /// Sunrise and sunset, read back into minutes: how long the day is, and — only when
    /// the day is today — how much of it is left to walk in.
    private var daylight: (span: Int, remaining: Int?)? {
        guard hasNumbers,
              let rise = WeatherClock.minutes(wx.sr),
              let set = WeatherClock.minutes(wx.ss),
              set > rise else { return nil }
        guard isToday else { return (set - rise, nil) }
        let now = WeatherClock.minutesIntoToday()
        // Before first light the whole day is still to come. Counted from the clock alone
        // this read "20h 33m left" at midnight — true of the sunset, false of the light,
        // and the tile is about the light.
        guard now > rise else { return (set - rise, set - rise) }
        return (set - rise, max(0, set - now))
    }

    /// The fraction of the day's light already spent. Nil on any day but today, where
    /// there is no "so far" to draw.
    private var daylightSpent: Double? {
        guard let daylight, let remaining = daylight.remaining else { return nil }
        return Double(daylight.span - remaining) / Double(daylight.span)
    }

    /// What is left of the page once the chrome above and below the tiles has had its
    /// share: the section's air, the verdict line, the reading and the source line.
    ///
    /// Taken as a fraction of the page rather than as a constant, so the panel fills an SE
    /// and a Pro Max alike; clamped so a very small display cannot squeeze a tile below
    /// what its two lines of type need, and a very large one cannot stretch six readings
    /// into a poster.
    /// 0.68 rather than 0.72: the page-dots pill floats over the foot of the display, and
    /// the last four points of the source line were reading through it.
    private var slabHeight: CGFloat {
        min(max(ParkScreen.pageHeight * 0.68, 380), 620)
    }

    private var sunLabel: String {
        guard let daylight else { return "Sunset" }
        guard let remaining = daylight.remaining else {
            return "Sunset · \(WeatherClock.span(daylight.span)) of light"
        }
        if remaining == 0 { return "Sunset · dark now" }
        // The day is either still ahead of you or already running; only the second case
        // has an amount "left".
        return remaining == daylight.span
            ? "Sunset · \(WeatherClock.span(daylight.span)) of light"
            : "Sunset · \(WeatherClock.span(remaining)) left"
    }

    /// Which day is being read, and the two controls that change it.
    ///
    /// The date was only ever said in the source line under the tiles and in the label on
    /// the temperature tile, both of them in passing — so a reader stepping through days
    /// had to hunt for what they were looking at.
    /// One control rather than three: the trough the segmented controls are built from,
    /// with the day written across it and a disc lifted onto each end.
    ///
    /// It was two 38pt outlines with the date loose between them, a third of a screen
    /// apart — three objects that had to be read as one thing, and the arrows looked like
    /// chrome rather than the way to change the day.
    private var dayBar: some View {
        HStack(spacing: 6) {
            stepper("chevron.left", by: -1, enabled: offset > 0)
            VStack(spacing: 1) {
                Text(dayTitle).font(WP.headingUI(17))
                if let daySubtitle {
                    Text(daySubtitle).font(WP.body(11)).opacity(0.55)
                }
            }
            .frame(maxWidth: .infinity)
            stepper("chevron.right", by: 1, enabled: offset < Self.horizon)
        }
        .padding(6)
        .frame(height: 56)
        .background(WP.neutral200, in: Capsule())
        .padding(.bottom, 14)
    }

    private func stepper(_ icon: String, by delta: Int, enabled: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { offset += delta }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(WP.mark))
                .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .disabled(!enabled)
        // Faded rather than recoloured: an arrow that has run out of days is the same
        // control, not a different one.
        .opacity(enabled ? 1 : 0.32)
        .accessibilityLabel(delta < 0 ? "Previous day" : "Next day")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayBar

            // Only where there are figures to read it off. Stepping to a day whose forecast
            // has not come back left "Kind — hike any hour" and a green dot standing over
            // six dashes — a verdict on a day the app knows nothing about, which is the one
            // thing this panel is built not to do.
            if hasNumbers {
                HStack(spacing: 9) {
                    Circle().fill(light.color).frame(width: 10, height: 10)
                    Text(light.label).font(WP.bodyItalic(13)).opacity(0.8)
                }
            }

            WeatherSlab(tiles: tiles, selected: $openTile)
                .frame(height: slabHeight)
                .padding(.top, 14)

            Text(hasNumbers ? wx.note : "No forecast has come back for this park yet.")
                .font(WP.bodyItalic(13)).lineSpacing(3).opacity(0.8)
                .padding(.top, 14)

            SourceLine(sourceLine)
                .padding(.top, 16)
        }
        // Keyed on the day as well as the park: this asked for `Date()` regardless, so a
        // trip being planned for next month still read today's forecast.
        .task(id: "\(park.code)|\(WPDate.iso(day))") {
            // Cleared first, or stepping to the next day left the day before's figures on
            // the tiles under the new date until the request came back — the one way this
            // panel can be actually wrong rather than merely empty.
            live = nil
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
        return "Asking Open-Meteo and the National Weather Service for \(dayLabel) at this park — until one answers there is nothing here to read."
    }
}

// MARK: - Stay

struct StaySection: View {
    var park: CuratedPark

    /// The park service's campgrounds, its own pages first.
    ///
    /// They arrived in whatever order NPS returned them. Ordered by who answers for them:
    /// a campground with a page on nps.gov, then one that books on Recreation.gov, then
    /// anything the app can only name. Sorting is stable, so campgrounds with the same
    /// answer keep the park service's own order.
    private var liveCampgrounds: [ParkFacts.Campground] {
        guard case .loaded(let facts) = ParkFacts.shared.state(for: park) else { return [] }
        return facts.campgrounds.enumerated()
            .sorted {
                let (a, b) = (Self.rank($0.element), Self.rank($1.element))
                return a == b ? $0.offset < $1.offset : a < b
            }
            .map(\.element)
    }

    /// Ranked by the pill the row actually draws, not by which links the record happens to
    /// carry.
    ///
    /// Most park-service campgrounds have both an nps.gov page and a Recreation.gov
    /// facility, and `official` prefers the booking link — so ranking on `npsURL` first put
    /// campgrounds wearing a Recreation.gov pill at the top of the NPS group and the list
    /// came out looking unsorted. `facilityID` is tested first here for the same reason the
    /// row tests it first.
    private static func rank(_ camp: ParkFacts.Campground) -> Int {
        if camp.facilityID != nil { return 1 }
        if camp.npsURL != nil { return 0 }
        return 2
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

            // Two bundled lists used to sit here: a hand-written campground list for the
            // eight parks in `curated.json`, and "Lodges & hotels" — four strings a piece,
            // no source, no date, and a nightly rate nobody has checked since it was typed.
            // A price a reader budgets against has to come from somewhere that can be
            // asked again. Both are gone; what is below is fetched every time.
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

    /// Every row on this screen, and who was asked for it. Nothing here ships with the app.
    private var staySource: String {
        "In-park campgrounds and nightly availability from the National Park Service and"
        + " Recreation.gov. Everything under them is Apple Maps, within thirty miles of the"
        + " park, nearest first."
    }
}

// MARK: - Plans

/// When in the day a thing to do suits — read off the park service's own words, never
/// guessed.
///
/// NPS publishes no time-of-day field, so this is a reading of the title and the
/// description: a night-sky programme says "stargazing", a summit hike says "sunrise". Most
/// entries say nothing about time at all, and those get no answer rather than a guessed
/// one. Deciding that a four-hour trail is "morning" would be inventing a fact about a
/// park, which is the one thing this screen must not do.
enum DayPart: String, CaseIterable {
    case morning, afternoon, evening, night

    var label: String { rawValue.capitalized }

    var glyph: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "sunset"
        case .night: return "moon.stars"
        }
    }

    var tint: Color {
        switch self {
        case .morning: return Color(oklch: 0.58, 0.13, 70)
        case .afternoon: return WP.mark
        case .evening: return Color(oklch: 0.55, 0.16, 30)
        case .night: return Color(oklch: 0.46, 0.10, 260)
        }
    }

    /// Nil where the words say nothing about when.
    static func read(_ text: String) -> DayPart? {
        let s = text.lowercased()
        func says(_ words: [String]) -> Bool { words.contains { s.contains($0) } }
        // Night first: "night sky" also contains "sky", and a moonlight walk is an evening
        // word away from being mis-filed.
        if says(["night sky", "stargaz", "star gaz", "astronomy", "after dark",
                 "nocturnal", "moonlight", "milky way", "night hike", "owl prowl"]) { return .night }
        if says(["sunrise", "dawn", "first light", "early morning", "morning"]) { return .morning }
        if says(["sunset", "dusk", "evening", "golden hour", "twilight"]) { return .evening }
        if says(["afternoon", "midday", "mid-day", "noon"]) { return .afternoon }
        return nil
    }
}

struct PlansSection: View {
    var park: CuratedPark

    private var thingsToDo: [ParkFacts.Activity] {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park) { return facts.thingsToDo }
        return []
    }

    private func dayPart(_ activity: ParkFacts.Activity) -> DayPart? {
        DayPart.read(activity.title + " " + (activity.note ?? ""))
    }

    /// One line over the list: which part of the day the park service's own descriptions
    /// keep pointing at, and how much of the list said nothing.
    private var dayPartSummary: String? {
        guard !thingsToDo.isEmpty else { return nil }
        let read = thingsToDo.compactMap(dayPart)
        let silent = thingsToDo.count - read.count
        guard !read.isEmpty else {
            return "None of these say what time of day they suit — the park's own page will."
        }
        let counts = Dictionary(grouping: read, by: { $0 }).mapValues(\.count)
        guard let top = counts.max(by: { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) })
        else { return nil }
        let lead = "\(top.key.label) comes up most — \(top.value) of \(read.count) that name a time."
        return silent == 0 ? lead : "\(lead) The other \(silent) do not say."
    }

    var body: some View {
        // Hand-written day plans used to open this section — "Day 1 in park · Geyser
        // basins", three rows with clock times typed into the record. They shipped for
        // eight parks, and their times were guesses the app could already do better than:
        // the weather panel on this same screen knows the real first light for the date
        // being planned. What the park service publishes covers every park it runs.
        VStack(alignment: .leading, spacing: 14) {

            if !thingsToDo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle("Things to do")
                    if let dayPartSummary {
                        Text(dayPartSummary)
                            .font(WP.bodyItalic(12.5)).lineSpacing(3).opacity(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 6)
                    }
                    ForEach(thingsToDo) { activity in
                        DividedRow(vertical: 11) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(activity.title)
                                        .font(WP.rowTitle(16)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    if let part = dayPart(activity) {
                                        HStack(spacing: 4) {
                                            Image(systemName: part.glyph)
                                                .font(.system(size: 9, weight: .semibold))
                                            Text(part.label).font(WP.body(10))
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(part.tint.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().stroke(part.tint, lineWidth: 0.75))
                                        .foregroundStyle(part.tint)
                                        .fixedSize()
                                    }
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

    private var units: [NearbyUnits.Unit] {
        if case .ready(let units) = NearbyUnits.shared.state(for: park) { return units }
        return []
    }

    /// The ones an afternoon reaches — the window the whole tab is arranged around.
    private var afternoon: [NearbyUnits.Unit] { units.filter(\.isAfternoon) }
    private var closer: [NearbyUnits.Unit] { units.filter { ($0.minutes ?? .max) < 55 } }
    private var further: [NearbyUnits.Unit] {
        units.filter { !$0.isAfternoon && ($0.minutes ?? .max) >= 55 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Everything the park service runs near here that is not another national park — monuments, historic sites, memorials, battlefields — and the state parks around them. A cancellation stamp waits at each park-service visitor centre.")
                .font(WP.body(13)).lineSpacing(3).opacity(0.8)
                .padding(.bottom, 10)

            switch NearbyUnits.shared.state(for: park) {
            case .idle, .loading:
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Asking the park service what else is near \(park.name)…")
                        .font(WP.bodyItalic(12.5)).opacity(0.7)
                }
            case .failed(let why):
                Text(why).font(WP.bodyItalic(12.5)).opacity(0.7).lineSpacing(3)
            case .ready:
                group("Under an hour", closer)
                group("An afternoon away · 1–1½ hours", afternoon, highlight: true)
                group("Further out", further)
            }

            SourceLine("Units from the National Park Service, state parks from the table on this phone. Drive times from OSRM for the nearest ten; the rest are straight-line miles.")
                .padding(.top, 16)
        }
        .task(id: park.code) { NearbyUnits.shared.load(park) }
    }

    /// One band of the list. Empty bands say nothing rather than showing a bare heading.
    @ViewBuilder
    private func group(_ title: String, _ rows: [NearbyUnits.Unit], highlight: Bool = false) -> some View {
        if !rows.isEmpty {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(WP.body(11)).tracking(1.3)
                    .foregroundStyle(highlight ? WP.mark : WP.accent700)
                Rectangle().fill(WP.divider).frame(height: 1)
            }
            .padding(.top, 14)
            .padding(.bottom, 2)

            ForEach(rows) { unit in
                Button {
                    app.sheet = .stamp(name: unit.name, city: unit.place, dist: unit.distanceLine)
                } label: {
                    DividedRow(vertical: 12) {
                        HStack(spacing: 12) {
                            Text(unit.distanceLine)
                                .font(WP.body(12)).tnum()
                                .foregroundStyle(unit.isAfternoon ? WP.mark : WP.accent700)
                                .frame(width: 82, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                Text("\(unit.place) · \(unit.designation)")
                                    .font(WP.bodyItalic(11.5)).opacity(0.6)
                            }
                            Spacer(minLength: 0)
                            if !unit.isStatePark, app.isStamped(app.stampKey(forName: unit.name)) {
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

    /// The campground's own page on Recreation.gov. Only the facilities that book there
    /// have an id, so a concessioner-run campground gets no link rather than a wrong one.
    private var bookingLink: URL? {
        camp.facilityID.flatMap { URL(string: "https://www.recreation.gov/camping/campgrounds/\($0)") }
    }

    /// A first-come campground is listed on Recreation.gov without being bookable there.
    /// Longs Peak has a facility page and no calendar; "Book" would be a promise the page
    /// does not keep.
    private var bookingLabel: String {
        guard let id = camp.facilityID else { return "View on Recreation.gov" }
        if case .notBookable = Recreation.shared.state(facility: id) {
            return "View on Recreation.gov"
        }
        return "Book on Recreation.gov"
    }

    /// Where this campground's official page lives.
    ///
    /// Recreation.gov when it books there, and the park service's own page when it does
    /// not — which is most of the first-come campgrounds, the ones a reader most needs to
    /// go and read about. One pill either way: the errand is the same.
    private var official: (url: URL, title: String, glyph: String)? {
        if let url = bookingLink { return (url, bookingLabel, "tent.fill") }
        if let url = camp.npsURL { return (url, "View on NPS.gov", "leaf.fill") }
        return nil
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

                // The panel counts the free sites and then left you to find the booking
                // page yourself. A facility id *is* the Recreation.gov page — the same id
                // the availability above was read from — so the row can just open it.
                if let official {
                    Link(destination: official.url) {
                        HStack(spacing: 7) {
                            Image(systemName: official.glyph)
                                .font(.system(size: 11, weight: .semibold))
                            Text(official.title)
                                .font(WP.body(12, semibold: true))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(WP.text)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(WP.book, in: Capsule())
                        // The pill is 32 points tall so it sits inside the row rather than
                        // dominating it; the target around it is the full 44.
                        .contentShape(Capsule())
                        .padding(.vertical, 6)
                    }
                    .accessibilityLabel("\(official.title) — \(camp.name)")
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

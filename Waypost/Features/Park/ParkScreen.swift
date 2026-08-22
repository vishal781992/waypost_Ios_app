import SwiftUI
import UIKit

/// One park, pushed over whatever opened it. The web app's six in-park tabs become one
/// screen with a scrolling segment rail.
struct ParkScreen: View {
    @Environment(AppState.self) private var app
    /// The chips open a website, a phone number and Apple Maps; only the first two are URLs.
    @Environment(\.openURL) private var openURL
    var park: CuratedPark
    var initialSegment: ParkSegment
    /// The day this park is being read for — a trip's arrival date. Nil means today.
    var date: Date?

    @State private var segment: ParkSegment = .brief
    /// Bumped by a tap on the section already showing. A counter rather than a flag, so
    /// the second tap in a row is still a change the scroll view can observe.
    @State private var scrollTopRequests = 0
    /// Which way the next page comes in from.
    @State private var forward = true
    /// Where the in-flow rail is on the display, and the line it turns into a header at.
    @State private var railTop: CGFloat = .greatestFiniteMagnitude
    /// Parts of the current section that do their own sideways scrolling.
    @State private var swipeBlocks: [CGRect] = []
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

    /// The page header: one row, for the title and the way back. It was two — the second
    /// held the discs, which are frozen to the foot of the display now.
    static let barHeight: CGFloat = 46 + 8

    /// The status bar's height. Asked of the window rather than of a `GeometryReader`:
    /// this screen's scroll view ignores the top safe area, and the proxy inside it
    /// reports zero — which put the pinned header under the clock.
    static var statusBarInset: CGFloat { WP.statusBarInset }

    private var packState: PackState { app.packState(park.code) }
    private var isSaved: Bool { app.saved.contains(park.code) }

    /// What the offline-pack control says, in the width one quarter of a row leaves it.
    ///
    /// `park.pack` is a size for the eight bundled parks and the words "Not downloaded"
    /// for everywhere else, which is a sentence this pill has no room for — and one that
    /// only repeats what an un-pressed download control already says.
    private var packLabel: String {
        switch packState {
        case .ready: return "On device"
        case .busy: return "\(Int((app.packProgress[park.code] ?? 0) * 100))%"
        case .none: return park.pack.first?.isNumber == true ? "Offline · \(park.pack)" : "Offline pack"
        }
    }

    /// Whether this park is already on the visited rail — stamped on the ground, written
    /// into a trip that has been, or added here by hand.
    private var hasVisited: Bool { app.visitRail.contains { $0.id == park.code } }

    /// Whether the reader is being asked to confirm taking this park off the rail.
    @State private var confirmingUnvisit = false

    /// "I have been here", as a disc in the mark's orange.
    ///
    /// This was a word in a pill that turned into a settled, untappable state once the
    /// park was on the rail — which meant a mistaken tap could only be undone from the
    /// Profile screen, if at all. It is a toggle now: filled seal for a fact, hollow seal
    /// for the offer, and taking it back asks first, because it is the one control here
    /// that erases something the reader told the app.
    private var visitButton: some View {
        Button {
            if hasVisited { confirmingUnvisit = true } else { app.addVisit(park.code) }
        } label: {
            Image(systemName: hasVisited ? "checkmark.seal.fill" : "checkmark.seal")
                .font(.system(size: 19, weight: .medium))
                .frame(width: 46, height: 46)
                .markControl()
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(hasVisited
                            ? "Visited. Remove \(park.name) from your visited list"
                            : "Mark \(park.name) as visited")
        .confirmationDialog("Remove from visited?", isPresented: $confirmingUnvisit, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { app.removeVisit(park.code) }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("\(park.name) comes off your visited rail. Tap visited again to put it back.")
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
            // The labels are this app's own words, not the park service's — the screen
            // knows it is about to show a fee and an opening time before it asks anybody.
            // So the wait is drawn in the shape of the answer: both labels, and a pending
            // line under each, the hours slot holding the three lines they usually run to.
            //
            // This was one twenty-point spinner line, and the loaded row is two stacked
            // facts — so the moment NPS answered, the chips, the caption and everything
            // below them dropped about ninety points, out from under whatever your thumb
            // was already reaching for. Reserving the height does not make the request any
            // faster. It stops the page moving while it runs.
            VStack(alignment: .leading, spacing: 11) {
                awaitedFact("Entrance fee", reservingLines: 1)
                awaitedFact("Park hours", reservingLines: 3)
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

    /// One fact still in flight, holding the space its answer will want.
    ///
    /// `reservesSpace` takes the height from the font rather than from a number measured
    /// once on one phone, so the reservation stays right at every Dynamic Type size and
    /// cannot drift when the type scale changes underneath it.
    ///
    /// A pending field says it is pending. "Asking the park service…" is the sentence the
    /// reservation note below already uses for the same state, and the app is careful
    /// everywhere else to keep a question in flight apart from an answer that came back
    /// empty — a blank slot here would read as the second when it is the first.
    private func awaitedFact(_ label: String, reservingLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(WP.body(10)).tracking(1.4)
                .foregroundStyle(WP.accent800)
            Text("Asking the park service…")
                .font(WP.bodyItalic(12.5)).opacity(0.55).lineSpacing(2)
                .lineLimit(reservingLines, reservesSpace: true)
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
    ///
    /// Three chips on one line, where this was four full-width boxes stacked — 230 points
    /// of the page for three links and a clock, which is more than the photograph gets
    /// after the fold. Two of those boxes were not even controls: the park's clock and its
    /// gateway town are facts, and they read better as the caption they now are.
    /// Equal shares of the row rather than equal gaps.
    ///
    /// Spread by spacers, three chips of three different widths left two gaps of two
    /// different sizes — the arithmetic was uniform and the page was not. Every chip is
    /// an equal share of the row now, so the gaps are equal because the chips are, and
    /// the width that was idle went to the park service's own road in.
    @ViewBuilder
    private var contactChips: some View {
        let items = contactChipItems
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button(action: item.open) { chip(glyph: item.glyph, text: item.label) }
                        .buttonStyle(PressStyle(scale: 0.97))
                        .accessibilityLabel(item.spoken)
                }
            }
            .padding(.top, 12)
        } else if isFindingContacts {
            // Every chip on this row comes from a lookup that has not answered yet, so the
            // row is empty and then, a moment later, forty-eight points tall — with the
            // caption and the whole overview under it moving down to make room. How many
            // chips arrive is not knowable in advance (a park may have a site, a number,
            // both or neither), so nothing is drawn here: only the height one row of them
            // takes is held, which is the same whether one chip lands or four.
            //
            // Fixed height rather than a minimum: `Color` is flexible in both directions,
            // and a flexible child in this column would be handed the slack instead of the
            // thirty-six points asked for.
            Color.clear
                .frame(height: 36)
                .padding(.top, 12)
                .accessibilityHidden(true)
        }
    }

    /// Whether the lookups behind the chip row are still out.
    ///
    /// Only Apple Maps is asked about: the website, the phone number and the map item all
    /// arrive together from that one lookup, and the park service's directions chip is an
    /// extra that may never come. Once Maps has answered — with a place or with nothing —
    /// this row is as full as it is ever going to be.
    private var isFindingContacts: Bool {
        switch ParkWebsite.shared.state(for: park) {
        case .idle, .looking: return true
        case .found, .none: return false
        }
    }

    /// Somewhere this screen can hand the park off to.
    private struct ContactChip: Identifiable {
        let id: String
        let glyph: String
        let label: String
        /// What VoiceOver says, which is longer than the word on the chip — "Call" alone
        /// does not say who is being called or on what number.
        let spoken: String
        let open: () -> Void
    }

    private var contactChipItems: [ContactChip] {
        let details = ParkWebsite.shared.details(for: park)
        var items: [ContactChip] = []

        if let site {
            // A park with no NPS fee has nothing above this but "Not published", so the
            // chip names what the site is for rather than what it is.
            items.append(ContactChip(id: "site",
                                     glyph: "safari",
                                     label: liveFee == nil ? "Fees" : "Park site",
                                     spoken: "Open the park's own website") { openURL(site) })
        }

        if let phone = details?.phone,
           let dial = URL(string: "tel://" + phone.filter { $0.isNumber || $0 == "+" }) {
            items.append(ContactChip(id: "call",
                                     glyph: "phone",
                                     label: "Call",
                                     spoken: "Call the park on \(phone)") { openURL(dial) })
        }

        if let details {
            items.append(ContactChip(id: "maps",
                                     glyph: "map",
                                     label: "Maps",
                                     spoken: "See \(park.name) in Apple Maps") { details.mapItem.openInMaps() })
        }

        // The park service's own written approach, which the app has always had and never
        // shown. Absent until the facts arrive, and for the few parks NPS writes none for.
        if let directions = facts?.directions, !directions.isEmpty {
            // "Directions" is the accurate word and two characters too many for a quarter
            // of the row — it truncated to "Directi…" on a 402pt phone.
            items.append(ContactChip(id: "directions",
                                     glyph: "signpost.right",
                                     label: "Drive in",
                                     spoken: "How to drive in to \(park.name)") {
                app.sheet = .directions(park: park.name, text: directions)
            })
        }

        return items
    }

    /// The park's own website, if the finder has one for it.
    private var site: URL? {
        if case .found(let url) = ParkWebsite.shared.state(for: park) { return url }
        return nil
    }

    /// The park's own clock, in the italic the page uses for asides.
    ///
    /// Drawn only when the park keeps a different one from the phone — the hours above
    /// and the sunrise in the weather section are the park's, not yours, and that is
    /// worth a line only when the two disagree.
    ///
    /// The gateway town stood here too and no longer does: which town you pass through
    /// is a fact about a drive, and the drive is what the trip screens are for.
    @ViewBuilder
    private var contactCaption: some View {
        if let zone = ParkWebsite.shared.details(for: park)?.timeZone,
           zone.identifier != TimeZone.current.identifier {
            Text("Park time \(Self.clock(in: zone)) · \(zone.abbreviation() ?? zone.identifier)")
                .font(WP.bodyItalic(12.5))
                .opacity(0.62)
                .padding(.top, 9)
        }
    }

    /// One link, as a word in a hairline capsule. Black rather than the park-service brown
    /// the boxed rows used: at chip size the brown on the page's off-white is thin, and
    /// these sit a line below four filled dark pills that would swamp it.
    private func chip(glyph: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
                .font(.system(size: 12.5, weight: .semibold))
            Text(text)
                .font(WP.body(12.5))
                .lineLimit(1)
                // A quarter of a 320pt phone is 64 points, and "Park site" wants 70 of
                // them. Shrinking is the graceful failure; truncating to "Park si…" is not.
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(WP.text)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background { Capsule().stroke(WP.text.opacity(0.18), lineWidth: 1) }
        .contentShape(Capsule())
    }

    private static func clock(in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date())
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

                        // The rail itself is welded to the foot of the display now; what
                        // stands here is the line it used to occupy — where a picked
                        // section scrolls back to, and the line whose passing off the top
                        // turns the page into a page of its own.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.railAnchor)
                            .modifier(TracksTopEdge { railTop = $0 })

                        section
                            .padding(.horizontal, WP.gutter)
                            .padding(.top, Self.sectionTop)
                            .padding(.bottom, WP.tabBarClearance)
                            // Pinned to the width of the scroll view, so nothing inside a
                            // section can ever make the *page* wider than the phone.
                            //
                            // One `HStack` that cannot fit — a booking pill beside two
                            // controls, a long park name beside a chip — used to widen this
                            // whole column, and because the column is laid out leading in a
                            // wider frame, every other line on the screen shifted left with
                            // it. The symptom appeared nowhere near the cause: a masthead
                            // reading "ATIONAL PARK" at the top of the page, and the whole
                            // screen sliding sideways under a thumb like a web page.
                            // Individual rows still wrap properly; this is the backstop for
                            // the ones that have not been taught to, on a narrower phone or
                            // at a text size nobody tested.
                            .containerRelativeFrame(.horizontal)
                            // Every section is at least a screen tall, so a short one —
                            // weather is six figures and a line — can still be scrolled
                            // into the pinned state the long ones reach.
                            .frame(minHeight: Self.pageHeight, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .captureScrollPosition()
                // Frozen to the floor rather than carried by the page. As an inset rather
                // than an overlay, so the scroll view holds its own last line clear of the
                // rail instead of every section having to pad for it by hand.
                .safeAreaInset(edge: .bottom, spacing: 0) { frozenRail }
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
                // The top of the section, not the top of the park. Re-tapping the rail
                // means "take me back to the start of what I am reading" — the same place
                // changing section lands you, so the rail has one destination rather than
                // two that depend on which section was showing when you pressed it.
                .onChange(of: scrollTopRequests) { _, _ in
                    withAnimation(.snappy(duration: 0.34)) {
                        scroller.scrollTo(Self.railAnchor, anchor: .top)
                    }
                }
            }

                // Back floats over the photograph until the bar takes the job over.
                backControl.opacity(railFade)

                pinnedBar
                    .opacity(barFade)
                    .allowsHitTesting(pinned > 0.5)
        }
        .coordinateSpace(name: Self.pageSpace)
        .simultaneousGesture(pageTurn)
        .onPreferenceChange(RailTopKey.self) { railTop = $0 }
        .onPreferenceChange(PageTurnBlockKey.self) { swipeBlocks = $0 }
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

    /// The six sections, welded to the foot of the display.
    ///
    /// It used to ride the page and hand itself over to a copy in the header on the way
    /// past the top — which meant the one control the screen is navigated by was somewhere
    /// off the top of it for most of a long section, and in two places during the swap.
    /// Frozen, it is in one place, always, and that place is the end of the display a
    /// thumb actually reaches.
    /// A capsule of ink glass, floating, with the page running past it either side —
    /// the same material every button on this screen is made of, and the same shape
    /// language as the app's own tab bar. A hairline plate read as the last row of the
    /// page; this reads as chrome laid over it, which is what it is.
    private var frozenRail: some View {
        VStack(spacing: 0) {
            // The soft zone above the capsule. Empty of itself — what fills it is the
            // blurred page, in the background below.
            Color.clear
                .frame(height: 34)
                .allowsHitTesting(false)

            SegmentDiscRail(options: railOptions, selection: segmentBinding, onInk: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlass(.control, radius: 999)
                .shadow(color: Color(hex: 0x181008, opacity: 0.22), radius: 12, y: 6)
                .padding(.horizontal, WP.gutter)
            // Down in the home indicator's clearance, but not all the way down it. At -10
            // the bottom of every disc sat inside the strip iOS reserves for the home
            // gesture, which takes the first touch and gives the app the second — so a
            // deliberate tap on a disc missed about half the time.
                .padding(.top, 4)
                .padding(.bottom, -4)
        }
        // The page goes soft as it reaches the bar rather than being cut off at a line.
        //
        // A plain wash of page colour did hide the type, but it hid it abruptly: chips
        // were sliced across their middles and what was left below read as a dead band.
        // Frosted glass instead, masked so it is nothing at the top and full at the
        // bottom — words lose their edges over thirty points, and the last of the colour
        // takes what is left. Behind the capsule and down past the home indicator it is
        // opaque, so nothing survives in the strip under the bar.
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [WP.bg.opacity(0), WP.bg.opacity(0.55), WP.bg],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.55), location: 0.28),
                        .init(color: .black, location: 0.62),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// The line the rail used to stand on: what a picked section scrolls back to.
    private static let railAnchor = "park-sections"

    /// The rail's own height: a 44pt disc with 14 above it and 10 below.
    /// The frozen bar's own height: a 44pt disc with 12 above it and 4 below.
    private static let railHeight: CGFloat = 60

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
                // Tapping the section you are already reading used to be swallowed here.
                // A rail that answers nothing is a rail that looks broken from the foot of
                // a long page, so the same tap now does what the same tap does everywhere
                // else on iOS: takes you back to the top of what you are reading.
                guard new != segment else {
                    scrollTopRequests += 1
                    Haptics.tap()
                    return
                }
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
    /// The space the page turn and the regions that opt out of it are both measured in.
    static let pageSpace = "park-page"

    private var pageTurn: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named(Self.pageSpace))
            .onEnded { drag in
                guard drag.startLocation.x > 32 else { return }
                // A drag that began on something which scrolls sideways belongs to it.
                guard !swipeBlocks.contains(where: { $0.contains(drag.startLocation) }) else { return }
                let across = drag.translation.width
                guard abs(across) > 48, abs(across) > abs(drag.translation.height) * 1.4 else { return }
                let all = ParkSegment.allCases
                guard let here = all.firstIndex(of: segment) else { return }
                let next = here + (across < 0 ? 1 : -1)
                guard all.indices.contains(next) else { return }
                segmentBinding.wrappedValue = all[next]
            }
    }

    /// The page header: the section's name and the way back, once the page has been
    /// scrolled far enough to be a page of its own.
    ///
    /// It carried a second copy of the rail. With the rail frozen at the foot of the
    /// display that copy would be the same six discs twice on one screen, so the header
    /// is now one row — a name and a chevron — and it is 42 points shorter for it.
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
            .padding(.bottom, 8)

            Hairline()
        }
        // No top padding: the ZStack already places this below the status bar, and adding
        // the inset again put the header a second status bar down the screen. Only the
        // plate behind it runs up under the clock.
        .background {
            Rectangle().fill(WP.bg).ignoresSafeArea(edges: .top)
        }
    }

    // The six dots that used to float above the fold said which page of six this was —
    // worth having while the rail was off the top of the screen. The rail is on the
    // screen at all times now, and it says the same thing with the sections named.

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
    private var backControl: some View { FloatingBack(label: "Back") { app.pop() } }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Four errands, one line. They were two rows of two, which put a whole row of
            // controls between the photograph and the first sentence about the park.
            //
            // Saving and having-been are the two a symbol says as well as a word does — a
            // bookmark and a seal — so they become 46pt discs in the two brand colours and
            // hand their width to the two that need a sentence. Both discs carry an
            // accessibility label, because an icon-only control has nothing to read out.
            HStack(spacing: 8) {
                Button { app.toggleSaved(park.code) } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 46, height: 46)
                        .limeControl()
                }
                .buttonStyle(PressStyle(scale: 0.94))
                .accessibilityLabel(isSaved ? "Remove \(park.name) from saved" : "Save \(park.name)")

                Button { app.startPack(park.code) } label: {
                    Text(packLabel)
                        .font(WP.headingUI(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .glassControl()
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .accessibilityLabel(packState == .ready ? "Offline pack on device"
                                    : "Download the offline pack for \(park.name)")

                Button { app.startBuilder(around: park) } label: {
                    Text("Plan a trip")
                        .font(WP.headingUI(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .glassControl()
                }
                .buttonStyle(PressStyle(scale: 0.98))

                visitButton
            }

            factsRow.padding(.top, 13)
            contactChips
            // A park in your own time zone has nothing to say here, and says nothing.
            contactCaption
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
                    AlertDisclosureRow(alert: alert)
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
                //
                // One line of chips rather than three lists stacked. Fifteen rows of
                // somewhere-to-plug-in sat between the alerts and the campgrounds — the
                // two things this page is actually read for — and most visits only need
                // to know a charger exists and roughly how far it is, which is what the
                // chip says without being opened. The last shop before the gate is in
                // here too, which is the reason a camper opens this screen at all.
                PlaceCategoryChips(park: park, kinds: [.charger, .fuel, .store])
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

    /// The rail's reach, in days either side of the day the screen was opened on.
    ///
    /// Sixty back and sixty on. Forward of about a fortnight the numbers stop being a
    /// forecast and become the same calendar week averaged over ten years — which is the
    /// honest answer to "what is October like here", and which the source line under the
    /// tiles names for whichever day is being read. Backwards they are the archive: what
    /// the weather actually did, which is what a reader asks when they are looking at
    /// photographs of a trip they have already taken.
    private static let reach = 60
    private static let window = Array(-reach...reach)

    /// The high for a day, by ISO date, as each disc gets an answer. Kept for the whole
    /// visit: scrolling the rail back and forth must not ask twice.
    @State private var highs: [String: Int] = [:]

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

    /// Four months of days, as discs coloured by what the day is going to be like.
    ///
    /// Two arrows and a date used to be the whole control, five days deep — which answers
    /// "what is it doing tomorrow" and refuses the question the panel is actually opened
    /// with, which is "which day should I go". A season laid out in a rail answers that in
    /// one look: the run of green is when to come, and the reader scrolls to it rather
    /// than tapping an arrow forty times to find out it was August all along.
    private var dayStrip: some View {
        ScrollViewReader { rail in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 7) {
                    ForEach(Self.window, id: \.self) { step in
                        dayPill(step)
                            .id(step)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            // The day being read starts in the middle of the display rather than at its
            // left edge: a rail that opens on the first of sixty days looks like a rail
            // with nothing behind it.
            .onAppear { rail.scrollTo(offset, anchor: .center) }
            .onChange(of: offset) { _, new in
                withAnimation(.snappy(duration: 0.28)) { rail.scrollTo(new, anchor: .center) }
            }
        }
        // Or a drag along the dates turns the page instead — which it did, two sections
        // at a time, while the rail scrolled underneath.
        .keepsHorizontalDrags()
        .padding(.bottom, 14)
    }

    /// One day: the date in a disc the colour of its high, the month underneath.
    private func dayPill(_ step: Int) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: step, to: base) ?? base
        let iso = WPDate.iso(date)
        let high = highs[iso]
        let band = high.map { WeatherLight(high: $0) }
        let selected = step == offset
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { offset = step }
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(WP.headingUI(15))
                    // On a filled disc the type is the fill's own dark end; on an
                    // unanswered one it is the page's ink at half strength, which is how
                    // the rest of the app draws a figure it has not got yet.
                    .foregroundStyle(selected ? .white : (band == nil ? WP.text.opacity(0.5) : WP.text))
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(selected ? (band?.color ?? WP.ink)
                                               : (band?.color.opacity(0.26) ?? WP.neutral200))
                    }
                    .overlay {
                        if selected { Circle().stroke(WP.text.opacity(0.85), lineWidth: 2).padding(-3) }
                    }

                Text(isToday ? "TODAY" : date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(WP.body(9.5)).tracking(0.6)
                    .foregroundStyle(isToday ? WP.text : WP.text.opacity(0.55))
            }
            .frame(width: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(high.map { "High \($0) degrees" } ?? "No reading yet")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        // Each disc asks for its own day the first time it is scrolled into being, and
        // never again — `quickForecast` is the one-call version, because sixty discs
        // wanting the blended three-source answer is sixty times the traffic for a colour.
        //
        // It only answers inside the forecast window, which is a fortnight. Outside it —
        // a week in October, a day last month — the fallback is the same calendar window
        // averaged over ten years. That is not a forecast and the panel below says so for
        // whichever day is picked; as a colour on a disc it is the honest one, because the
        // question a rail this long is scrolled with is what October is like here.
        .task(id: iso) {
            guard highs[iso] == nil else { return }
            let weather = WeatherService(failures: FailureLog())
            if let day = await weather.quickForecast(lat: park.lat, lon: park.lon, iso: iso) {
                highs[iso] = day.hi
            } else if let normal = await weather.normals(lat: park.lat, lon: park.lon, iso: iso) {
                highs[iso] = normal.hi
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayStrip

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


/// One posted alert: its category, its title, and its text when you ask for it.
///
/// The park service writes these at whatever length it likes, and a park in fire season
/// posts five of them. Printed in full they were most of the Overview — the reader scrolled
/// past a paragraph about propane stoves to reach the entry gates. The tag and the title
/// are what triage a list; the body is what you read once you have found the one that
/// matters, so the body is what waits.
///
/// The severity tag never collapses. Red for a danger or a closure, amber for a caution,
/// green for an information notice — that is the whole point of the row and it has to
/// survive being shut.
private struct AlertDisclosureRow: View {
    var alert: CuratedAlert

    @State private var isOpen = false

    var body: some View {
        let tone = AlertSeverity(category: alert.cat).color

        Button {
            withAnimation(Motion.panel) { isOpen.toggle() }
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
                        // The same chevron, turned rather than swapped: down means the
                        // text is below, right means it is still folded away.
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WP.accent700)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }

                    Text(alert.title)
                        .font(WP.rowTitle(17))
                        .multilineTextAlignment(.leading)
                        // Shut, the title is the only thing in the stack and SwiftUI gave
                        // it a single line — "Heat Alert - Temperatures May Be Higher Th…".
                        // It wrapped correctly only while the body was under it, which is
                        // exactly the state this row now spends most of its life outside of.
                        .fixedSize(horizontal: false, vertical: true)

                    if isOpen {
                        Text(alert.body)
                            .font(WP.body(12.5)).lineSpacing(2).opacity(0.75)
                            .multilineTextAlignment(.leading)
                            .transition(.opacity)
                    }
                }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .accessibilityLabel("\(alert.cat). \(alert.title)")
        .accessibilityValue(isOpen ? alert.body : "")
        .accessibilityHint(isOpen ? "Collapses the notice" : "Expands the notice")
    }
}

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



/// The one control that takes a reader off this app and onto the page that can actually
/// book them a site.
///
/// Lifted out of the park screen's campground row so the trip's Stays list can carry the
/// same pill rather than a second one drawn to look like it. The errand is identical on
/// both screens — "open the official page for this campground" — so it is one view.
struct CampgroundOfficialLink: View {
    var camp: ParkFacts.Campground

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

    var body: some View {
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
                            // "Checking…" is one short word and "First-come, no calendar"
                            // is four; left to compress against a long campground name the
                            // chip wrapped to two lines when the answer landed and took the
                            // row's height with it. The chip holds its own width and the
                            // name, which can wrap without changing what it says, gives.
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
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
                // Wraps rather than overflows.
                //
                // "Book on Recreation.gov" is a wide pill, and beside the add and
                // directions controls the row came to more than the width of the phone. An
                // `HStack` does not wrap — it overflowed, and because the column is laid
                // out `maxWidth: .infinity` the whole *page* shifted left to accommodate
                // it. That is why the masthead read "ATIONAL PARK" with the N off the
                // screen and the screen slid sideways under a finger like a web page.
                FlowRow(spacing: 9, rowSpacing: 8) {
                    CampgroundOfficialLink(camp: camp)
                    // A campground is a place like any other: on a park opened from a trip
                    // it can go on that trip's list, and from anywhere else it cannot.
                    if let lat = camp.lat, let lon = camp.lon {
                        PlaceRowActions(place: PlannedPlace(
                            name: camp.name,
                            subtitle: [camp.fee, camp.sites.map { "\($0) sites" }]
                                .compactMap { $0 }.joined(separator: " · "),
                            lat: lat, lon: lon,
                            category: PlacesService.Kind.campground.rawValue
                        ), day: nil)
                    }
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

/// Regions of a section that scroll sideways themselves, and must not have their drags
/// read as a page turn.
///
/// The page is turned by dragging across it, which was unambiguous while nothing inside a
/// section scrolled horizontally. The weather rail does, and a drag along it both scrolled
/// the dates and threw the reader two sections along.
struct PageTurnBlockKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marks this view as scrolling sideways on its own account. Drags that begin inside
    /// it are the view's, not the page's.
    func keepsHorizontalDrags() -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: PageTurnBlockKey.self,
                                       value: [geo.frame(in: .named(ParkScreen.pageSpace))])
            }
        }
    }
}

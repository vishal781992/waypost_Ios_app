import MapKit
import SwiftUI

/// A trip, opened. Route / Days / Stays — the web app's single long scroll, split three
/// ways so each answers one question.
struct TripDetailScreen: View {
    @Environment(AppState.self) private var app
    var trip: SavedTrip

    @State private var segment: TripSegment = .route
    /// Whether the "this drive has no stops on it" question is showing.
    @State private var confirmingBareDrive = false

    private var parks: [CuratedPark] { trip.codes.compactMap { app.park($0) } }
    private var isSeed: Bool { trip.id == "seed" }

    var body: some View {
        // The route runs to the very top of the display, under the status bar, so opening a
        // trip keeps the picture that was tapped to get here rather than replacing it with
        // a header. Only the scroll view ignores the safe area; back floats inside it.
        ZStack(alignment: .topLeading) {
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                // Pinned section headers, so the control stays on the display once the page
                // has scrolled past it. Choosing a section and then having to scroll back up
                // to choose another is the fault this fixes.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    hero

                    // The gutter belongs to the page, not to the hero — so everything
                    // below the map is inset together and the map alone runs full bleed.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(trip.tag).kickerStyle()
                        Text(trip.title).font(WP.display(34)).padding(.top, 7)
                            .multilineTextAlignment(.leading)
                        Text(trip.route).font(WP.bodyItalic(12.5)).opacity(0.65).padding(.top, 5)

                        statLine.padding(.top, 13)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WP.gutter)

                    Section {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            switch segment {
                            case .route: routeList
                            case .days: dayList
                            case .list: TripPlanList(trip: trip)
                            }
                        }
                        .padding(.top, 20)
                        .panelTransition(id: segment)

                        // Share is a disc now, and it floats. Full width at the foot of the
                        // scroll it was the largest thing on the screen and the last thing
                        // anybody wanted — on a trip with a fortnight of days it also sat
                        // below all of them. See `shareDisc`.
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WP.gutter)
                    } header: {
                        SegmentedTrough(options: TripSegment.allCases.map { ($0, $0.label) },
                                        selection: $segment)
                            .padding(.horizontal, WP.gutter)
                            // Room for the back control above it. A pinned header stops at
                            // the top of what the scroll view can see, and `FloatingBack`
                            // floats in the same place — so pinned, the two were in each
                            // other's way, with the clock over both of them.
                            .padding(.top, Self.pinnedTop)
                            .padding(.bottom, 12)
                            // Opaque, or the page scrolls through the pinned control.
                            .background(WP.bg)
                            .id(Self.segmentAnchor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Only Route still has a disc floating over it. The other two carry a frozen
                // footer, and `safeAreaInset` insets the scroll by its height for them.
                .padding(.bottom, segment == .route ? 82 : WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .captureScrollPosition()
            // Frozen to the floor on the two tabs that end in an action. `safeAreaInset`
            // also pads the scrolling content by the strip's height, so the last row still
            // clears it — and a control welded to the floor is one a thumb can find
            // without scrolling to the end of a fortnight of days to reach it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                switch segment {
                case .list: listFooter
                case .days: if !plannedDaysList.isEmpty { calendarFooter }
                case .route: EmptyView()
                }
            }
            // Route has no action of its own, so there the disc floats over the page and
            // stays where it is while the page moves under it.
            .overlay(alignment: .bottomTrailing) {
                if segment == .route {
                    shareDisc
                        .padding(.trailing, WP.gutter)
                        .padding(.bottom, 18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Motion.panel, value: segment)
            // Choosing a section puts its first line under the control rather than leaving
            // it below the fold. The same move the park screen's rail makes, at the same
            // speed — `.snappy(duration: 0.34)`, transcribed rather than re-chosen.
            .onChange(of: segment) { _, _ in
                withAnimation(.snappy(duration: 0.34)) {
                    scroller.scrollTo(Self.segmentAnchor, anchor: .top)
                }
            }
            }

            topFrost

            // No padding here. `FloatingBack` carries its own, which is the only way the
            // two screens can be guaranteed to put it in the same place.
            FloatingBack(label: "Trips") { app.pop() }
        }
        .background(WP.bg)
        .onAppear {
            segment = app.tripSegment[trip.id] ?? .route
            if isSeed {
                // The seed trip carries its own legs from Denver onwards, so the only one
                // missing is the drive from wherever the traveller is right now. A composed
                // trip starts from the origin it was planned with, and `route` already
                // draws that leg — asking for an approach leg too added a second, contra-
                // dictory "Getting there" row measured from the device.
                if let first = parks.first {
                    app.routing.routeApproach(trip, to: first)
                }
            } else {
                app.routing.route(trip, parks: parks, origin: trip.resolvedOrigin(app.library))
            }
        }
        .onChange(of: segment) { _, new in app.tripSegment[trip.id] = new }
        // The days are laid out over the legs, so they wait for the router. `legs` lands
        // once and this fires once; `build` returns early if it has already run.
        .onChange(of: app.routing.legs(for: trip).count) { _, _ in
            TripDays.shared.build(trip, parks: parks, legs: app.routing.legs(for: trip))
        }
        .task(id: trip.id) {
            TripDays.shared.build(trip, parks: parks, legs: app.routing.legs(for: trip))
        }
        // Not at launch, and not once: the calendar changes while the app is open, and the
        // days this asks about are not known until the router and the composer have both
        // finished. `TripCalendar` does nothing without full access and nothing twice over
        // the same stretch, so re-running this is cheap.
        .task(id: calendarKey) {
            guard app.checksCalendar else { return }
            TripCalendar.shared.readAccess()
            let days = plannedDaysList.compactMap(\.date)
            guard !days.isEmpty else { return }
            await TripCalendar.shared.look(over: [trip.id: days])
        }
    }



    /// Sharing, as one disc in the mark's orange.
    ///
    /// The same control wherever it sits: welded beside *drive it* on My list, floating over
    /// the page on the other two. A trip is shared once and read many times, so it is the
    /// smaller of the two things you can do with one.
    private var shareDisc: some View {
        Button {
            app.show("Sharing sends a read-only copy")
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                // The glyph's own weight sits it low in its box; lifting it centres the
                // arrow in the disc rather than the box that contains it.
                .offset(y: -1)
                .frame(width: 52, height: 52)
                .background(Circle().fill(WP.mark))
                .shadow(color: Color(hex: 0x181008, opacity: 0.22), radius: 10, y: 6)
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel("Share this itinerary")
    }

    // MARK: The list's frozen footer

    /// Drive it, and share it — welded to the bottom of My list.
    ///
    /// The two were stacked full-width down the page with a paragraph between them, which
    /// read as two unrelated announcements rather than as the pair of things you do with a
    /// finished list. Share is the rarer of the two and becomes a disc; drive keeps the
    /// words because it is the one that needs explaining.
    private var listFooter: some View {
        HStack(spacing: 11) {
            GlowButton(title: driveTitle, minHeight: 52) {
                driveTheList()
            }

            shareDisc
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WP.gutter)
        .padding(.top, 10)
        .padding(.bottom, -12)
        .background(WP.bg.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
        .alert("No stops on the list", isPresented: $confirmingBareDrive) {
            Button("Cancel", role: .cancel) {}
            Button("Drive there") { openDrive(bare: true) }
        } message: {
            Text("Nothing on this list is set as a stop, so this will take you straight to \(parks.first?.name ?? "the first park") from where you are now.")
        }
    }

    /// The places on the list that are actually driven to, in trip order.
    private var listStops: [PlannedPlace] {
        app.plan(for: trip.id).filter { $0.isStop }.compactMap(\.place)
    }

    private var driveTitle: String {
        switch listStops.count {
        case 0: return "Drive to \(parks.first?.name ?? "the park")"
        case 1: return "Drive it with 1 stop"
        case let count: return "Drive it with \(count) stops"
        }
    }

    /// A drive with nothing on it is a legitimate thing to want and an easy thing to ask
    /// for by accident — every stop switched off looks the same as never having added one.
    /// So it asks first, and says what it is about to do.
    private func driveTheList() {
        if listStops.isEmpty { confirmingBareDrive = true } else { openDrive(bare: false) }
    }

    private func openDrive(bare: Bool) {
        var chain: [MKMapItem] = []
        if let origin = trip.resolvedOrigin(app.library) {
            chain.append(Self.mapItem(lat: origin.lat, lon: origin.lon, name: origin.name))
        }
        chain += bare ? [] : listStops.map(\.mapItem)
        // Always ends at the park, whether or not anything was picked on the way.
        if let park = parks.first {
            chain.append(Self.mapItem(lat: park.lat, lon: park.lon, name: park.name))
        }
        guard chain.count > 1 else { return }
        MKMapItem.openMaps(with: chain, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
    }

    private static func mapItem(lat: Double, lon: Double, name: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        item.name = name
        return item
    }

    // MARK: The hero

    /// Where the route starts, stops and ends — the origin, then the parks in order.
    private var points: [(lat: Double, lon: Double)] {
        let origin = trip.resolvedOrigin(app.library)
        return ([origin.map { (lat: $0.lat, lon: $0.lon) }].compactMap { $0 })
            + parks.map { (lat: $0.lat, lon: $0.lon) }
    }

    private var routeLegs: [RouteLeg] { TripRouteGeometry.stretches(app.routing.legs(for: trip)) }
    private var airports: [(lat: Double, lon: Double)] { TripRouteGeometry.airports(app.routing.legs(for: trip)) }

    /// The trip's route map, full-bleed, dissolving into the page.
    ///
    /// The same three moves the park screen's photograph makes: drawn taller than its box
    /// by the status bar, pulled back up by the same amount so it runs under the clock
    /// while the scroll view keeps its safe area, and faded into the page colour at the
    /// bottom rather than stopping at an edge.
    ///
    /// It collapses to nothing when there is no map to draw — offline on a first open, with
    /// nothing cached. An empty three-hundred-point rectangle is worse than no hero, and
    /// growing the height in when the picture lands moves nothing that was already read.
    @ViewBuilder
    private var hero: some View {
        if points.count > 1 {
            RouteMapPlate(id: trip.id, points: points, legs: routeLegs,
                          airports: airports, hero: true)
                .frame(height: Self.heroHeight + WP.statusBarInset)
                .padding(.top, -WP.statusBarInset)
                // The masthead sits up into the dissolve, where the map has already given
                // way to the page.
                .padding(.bottom, -34)
        } else {
            // No map: the page starts where it always did, under the floating back control.
            Color.clear.frame(height: WP.statusBarInset + 52)
        }
    }

    /// The top of the display, frosted.
    ///
    /// The page runs full bleed so the hero keeps the map that was tapped to get here,
    /// which means a scrolled page sends leg rows up through the status bar and behind the
    /// back control. A row's own words then ran across the clock and across "Trips", and
    /// two pieces of type at the same size sharing the same band reads as a mistake rather
    /// than as depth.
    ///
    /// So the band is frosted rather than cut. Glass at the top going to nothing by the
    /// bottom, with a wash of page colour behind it so the clock keeps its contrast over a
    /// pale row — words lose their edges before they reach the control instead of sliding
    /// out from under it intact. It ends exactly where `pinnedTop` does, which is where the
    /// segmented control's own opaque background begins, so the two meet with no seam.
    ///
    /// Sized and lifted the way `hero` is: drawn taller than its box by the status bar and
    /// pulled back up by the same amount. Nothing here takes a touch — the control sits
    /// above it, the page scrolls under it.
    private var topFrost: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [WP.bg.opacity(0.66), WP.bg.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.9), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: WP.statusBarInset + Self.pinnedTop)
        .padding(.top, -WP.statusBarInset)
        .allowsHitTesting(false)
    }

    /// Where the segmented control sits, and where choosing a section scrolls back to.
    private static let segmentAnchor = "trip.segments"

    /// What the control keeps clear above itself: `FloatingBack`'s own footprint.
    ///
    /// Six points of top padding and forty-four of control, plus four for air — read off
    /// `FloatingBack` rather than measured off a screenshot, because the control owns its
    /// placement and this has to follow it if that ever changes.
    private static let pinnedTop: CGFloat = 54

    /// Shorter than the park screen's 372. A trip has a segmented control and a list under
    /// it, and pushing those off the display is the thing the hero is meant to fix.
    private static let heroHeight: CGFloat = 260

    // MARK: Stats

    /// The miles this trip is actually driven.
    ///
    /// A flown leg used to contribute the drive it replaces — 1,470 miles for a leg the app
    /// had just recommended flying — so the stat row totalled a journey nobody was making.
    /// A leg that flies contributes the two airport drives instead, which is the driving
    /// that will really happen.
    private var totalMiles: Int {
        if isSeed { return app.library.legs.reduce(0) { $0 + $1.mi } }
        let routed = app.routing.legs(for: trip)
        return routed.isEmpty
            ? estimatedMiles
            : routed.reduce(0) { $0 + ($1.flightPath?.drivenMiles ?? $1.miles) }
    }

    /// Whether the miles on this screen were driven by a router or guessed from a great
    /// circle. The stat row says which, because the two are not the same number.
    private var milesAreRouted: Bool { isSeed || !app.routing.legs(for: trip).isEmpty }

    /// What the app is prepared to say about the legs it just drew.
    private var routingNote: String {
        switch app.routing.phase(for: trip) {
        case .idle, .routing:
            return "Routing the legs…"
        case .routed(let origin, let source):
            switch source {
            case .chosen:
                return "Legs routed by Apple Maps from \(origin), the origin this trip was planned from, through the parks in visiting order."
            case .device:
                return "Legs routed by Apple Maps from your location — \(origin) — through the parks in visiting order."
            case .approximate:
                return "Legs routed by Apple Maps from \(origin). This iPhone did not give a precise location, so the first leg starts from there."
            }
        case .unrouted(let why):
            return why
        }
    }

    /// Whether the router is still working on this trip's legs.
    private var isRouting: Bool {
        switch app.routing.phase(for: trip) {
        case .idle, .routing: return true
        case .routed, .unrouted: return false
        }
    }

    /// For a trip the app composed, the legs are estimated from coordinates — and the
    /// stat row says "est." so the number is never read as a routed one.
    private var estimatedMiles: Int {
        guard let origin = trip.resolvedOrigin(app.library) else { return 0 }
        var previous = (lat: origin.lat, lon: origin.lon)
        var sum = 0.0
        for park in parks {
            sum += haversine(previous, (park.lat, park.lon)) * 1.24
            previous = (park.lat, park.lon)
        }
        sum += haversine(previous, (origin.lat, origin.lon)) * 1.24
        return Int((sum / 5).rounded()) * 5
    }

    private func haversine(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let r = Double.pi / 180
        let dLat = (b.lat - a.lat) * r, dLon = (b.lon - a.lon) * r
        let h = pow(sin(dLat / 2), 2) + cos(a.lat * r) * cos(b.lat * r) * pow(sin(dLon / 2), 2)
        return 2 * 3959 * asin(sqrt(h))
    }

    /// The shape of the trip, in one line.
    ///
    /// Five labelled cells in a two-column grid was three rows of chrome above the control
    /// somebody opened the screen to use, and most of what it said the map now says better.
    /// What survives is what the map cannot: how long, how far, and what is driving it.
    ///
    /// The park count goes, because the route line names the parks directly above this. The
    /// packs go to a chip, because a pack is not a fact about the trip — it is a state you
    /// can act on, and it turns lime when it is done so "all downloaded" reads without
    /// being read.
    ///
    /// `milesAreRouted` is the one thing that must survive the compression. A routed number
    /// and a great-circle guess are different claims, and the italic *est.* is where the
    /// screen says which one is on it.
    private var statLine: some View {
        let days = plannedDayCount
        let ready = parks.filter { app.packState($0.code) == .ready }.count
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            figure("\(days)", "days")
            separator
            figure(totalMiles.formatted(.number), milesAreRouted ? "mi by road" : "mi")
            if !milesAreRouted {
                Text("est.").font(WP.bodyItalic(11.5)).opacity(0.6)
            }
            separator
            Text(app.vehicleIsElectric ? "Electric" : "Gasoline")
                .font(WP.body(12.5)).opacity(0.66)
            separator
            packChip(ready: ready, of: parks.count)
            // Only when there is something to say. A trip with nothing booked against it
            // shows nothing here rather than a green all-clear: with the switch off, or
            // the permission refused, nobody has looked, and "clear" would be a claim the
            // app has not earned. Absence is not a finding either way.
            if !calendarClashes.isEmpty {
                clashChip(calendarClashes.count)
            }
            Spacer(minLength: 0)
        }
        // No rules around it. Two hairlines boxed one line of text in directly under a
        // title and a route line that are already separated by nothing but air — the row
        // reads as the end of the heading, and the box made it look like a table with one
        // row in it.
        .padding(.top, 2)
    }

    /// How long the trip is, from the best answer available.
    ///
    /// This used to be `parks.count * 2 + parks.count`, which never looked at a distance
    /// or a duration: a trip with a thirty-seven-hour drive in it and one with a
    /// forty-minute drive in it both came out at six days. In order: the days as composed,
    /// the shape those days will take once the router has answered, and — before it has —
    /// the old arithmetic, which is the only honest thing left to say when the roads are
    /// still unknown.
    private var plannedDayCount: Int {
        if isSeed { return app.library.days.count }
        if case .ready(let composed) = TripDays.shared.state(for: trip), !composed.isEmpty {
            return composed.count
        }
        let shape = TripDays.plannedShape(trip, parks: parks, legs: app.routing.legs(for: trip))
        return shape.isEmpty ? parks.count * 2 + parks.count : shape.count
    }

    private func figure(_ value: String, _ unit: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(WP.body(12.5, semibold: true)).tnum()
            Text(unit).font(WP.body(12.5)).opacity(0.66)
        }
    }

    private var separator: some View {
        Text("·").font(WP.body(12.5)).opacity(0.36)
    }

    /// What this trip's days already have on them.
    private var calendarClashes: [TripCalendar.Clash] {
        TripCalendar.shared.clashes(for: trip.id)
    }

    /// A count, not a colour.
    ///
    /// A red outline says a trip is impossible and gives a reader nothing to do about it.
    /// "2 clashes" says which trip to open and roughly how bad it is, and the day rows say
    /// which days and what with.
    private func clashChip(_ count: Int) -> some View {
        Text("\(count) \(count == 1 ? "clash" : "clashes")")
            .font(WP.body(10.5, semibold: true)).tnum()
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(WP.accent100, in: Capsule())
            .overlay(Capsule().stroke(WP.markDeep.opacity(0.5), lineWidth: 1))
            .foregroundStyle(WP.markDeep)
            .accessibilityLabel("\(count) days of this trip already have something booked")
    }

    private func packChip(ready: Int, of total: Int) -> some View {
        let done = total > 0 && ready == total
        return Text("\(ready) of \(total) packs")
            .font(WP.body(10.5, semibold: true)).tnum()
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(done ? WP.lime : WP.accent100, in: Capsule())
            .overlay(Capsule().stroke(done ? Color.black.opacity(0.12) : WP.accent400, lineWidth: 1))
            .foregroundStyle(done ? WP.text : WP.accent800)
    }

    // MARK: Route

    private var routeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Getting there from where you actually are — the leg no itinerary ever
            // includes, and the first one anybody actually drives.
            if let approach = app.routing.approach(for: trip) {
                legRow(approach.curated, date: "", index: 0, label: "Getting there",
                       flyRefusal: approach.flyRefusal,
                       arriving: parks.first.map { WeatherStop($0) }) {
                    app.sheetTrip = trip.id; app.sheet = .routedLeg(approach, label: "Getting there")
                }
            } else if case .routing = app.routing.approachPhase(for: trip) {
                Text("Measuring the drive from where you are to \(parks.first?.name ?? "the first park")…")
                    .font(WP.bodyItalic(11.5)).opacity(0.55).padding(.vertical, 12)
            } else if case .unrouted(let why) = app.routing.approachPhase(for: trip) {
                Text(why)
                    .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.vertical, 12)
            }

            if isSeed {
                ForEach(Array(app.library.days.enumerated()), id: \.element.d) { _, day in
                    if day.isLeg, let index = day.leg, app.library.legs.indices.contains(index) {
                        legRow(app.library.legs[index], date: day.date, index: index)
                    } else if day.isPark, let code = day.code, let park = app.library.park(code),
                              (day.n ?? 1) == 1 {
                        parkRow(park, date: day.date, days: day.of ?? 1,
                                numeral: numeral(for: code))
                    }
                }
            } else {
                // Drive, park, drive, park — the order they are travelled in, with the
                // first leg starting from wherever the traveller actually is.
                let routed = app.routing.legs(for: trip)
                ForEach(Array(parks.enumerated()), id: \.element.code) { index, park in
                    if index < routed.count {
                        let leg = routed[index]
                        // A flown leg ends at the arrival airport, and the drive on to the
                        // park follows as a row of its own — so the weather column belongs
                        // to whichever of the two actually arrives at the park.
                        legRow(leg.curated, date: "", index: index, flyRefusal: leg.flyRefusal,
                               arriving: leg.arrivalDrive == nil ? WeatherStop(park) : nil) {
                            app.sheetTrip = trip.id; app.sheet = .routedLeg(leg, label: leg.fly == nil ? "Driving day" : "Flying day")
                        }
                        if let arrival = leg.arrivalDrive {
                            let label = "Driving from \(arrival.from)"
                            legRow(arrival.curated, date: "", index: index, label: label,
                                   arriving: WeatherStop(park)) {
                                app.sheetTrip = trip.id
                                app.sheet = .routedLeg(arrival, label: label)
                            }
                        }
                    } else if isRouting {
                        // One leg is asked for per park, in order, before the router is
                        // called — so the count here is not a guess about what will come
                        // back but the number of answers this screen is waiting on. The
                        // park rows used to sit directly on top of one another until the
                        // router replied and then a drive pushed in above each one.
                        awaitedLeg(index: index)
                    }
                    parkRow(park, date: trip.dates, days: 2, numeral: ["I", "II", "III", "IV", "V"][min(index, 4)])
                }
                // The drive home, when there is one.
                if routed.count > parks.count {
                    let home = routed[parks.count]
                    let homeLabel = home.fly == nil ? "The drive home" : "The flight home"
                    // The way home arrives where the trip started, so that is the place
                    // its weather is asked about — the same rule the outbound legs follow,
                    // and the same rule about which of a flight and its arrival drive
                    // carries the column.
                    let back = trip.resolvedOrigin(app.library).map { WeatherStop($0) }
                    legRow(home.curated, date: "", index: parks.count, label: homeLabel,
                           flyRefusal: home.flyRefusal,
                           arriving: home.arrivalDrive == nil ? back : nil) {
                        app.sheetTrip = trip.id; app.sheet = .routedLeg(home, label: homeLabel)
                    }
                    if let arrival = home.arrivalDrive {
                        let label = "Driving from \(arrival.from)"
                        legRow(arrival.curated, date: "", index: parks.count, label: label,
                               arriving: back) {
                            app.sheetTrip = trip.id
                            app.sheet = .routedLeg(arrival, label: label)
                        }
                    }
                }

                Text(routingNote)
                    .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 14)
            }
        }
    }


    // MARK: Weather on the route

    /// The trip's days, once they have been worked out. The route tab draws legs and parks
    /// rather than days, so this is where a row finds out which date it happens on.
    private var plannedDaysList: [TripDays.Day] {
        if case .ready(let days) = TripDays.shared.state(for: trip) { return days }
        return []
    }

    /// The day the nth leg arrives.
    ///
    /// The last of that leg's days, because a leg can take several now and the weather at
    /// the far end belongs to the day you actually get there. Asked by leg rather than by
    /// counting travelling days: those two stopped being the same number the moment a
    /// thirty-seven-hour drive stopped being one day.
    private func travelDate(_ index: Int) -> Date? {
        plannedDaysList.last { $0.leg == index }?.date
    }

    /// Every date spent in one park. Two entries for a two-day park, which is what earns
    /// that park a symbol per day rather than one average true of neither.
    private func parkDates(_ code: String) -> [Date] {
        plannedDaysList.compactMap { day in
            if case .park(let dayCode, _, _, _) = day.kind, dayCode == code { return day.date }
            return nil
        }
    }

    /// Where a leg ends, for the weather column.
    ///
    /// The drive home does not end at a park, and while `arriving:` took a `CuratedPark`
    /// there was nothing to hand it — so the last row of every trip drew no weather at
    /// all. A place with a name and a coordinate is all the forecast ever needed.
    private struct WeatherStop {
        let key: String
        let lat: Double
        let lon: Double

        init(_ park: CuratedPark) { key = park.code; lat = park.lat; lon = park.lon }
        init(_ origin: TripOrigin) { key = origin.name; lat = origin.lat; lon = origin.lon }
    }

    /// A leg is weathered at the place it arrives — the end of a drive is where the day is
    /// spent, and the start of it is a park whose own row already carries the morning.
    private func legWeather(_ index: Int, to stop: WeatherStop?) -> some View {
        Group {
            if let stop, let date = travelDate(index) {
                WeatherGlyph(day: TripWeather.shared.day(lat: stop.lat, lon: stop.lon, date: date),
                             awaiting: TripWeather.shared.isAsking(lat: stop.lat, lon: stop.lon, date: date))
                    .task(id: stop.key + date.description) {
                        TripWeather.shared.load(lat: stop.lat, lon: stop.lon, date: date)
                    }
            }
        }
    }

    private func numeral(for code: String) -> String {
        let index = trip.codes.firstIndex(of: code) ?? 0
        return ["I", "II", "III", "IV", "V"][min(index, 4)]
    }

    /// - Parameter flyRefusal: why this leg is driven, on a trip that asked to fly where
    ///   flying is faster. Shown so the answer is visible: a switch that silently changes
    ///   nothing on the legs it declined reads as a switch that does not work.
    private func legRow(_ leg: CuratedLeg, date: String, index: Int,
                        label: String? = nil,
                        flyRefusal: String? = nil,
                        arriving: WeatherStop? = nil,
                        onTap: (() -> Void)? = nil) -> some View {
        Button {
            // A seed leg opens the sheet the library built; a routed one opens the sheet
            // built from what the router returned. Both open.
            if let onTap { onTap() } else { app.sheetTrip = trip.id; app.sheet = .leg(index: index, date: date) }
        } label: {
            DividedRow(vertical: 13) {
                // Centred, not top-aligned. The glyph pinned to the top of the row sat
                // level with the "LEG I" rule and read as belonging to the heading rather
                // than to the drive under it.
                HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 9) {
                        Text((label ?? "Leg \(["I", "II", "III", "IV"][min(index, 3)])").uppercased())
                            .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent)
                        Rectangle().fill(WP.divider).frame(height: 1)
                        if !date.isEmpty {
                            Text(date).font(WP.body(11)).opacity(0.55)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(leg.from)
                        Text("→").foregroundStyle(WP.accent700)
                        Text(leg.to)
                    }
                    .font(WP.body(14))
                    .padding(.top, 3)
                    Text("\(leg.mi) mi · \(leg.drive) · \(leg.road)")
                        .font(WP.body(12)).opacity(0.62).lineSpacing(1)
                        .multilineTextAlignment(.leading)
                    if let fly = leg.fly {
                        Text("By air: \(fly.via) · \(fly.time)")
                            .font(WP.bodyItalic(12)).foregroundStyle(WP.accent700)
                    } else if let flyRefusal {
                        Text(flyRefusal)
                            .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                // One column down the right edge of the whole route, so the weather of a
                // trip reads as a strip in a single pass rather than as a fact buried in
                // each row's own sentence.
                legWeather(index, to: arriving)

                // The same chevron the park rows carry. A leg opens a sheet with the
                // whole drive in it and nothing said so — the row was the only openable
                // thing on this screen with no mark on it.
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WP.accent700)
                }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }


    /// A leg the router has been asked for and has not returned.
    ///
    /// The kicker is real — "LEG II" is this screen's own numbering and does not come from
    /// the router — and so is the rule beside it. Only the two lines the router actually answers
    /// with are grey: where the drive runs, and how far and how long it is.
    ///
    /// No skeleton is drawn for the drive home. Whether a trip has one depends on the
    /// origin having a name, which is not settled until the router has run, and a row that
    /// might never arrive is the one thing a placeholder must not promise. Under-drawing
    /// costs one row of movement; over-drawing states something untrue.
    private func awaitedLeg(index: Int) -> some View {
        DividedRow(vertical: 13) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text("Leg \(["I", "II", "III", "IV"][min(index, 3)])".uppercased())
                        .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent.opacity(0.5))
                    Rectangle().fill(WP.divider).frame(height: 1)
                }
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(width: 168, height: 13)
                    SkeletonBar(width: 210, height: 11)
                }
                .padding(.top, 5)
                .skeletonBreath()
            }
        }
    }

    /// A park's sky for the days actually spent in it.
    ///
    /// One day, one symbol. More than one, a symbol each with the weekday over it — a
    /// two-day park averaged into a single glyph is a reading true of neither day, and
    /// "which of the two is the wet one" is the question somebody planning a park actually
    /// has. Capped at three so a long stay cannot push the row off its own edge.
    @ViewBuilder
    private func parkWeather(_ park: CuratedPark) -> some View {
        let dates = parkDates(park.code)
        HStack(spacing: 9) {
            ForEach(Array(dates.prefix(3).enumerated()), id: \.offset) { _, date in
                WeatherGlyph(
                    day: TripWeather.shared.day(lat: park.lat, lon: park.lon, date: date),
                    caption: dates.count > 1 ? Self.weekday.string(from: date) : nil,
                    awaiting: TripWeather.shared.isAsking(lat: park.lat, lon: park.lon, date: date)
                )
            }
        }
        .task(id: park.code + "\(dates.count)") {
            for date in dates.prefix(3) {
                TripWeather.shared.load(lat: park.lat, lon: park.lon, date: date)
            }
        }
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private func parkRow(_ park: CuratedPark, date: String, days: Int, numeral: String) -> some View {
        Button {
            // Opened for the day the trip reaches it, so the weather panel answers for
            // then rather than for today — and carrying the trip, so every list on the
            // park screen can put a place on this trip's list.
            app.openPark(park.code, date: trip.startDate, trip: trip.id)
        } label: {
            DividedRow(vertical: 14) {
                HStack(spacing: 13) {
                    ZStack {
                        ParkImage(park: park, blur: 7, saturation: 1.15,
                                  showsScrim: false, topLight: false)
                        Text(numeral)
                            .font(WP.headingUI(17))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(park.name).font(WP.rowTitle(18))
                        // A park the curated library has no weather for reported "0°" here,
                        // which reads as a freezing forecast rather than as no forecast.
                        // The high has moved to the glyph on the right, where it sits under
                        // the sky it belongs to.
                        Text([date, "\(days) day\(days == 1 ? "" : "s")"]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                            .font(WP.body(12)).opacity(0.62).tnum()
                    }
                    Spacer(minLength: 0)

                    parkWeather(park)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WP.accent700)
                }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }

    // MARK: Days

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSeed {
                ForEach(app.library.days) { day in
                    Button {
                        app.day = day.d
                        app.go(.today)
                    } label: {
                        DividedRow(vertical: 13) {
                            HStack(alignment: .top, spacing: 12) {
                                Text(day.date)
                                    .font(WP.body(11.5))
                                    .foregroundStyle(WP.accent700)
                                    .frame(width: 62, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(dayKicker(day).uppercased())
                                        .font(WP.body(10)).tracking(1.4).opacity(0.55)
                                    Text(dayTitle(day)).font(WP.rowTitle(17))
                                        .multilineTextAlignment(.leading)
                                    Text(daySub(day)).font(WP.body(12)).opacity(0.62).lineSpacing(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            } else {
                plannedDays
            }
        }
    }

    /// The trip, day by day: what is driven, what is worth stopping at on the way, and
    /// what the park service says there is to do once you are there.
    @ViewBuilder
    private var plannedDays: some View {
        switch TripDays.shared.state(for: trip) {
        case .idle, .building:
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Working out the days — the roads, and what the park service has near them…")
                    .font(WP.bodyItalic(12.5)).opacity(0.7).lineSpacing(3)
            }
            // The day count is arithmetic on what is already in hand — the parks, the
            // legs the router returned, the nights the trip was saved with — so the tab
            // can hold exactly the rows that are coming, and say which of them are drives.
            // Empty until the legs land: before that the count genuinely is not known, and
            // this tab keeps to its sentence.
            let shape = TripDays.plannedShape(trip, parks: parks, legs: app.routing.legs(for: trip))
            ForEach(Array(shape.enumerated()), id: \.offset) { _, isTravel in
                awaitedDay(isTravel: isTravel)
            }
        case .failed(let why):
            Text(why).font(WP.bodyItalic(13)).opacity(0.7).lineSpacing(3)
        case .ready(let days):
            ForEach(days) { day in
                PlannedDayRow(day: day)
                    .environment(\.planningTrip, trip.id)
            }

            calendarNote.padding(.top, 16)

            // `PlannedDayRow` is a `DividedRow`: the last day drew the closing rule.
            SourceLine("Days are worked out from the routed hours: at most eight at the wheel a day, setting off at eight — nine on the first morning — with fifteen per cent added for fuel, food and stops when working out when you get in. Arrive after four and the day is spent arriving. Stops are the National Park Service's, detours measured by OSRM against the same drive without them. Things to do are the park service's own list, in its own order — NPS publishes no rating to sort by.",
                       ruled: false)
                .padding(.top, 14)
        }
    }

    // MARK: The trip on the calendar

    /// Put the trip on the calendar, or take it back off.
    ///
    /// At the foot of the day list rather than beside the title, because this writes down
    /// exactly what is above it — one all-day entry per composed day — and the place to
    /// decide that is where those days can be read.
    /// The trip on the calendar, and the trip shared — welded to the floor of the Days tab.
    ///
    /// `listFooter`, with one word changed. The same `GlowButton` in the same lime at the
    /// same fifty-two points, the same eleven-point gap to the same share disc, the same
    /// page colour under the same hairline. Two tabs that both end in one action should end
    /// in the same control, and a dark glass pill beside a lime one read as two apps.
    private var calendarFooter: some View {
        HStack(spacing: 11) {
            GlowButton(title: calendarActionTitle, minHeight: 52) {
                Haptics.tap()
                Task { await writeToCalendar(remove: app.calendarTrips.contains(trip.id)) }
            }
            .disabled(TripCalendar.shared.working.contains(trip.id))
            .accessibilityLabel(app.calendarTrips.contains(trip.id)
                                ? "Take this trip off your calendar"
                                : "Add this trip's days to your calendar")

            shareDisc
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WP.gutter)
        .padding(.top, 10)
        .padding(.bottom, -12)
        .background(WP.bg.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    /// What the control says, including while it is writing.
    ///
    /// `GlowButton` carries a title and nothing else — no icon, no spinner — which is what
    /// makes it the same control My list uses rather than a lookalike. So the working state
    /// is said in the words, the way "Drive it with 3 stops" already changes with the list.
    private var calendarActionTitle: String {
        let added = app.calendarTrips.contains(trip.id)
        if TripCalendar.shared.working.contains(trip.id) {
            return added ? "Removing…" : "Adding…"
        }
        return added ? "Remove from calendar" : "Add to calendar"
    }

    /// What the control at the foot of the screen is about to do, or has done.
    ///
    /// Left in the scroll rather than carried into the footer: a frozen strip is for
    /// controls, and two lines of prose welded over the page would cost every day row the
    /// height of a paragraph for something worth reading once.
    private var calendarNote: some View {
        let added = app.calendarTrips.contains(trip.id)
        return VStack(alignment: .leading, spacing: 6) {
            // Said once, and only where it is true: the calendar was read, and these days
            // came back empty. The stat line stays silent when a trip is clear — silence is
            // not a claim — so this is the one place the difference between "checked, and
            // clear" and "never checked" is written down.
            if TripCalendar.shared.hasLooked(at: trip.id), calendarClashes.isEmpty {
                Text("Nothing else on your calendar for these days.")
                    .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(added
                 ? "These days are on your calendar, in “\(TripCalendar.shared.wroteInto ?? TripCalendar.calendarTitle)” — so hiding or deleting the whole trip is one move in Calendar."
                 : "Adding writes one all-day entry per day, into a calendar of its own called “\(TripCalendar.calendarTitle)” where your account will hold one. Nothing else on your calendar is touched.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func writeToCalendar(remove: Bool) async {
        if remove {
            if await TripCalendar.shared.remove(trip.id) {
                app.calendarTrips.remove(trip.id)
                app.persist()
                app.show("Taken off your calendar")
            } else {
                app.show(TripCalendar.shared.trouble ?? "The calendar did not answer")
            }
            return
        }
        let plan = TripCalendar.plan(for: trip, days: plannedDaysList, parks: parks)
        if await TripCalendar.shared.add(plan) {
            app.calendarTrips.insert(trip.id)
            app.persist()
            // Named, because it is not always the calendar the button offered — where no
            // account will hold one of ours the days go where new events already go.
            let into = TripCalendar.shared.wroteInto.map { " to “\($0)”" } ?? ""
            app.show("\(plan.entries.count) days added\(into)")
        } else {
            app.show(TripCalendar.shared.trouble ?? "The calendar did not answer")
        }
    }

    /// What decides a fresh look at the calendar: the trip, how many days it now has, and
    /// whether the traveller has the feature on at all.
    private var calendarKey: String {
        "\(trip.id)|\(plannedDaysList.count)|\(app.checksCalendar)"
    }

    /// A day the builder is composing. A drive and a day in a park are laid out the same
    /// way and read differently — a short kicker over a long line for "Denver → Zion", a
    /// long kicker over a short one for "Zion National Park · day 1 of 2" — and which of
    /// the two this row will be is known, so the bars say it.
    private func awaitedDay(isTravel: Bool) -> some View {
        DividedRow(vertical: 13) {
            HStack(alignment: .top, spacing: 12) {
                SkeletonBar(width: 46, height: 11)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBar(width: isTravel ? 74 : 138, height: 9)
                    SkeletonBar(width: isTravel ? 186 : 146, height: 16)
                }
                Spacer(minLength: 0)
            }
            .skeletonBreath()
        }
    }

    private func dayKicker(_ day: CuratedDay) -> String {
        if day.isLeg { return "Driving day" }
        guard let code = day.code, let park = app.library.park(code) else { return "" }
        return "\(park.name) · day \(day.n ?? 1) of \(day.of ?? 1)"
    }

    private func dayTitle(_ day: CuratedDay) -> String {
        if let index = day.leg, app.library.legs.indices.contains(index) {
            let leg = app.library.legs[index]
            return "\(leg.from) → \(leg.to)"
        }
        // The park itself. This used to print a written-down itinerary title — "Geyser
        // basins" — which shipped for eight parks and for no others, so most trips got a
        // blank line where a day's name should be.
        guard let code = day.code, let park = app.library.park(code) else { return "" }
        return park.name
    }

    private func daySub(_ day: CuratedDay) -> String {
        if let index = day.leg, app.library.legs.indices.contains(index) {
            let leg = app.library.legs[index]
            return "\(leg.mi) mi · \(leg.drive) · \(leg.ev.count) charge stops"
        }
        guard let code = day.code, let park = app.library.park(code) else { return "" }
        // The temperature only once something has answered for it. It was the bundled
        // August high, printed against whatever date the trip actually falls on.
        guard park.wx.isPublished else { return park.gw }
        return park.gw.isEmpty ? "\(park.wx.hi)°" : "\(park.wx.hi)° · \(park.gw)"
    }
}


// MARK: - One planned day

/// A day of the trip, folded down to a line.
///
/// The plan printed every day in full: the drive, the detours worth taking, and the park
/// service's own paragraph about each thing to do at each park. Four days filled a screen,
/// so a fortnight was fourteen screens and the *shape* of a trip — where the driving is,
/// which parks get two days — could not be seen at all. Folded, a fortnight fits on one
/// screen and the question "what am I doing on Wednesday" is answered by scanning rather
/// than by scrolling.
///
/// The shut line is never blank: a driving day keeps its mileage, a park day says how many
/// things are in it. Nothing is hidden that was not already a paragraph.
private struct PlannedDayRow: View {
    var day: TripDays.Day

    @Environment(\.planningTrip) private var planningTrip
    @State private var isOpen = false
    /// Which descriptions inside this day have been opened out.
    @State private var expandedDoings: Set<String> = []

    var body: some View {
        DividedRow(vertical: 13) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isOpen {
                    detail
                        .padding(.top, 7)
                        .padding(.leading, 74)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: Shut

    private var header: some View {
        Button {
            withAnimation(Motion.panel) { isOpen.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(day.dateLabel)
                    .font(WP.body(11.5))
                    .foregroundStyle(WP.accent700)
                    .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kicker.uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.55)
                    Text(summary)
                        .font(WP.rowTitle(17))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Visible folded. A fortnight of days is one screen precisely so the
                    // shape of the trip can be read without opening anything, and which
                    // day is already spoken for is part of that shape.
                    if !clashes.isEmpty {
                        Text(clashLine)
                            .font(WP.bodyItalic(11.5))
                            .foregroundStyle(WP.markDeep)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 0)

                if let trailing {
                    Text(trailing)
                        .font(WP.body(12)).opacity(0.62).tnum()
                        .padding(.top, 13)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WP.accent700)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .padding(.top, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.995))
        .accessibilityLabel("\(day.dateLabel). \(kicker). \(summary)")
        .accessibilityHint(isOpen ? "Collapses the day" : "Expands the day")
        .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)
    }

    /// What this day already has on it, where anybody has looked.
    private var clashes: [TripCalendar.Clash] {
        guard let planningTrip else { return [] }
        return TripCalendar.shared.clashes(for: planningTrip, on: day.date)
    }

    private var clashLine: String {
        switch clashes.count {
        case 0: return ""
        case 1: return "Already booked: \(clashes[0].title)"
        case let count: return "Already booked: \(clashes[0].title), and \(count - 1) more"
        }
    }

    private var kicker: String {
        switch day.kind {
        case .travel(_, _, _, _, let fly):
            if fly != nil { return "Flying day" }
            // A leg can take more than a day now, and a row that said only "Driving day"
            // three times running gave a reader no way to tell them apart.
            return day.parts > 1 ? "Driving day \(day.part) of \(day.parts)" : "Driving day"
        case .park(_, let name, let number, let of): return "\(name) · day \(number) of \(of)"
        }
    }

    /// The one line the day is worth when it is shut.
    private var summary: String {
        switch day.kind {
        case .travel(let from, let to, _, _, _):
            return "\(from) → \(to)"
        case .park:
            switch day.doings.count {
            case 0: return day.doingsNote == nil ? "Nothing to do listed" : "Nothing listed yet"
            case 1: return "1 thing to do"
            case let count: return "\(count) things to do"
            }
        }
    }

    /// What a driving day is, in the space a park day does not need.
    private var trailing: String? {
        guard case .travel(_, _, let miles, _, _) = day.kind else { return nil }
        return "\(miles) mi"
    }

    // MARK: Open

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch day.kind {
            case .travel(_, _, let miles, let drive, let fly):
                if let fly {
                    Text("\(fly.via) · \(fly.time)")
                        .font(WP.body(12)).foregroundStyle(WP.accent700).tnum()
                    Text("\(miles) mi · \(drive) if driven instead")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).tnum()
                    // A flown leg has no roadside to stop at, so the day says nothing
                    // about detours rather than reporting that it found none.
                } else {
                    Text("\(miles) mi · \(drive)")
                        .font(WP.body(12)).opacity(0.62).tnum()

                    if day.stops.isEmpty {
                        Text("Nothing of the park service's within a two-hour detour of this day's driving.")
                            .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Worth stopping for".uppercased())
                            .font(WP.body(9.5)).tracking(1.3)
                            .foregroundStyle(WP.mark)
                            .padding(.top, 4)
                        ForEach(day.stops) { stop in
                            HStack(alignment: .top, spacing: 9) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(stop.name).font(WP.body(13.5))
                                    Text("\(stop.place) · \(stop.designation) · \(stop.diversionLine)")
                                        .font(WP.bodyItalic(11)).opacity(0.6)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                // A detour worth taking is exactly the kind of thing that
                                // should end up on the list, and this is the screen where
                                // a reader decides it is worth taking.
                                PlaceRowActions(place: PlannedPlace(
                                    name: stop.name,
                                    subtitle: "\(stop.place) · \(stop.designation)",
                                    lat: stop.lat, lon: stop.lon,
                                    category: PlacesService.Kind.campground.rawValue
                                ), day: day.date)
                            }
                        }
                    }
                }

            case .park:
                if day.doings.isEmpty {
                    Text(day.doingsNote ?? "Nothing to do listed for this park.")
                        .font(WP.bodyItalic(12)).opacity(0.6).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(day.doings) { doing in
                        doingRow(doing)
                    }
                }
            }

            // The one thing an arrival day is actually about: whether there is any of it
            // left. Nil on every other kind of day, so it sits after the switch rather
            // than being repeated inside both travelling branches.
            if let line = day.arrivalLine {
                Text(line)
                    .font(WP.bodyItalic(11.5)).foregroundStyle(WP.accent700).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }

            // Named, with the hour, because "you have a clash" is not something anybody can
            // act on and "Dentist, 2:30 PM" is.
            if !clashes.isEmpty {
                Text("Already on this day".uppercased())
                    .font(WP.body(9.5)).tracking(1.3)
                    .foregroundStyle(WP.markDeep)
                    .padding(.top, 5)
                ForEach(clashes) { clash in
                    Text("\(clash.title) · \(clash.whenLabel)")
                        .font(WP.body(12.5)).opacity(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One thing to do, with a way to read the rest of what the park service wrote.
    ///
    /// The description ran to two lines and stopped at an ellipsis, and nothing said the
    /// rest existed or how to get at it — a reader opening the app for the first time has
    /// no reason to think three dots are a control. The words "Read more" are the control,
    /// and the whole row answers a tap so the target is not a six-point glyph.
    private func doingRow(_ doing: TripDays.Doing) -> some View {
        let isOpen = expandedDoings.contains(doing.id)
        // Two lines of this font is roughly this many characters; below it nothing is
        // being hidden and offering to open it would be a control that does nothing.
        let hasMore = (doing.note?.count ?? 0) > 96

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                if isOpen { expandedDoings.remove(doing.id) } else { expandedDoings.insert(doing.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(doing.title).font(WP.rowTitle(15))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if let duration = doing.duration {
                        Text(duration).font(WP.body(11)).opacity(0.6)
                    }
                }
                if let note = doing.note {
                    Text(note)
                        .font(WP.body(11.5)).opacity(0.62)
                        .lineSpacing(2)
                        .lineLimit(isOpen ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasMore {
                    HStack(spacing: 4) {
                        Text(isOpen ? "Show less" : "Read more").font(WP.body(11.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .foregroundStyle(WP.mark)
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.995))
        .disabled(!hasMore)
        .accessibilityHint(hasMore ? (isOpen ? "Collapses the description" : "Expands the description") : "")
    }

}

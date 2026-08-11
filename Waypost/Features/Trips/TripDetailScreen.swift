import SwiftUI

/// A trip, opened. Route / Days / Stays — the web app's single long scroll, split three
/// ways so each answers one question.
struct TripDetailScreen: View {
    @Environment(AppState.self) private var app
    var trip: SavedTrip

    @State private var segment: TripSegment = .route

    private var parks: [CuratedPark] { trip.codes.compactMap { app.park($0) } }
    private var isSeed: Bool { trip.id == "seed" }

    var body: some View {
        VStack(spacing: 0) {
            PushHeader(backLabel: "Trips", title: trip.title) { app.pop() }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(trip.tag).kickerStyle()
                    Text(trip.title).font(WP.display(34)).padding(.top, 7)
                        .multilineTextAlignment(.leading)
                    Text(trip.route).font(WP.bodyItalic(12.5)).opacity(0.65).padding(.top, 5)

                    stats.padding(.top, 16)

                    SegmentedTrough(options: TripSegment.allCases.map { ($0, $0.label) }, selection: $segment)
                        .padding(.top, 18)

                    Group {
                        switch segment {
                        case .route: routeList
                        case .days: dayList
                        case .stays: stayList
                        }
                    }
                    .padding(.top, 20)
                    .panelTransition(id: segment)

                    GlowButton(title: "Share this itinerary") {
                        app.show("Sharing sends a read-only copy")
                    }
                    .padding(.top, 22)

                    Text("Sharing sends a read-only copy. Whoever opens it can duplicate it into their own Trips.")
                        .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3).padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 18)
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .captureScrollPosition()
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
    }

    // MARK: Stats

    private var totalMiles: Int {
        if isSeed { return app.library.legs.reduce(0) { $0 + $1.mi } }
        let routed = app.routing.legs(for: trip)
        return routed.isEmpty ? estimatedMiles : routed.reduce(0) { $0 + $1.miles }
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
                return "Legs routed by OSRM from \(origin), the origin this trip was planned from, through the parks in visiting order."
            case .device:
                return "Legs routed by OSRM from your location — \(origin) — through the parks in visiting order."
            case .approximate:
                return "Legs routed by OSRM from \(origin). This iPhone did not give a precise location, so the first leg starts from there."
            }
        case .unrouted(let why):
            return why
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

    private var statRows: [(label: String, value: String)] {
        let days = isSeed ? app.library.days.count : parks.count * 2 + parks.count
        return [
            ("Parks", "\(parks.count)"),
            ("Days", "\(days)"),
            (milesAreRouted ? "Miles by road" : "Miles, est.", totalMiles.formatted(.number)),
            ("Vehicle", app.vehicleIsElectric ? "Electric" : "Gasoline"),
            ("Packs", "\(parks.filter { app.packState($0.code) == .ready }.count) of \(parks.count) ready"),
        ]
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            ForEach(statRows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label.uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.55)
                    Text(row.value).font(WP.statValue(20)).tnum()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: Route

    private var routeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Getting there from where you actually are — the leg no itinerary ever
            // includes, and the first one anybody actually drives.
            if let approach = app.routing.approach(for: trip) {
                legRow(approach.curated, date: "", index: 0, label: "Getting there") {
                    app.sheet = .routedLeg(approach, label: "Getting there")
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
                        legRow(leg.curated, date: "", index: index) {
                            app.sheet = .routedLeg(leg, label: "Driving day")
                        }
                    }
                    parkRow(park, date: trip.dates, days: 2, numeral: ["I", "II", "III", "IV", "V"][min(index, 4)])
                }
                // The drive home, when there is one.
                if routed.count > parks.count {
                    let home = routed[parks.count]
                    legRow(home.curated, date: "", index: parks.count, label: "The drive home") {
                        app.sheet = .routedLeg(home, label: "The drive home")
                    }
                }

                Text(routingNote)
                    .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 14)
            }
        }
    }

    private func numeral(for code: String) -> String {
        let index = trip.codes.firstIndex(of: code) ?? 0
        return ["I", "II", "III", "IV", "V"][min(index, 4)]
    }

    private func legRow(_ leg: CuratedLeg, date: String, index: Int,
                        label: String? = nil,
                        onTap: (() -> Void)? = nil) -> some View {
        Button {
            // A seed leg opens the sheet the library built; a routed one opens the sheet
            // built from what the router returned. Both open.
            if let onTap { onTap() } else { app.sheet = .leg(index: index, date: date) }
        } label: {
            DividedRow(vertical: 13) {
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
                    }
                }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }

    private func parkRow(_ park: CuratedPark, date: String, days: Int, numeral: String) -> some View {
        Button {
            // Opened for the day the trip reaches it, so the weather panel answers for
            // then rather than for today.
            app.openPark(park.code, date: trip.startDate)
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
                        Text([date,
                              "\(days) day\(days == 1 ? "" : "s")",
                              park.wx.isPublished ? "\(park.wx.hi)°" : ""]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                            .font(WP.body(12)).opacity(0.62).tnum()
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

    /// Which descriptions have been opened out.
    @State private var expandedDoings: Set<String> = []

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
        case .failed(let why):
            Text(why).font(WP.bodyItalic(13)).opacity(0.7).lineSpacing(3)
        case .ready(let days):
            ForEach(days) { day in
                DividedRow(vertical: 13) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(day.dateLabel)
                            .font(WP.body(11.5))
                            .foregroundStyle(WP.accent700)
                            .frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 5) {
                            switch day.kind {
                            case .travel(let from, let to, let miles, let drive):
                                Text("Driving day".uppercased())
                                    .font(WP.body(10)).tracking(1.4).opacity(0.55)
                                Text("\(from) → \(to)").font(WP.rowTitle(17))
                                    .multilineTextAlignment(.leading)
                                Text("\(miles) mi · \(drive)")
                                    .font(WP.body(12)).opacity(0.62).tnum()

                                if day.stops.isEmpty {
                                    Text("Nothing of the park service's within a two-hour detour of this drive.")
                                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("Worth stopping for".uppercased())
                                        .font(WP.body(9.5)).tracking(1.3)
                                        .foregroundStyle(WP.mark)
                                        .padding(.top, 4)
                                    ForEach(day.stops) { stop in
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(stop.name).font(WP.body(13.5))
                                            Text("\(stop.place) · \(stop.designation) · \(stop.diversionLine)")
                                                .font(WP.bodyItalic(11)).opacity(0.6)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }

                            case .park(_, let name, let number, let of):
                                Text("\(name) · day \(number) of \(of)".uppercased())
                                    .font(WP.body(10)).tracking(1.4).opacity(0.55)
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
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            SourceLine("Stops from the National Park Service, detours measured by OSRM against the same drive without them. Things to do are the park service's own list, in its own order — NPS publishes no rating to sort by.")
                .padding(.top, 14)
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

    // MARK: Stays

    /// The park service's campgrounds for one park, once its record has arrived.
    private func campgrounds(for park: CuratedPark) -> [ParkFacts.Campground] {
        if case .loaded(let facts) = ParkFacts.shared.state(for: park) { return facts.campgrounds }
        return []
    }

    private var stayList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parks) { park in
                let camps = campgrounds(for: park)
                if camps.isEmpty {
                    DividedRow(vertical: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(park.name.uppercased())
                                .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent)
                            Text("Asking the park service for this park's campgrounds…")
                                .font(WP.body(12)).opacity(0.65).lineSpacing(2)
                        }
                    }
                } else {
                    ForEach(camps) { camp in
                        DividedRow(vertical: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(park.name.uppercased())
                                    .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent)
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(camp.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    if let fee = camp.fee {
                                        Text(fee).font(WP.body(12.5)).foregroundStyle(WP.accent700)
                                    }
                                }
                                if let note = camp.reservationNote {
                                    Text(note).font(WP.body(12)).opacity(0.65).lineSpacing(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                }
            }
            SourceLine("Campgrounds from the National Park Service. Availability for your own nights is not published to this app — confirm with the campground.")
        }
        // The trip screen reads these; nothing else on it has asked for them.
        .task(id: parks.map(\.code).joined()) {
            for park in parks { ParkFacts.shared.load(park) }
        }
    }
}

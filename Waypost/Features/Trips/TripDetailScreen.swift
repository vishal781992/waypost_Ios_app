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
                    Text(trip.title).font(WP.heading(27)).padding(.top, 7)
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
        }
        .background(WP.bg)
        .onAppear {
            segment = app.tripSegment[trip.id] ?? .route
            if let first = parks.first {
                app.routing.routeApproach(trip, to: first)
            }
            if !isSeed {
                app.routing.route(trip, parks: parks, originCity: app.library.city(trip.origin))
            }
        }
        .onChange(of: segment) { _, new in app.tripSegment[trip.id] = new }
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
            return "Routing the legs from where you are…"
        case .routed(let origin, let precise):
            return precise
                ? "Legs routed by OSRM from your location — \(origin) — through the parks in visiting order."
                : "Legs routed by OSRM from \(origin). This iPhone did not give a precise location, so the first leg starts from there."
        case .unrouted(let why):
            return why
        }
    }

    /// For a trip the app composed, the legs are estimated from coordinates — and the
    /// stat row says "est." so the number is never read as a routed one.
    private var estimatedMiles: Int {
        guard let origin = app.library.city(trip.origin) else { return 0 }
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
            app.openPark(park.code)
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
                        Text("\(date) · \(days) day\(days == 1 ? "" : "s") · \(park.wx.hi)°")
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
                Text("Day plans are written when the trip is composed online. The parks' own plans are on each park screen.")
                    .font(WP.bodyItalic(13)).opacity(0.7).lineSpacing(3)
            }
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
        guard let code = day.code, let park = app.library.park(code), !park.days.isEmpty else { return "" }
        return park.days[min((day.n ?? 1) - 1, park.days.count - 1)].title
    }

    private func daySub(_ day: CuratedDay) -> String {
        if let index = day.leg, app.library.legs.indices.contains(index) {
            let leg = app.library.legs[index]
            return "\(leg.mi) mi · \(leg.drive) · \(leg.ev.count) charge stops"
        }
        guard let code = day.code, let park = app.library.park(code) else { return "" }
        return "\(park.wx.hi)° · \(park.gw)"
    }

    // MARK: Stays

    private var stayList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parks) { park in
                ForEach(park.camping) { camp in
                    DividedRow(vertical: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(park.name.uppercased())
                                    .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent)
                                Spacer(minLength: 0)
                                Text(camp.av)
                                    .font(WP.body(10))
                                    .padding(.horizontal, 9).padding(.vertical, 2)
                                    .background(camp.isOpen ? WP.accent100 : WP.neutral100, in: Capsule())
                                    .foregroundStyle(camp.isOpen ? WP.accent800 : WP.neutral800)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(camp.name).font(WP.rowTitle(17)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(camp.price).font(WP.body(12.5)).foregroundStyle(WP.accent700)
                            }
                            Text("\(camp.whereText) · \(camp.sites) · \(camp.src)")
                                .font(WP.body(12)).opacity(0.65).lineSpacing(2)
                        }
                    }
                }
            }
            SourceLine("Stays — curated. Live availability for your nights arrives with the data re-wire.")
        }
    }
}

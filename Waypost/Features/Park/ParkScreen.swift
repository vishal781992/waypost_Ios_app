import SwiftUI

/// One park, pushed over whatever opened it. The web app's six in-park tabs become one
/// screen with a scrolling segment rail.
struct ParkScreen: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark
    var initialSegment: ParkSegment
    /// The day this park is being read for — a trip's arrival date. Nil means today.
    var date: Date?

    @State private var segment: ParkSegment = .overview

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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(liveFee ?? park.fee).font(WP.body(12.5)).opacity(0.85)
                Text("|").opacity(0.28)
                Text(liveHours ?? park.hours).font(WP.body(12.5)).opacity(0.85)
            }
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
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    masthead
                    actions
                    SegmentRail(options: ParkSegment.allCases.map { ($0, $0.label) }, selection: $segment)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                        .background {
                            Rectangle().fill(WP.bg.opacity(0.94))
                                .overlay(alignment: .bottom) { Hairline() }
                        }

                    Group {
                        switch segment {
                        case .overview: OverviewSection(park: park)
                        case .weather: WeatherSection(park: park, date: date)
                        case .stay: StaySection(park: park)
                        case .plan: PlansSection(park: park)
                        case .near: NearbySection(park: park)
                        }
                    }
                    .padding(.horizontal, WP.gutter)
                    .padding(.top, 18)
                    .padding(.bottom, WP.tabBarClearance)
                    .panelTransition(id: segment)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .captureScrollPosition()
            .ignoresSafeArea(edges: .top)

            backControl
        }
        .background(WP.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { segment = app.parkSegment[park.code] ?? initialSegment }
        .task(id: park.code) { ParkFacts.shared.load(park) }
        .onChange(of: segment) { _, new in app.parkSegment[park.code] = new }
    }

    /// The photograph, full-bleed, dissolving into the page rather than stopping at an
    /// edge — so the name below it reads as being written on the same sheet.
    private var hero: some View {
        ParkImage(park: park, showsScrim: false, topLight: false)
            .frame(height: 372)
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
            if park.res {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reserve before you arrive".uppercased())
                        .font(WP.body(10)).tracking(1.4)
                        .foregroundStyle(WP.accent800)
                    Text(park.resNote)
                        .font(WP.body(13)).lineSpacing(3)
                        .foregroundStyle(WP.accent900)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(WP.accent100, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.accent300, lineWidth: 1))
            } else {
                Text(park.resNote)
                    .font(WP.bodyItalic(13)).lineSpacing(3).opacity(0.75)
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

    /// The fee the park service publishes today, in preference to anything bundled.
    private var liveFee: String? { facts?.fee }
    private var liveHours: String? { facts?.hours }

    /// Alerts the park is posting right now — closures, fire, road work — ahead of the
    /// bundled ones, which are editorial rather than current.
    private var alerts: [CuratedAlert] {
        if let live = facts?.alerts, !live.isEmpty { return live }
        return park.alerts
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
            .padding(.top, 14)
            .overlay(alignment: .top) { Hairline() }

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
        Text(text.uppercased())
            .font(WP.body(12))
            .tracking(1.5)
            .foregroundStyle(WP.accent700)
            .padding(.bottom, 2)
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

                Text([camp.sites.map { "\($0) sites" }, camp.fee]
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

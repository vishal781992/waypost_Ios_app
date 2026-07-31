import SwiftUI

/// One park, pushed over whatever opened it. The web app's six in-park tabs become one
/// screen with a scrolling segment rail.
struct ParkScreen: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark
    var initialSegment: ParkSegment

    @State private var segment: ParkSegment = .overview

    private var packState: PackState { app.packState(park.code) }
    private var isSaved: Bool { app.saved.contains(park.code) }

    var body: some View {
        VStack(spacing: 0) {
            PushHeader(backLabel: "Back", title: park.name) { app.pop() }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
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
                        case .weather: WeatherSection(park: park)
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
        }
        .background(WP.bg)
        .onAppear { segment = app.parkSegment[park.code] ?? initialSegment }
        .onChange(of: segment) { _, new in app.parkSegment[park.code] = new }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            BlobField(colors: park.c.map { Color(css: $0) }, topLight: false)
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x16100A, opacity: 0.7), location: 0),
                    .init(color: Color(hex: 0x16100A, opacity: 0.16), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom, endPoint: .top
            )
            VStack(alignment: .leading, spacing: 5) {
                Text("\(park.state) · \(park.region) · \(park.crowd)".uppercased())
                    .font(WP.body(10)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.82))
                Text(park.name)
                    .font(WP.display(38))
                    .foregroundStyle(.white)
                Text(park.tag)
                    .font(WP.bodyItalic(12.5))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, WP.gutter)
            .padding(.bottom, 15)
        }
        .frame(height: 196)
        .clipped()
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Button { app.toggleSaved(park.code) } label: {
                    Text(isSaved ? "Saved" : "Save this park")
                        .font(WP.headingUI(14))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSaved ? WP.accent100 : .clear, in: Capsule())
                        .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
                        .foregroundStyle(isSaved ? WP.accent800 : WP.text)
                }
                .buttonStyle(PressStyle(scale: 0.98))

                Button { app.startPack(park.code) } label: {
                    Text(packState == .ready ? "Pack on device"
                         : packState == .busy ? "Downloading \(Int((app.packProgress[park.code] ?? 0) * 100))%"
                         : "Offline pack · \(park.pack)")
                        .font(WP.headingUI(14))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(
                            Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(WP.neutral400)
                        )
                        .foregroundStyle(WP.accent700)
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(park.fee).font(WP.body(12.5)).opacity(0.85)
                Text("|").opacity(0.28)
                Text(park.hours).font(WP.body(12.5)).opacity(0.85)
            }
            .padding(.top, 13)

            Text("Gateway town \(park.gw)")
                .font(WP.bodyItalic(12.5)).opacity(0.62).padding(.top, 3)
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

            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Know before you go")
                ForEach(park.alerts) { alert in
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

            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Entry gates")
                ForEach(park.gates, id: \.self) { gate in
                    DividedRow(vertical: 9) {
                        Text(gate).font(WP.body(13.5)).lineSpacing(2)
                    }
                }
                Text(park.parking)
                    .font(WP.bodyItalic(12.5)).lineSpacing(3).opacity(0.7)
                    .padding(.top, 9)
            }

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

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Fuel & charging")
                fuelGroup("Gasoline", park.fuel.gas)
                fuelGroup("DC fast", park.fuel.fast)
                fuelGroup("Level 2", park.fuel.slow)
            }

            SourceLine("Overview — curated field library. Live NPS records are being re-wired onto this screen.")
        }
    }

    private func fuelGroup(_ title: String, _ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(WP.body(11.5)).foregroundStyle(WP.accent700)
            ForEach(rows, id: \.self) { row in
                Text(row).font(WP.body(12.5)).lineSpacing(2).padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Weather

struct WeatherSection: View {
    var park: CuratedPark

    private var light: WeatherLight { WeatherLight(high: park.wx.hi) }

    private var cells: [(label: String, value: String, sub: String, dot: Color)] {
        [
            ("High", "\(park.wx.hi)°", "August normal", light.color),
            ("Low", "\(park.wx.lo)°", "overnight", park.wx.lo <= 32 ? Color(oklch: 0.66, 0.13, 70) : Color(oklch: 0.60, 0.13, 150)),
            ("UV index", park.wx.uvIndex, park.wx.uvWord, uvColor),
            ("Wind", park.wx.wind, "max sustained", windColor),
            ("Sunrise", park.wx.sr.clockPadded, "first light", Color(oklch: 0.60, 0.13, 150)),
            ("Sunset", park.wx.ss.clockPadded, "last light", Color(oklch: 0.60, 0.13, 150)),
        ]
    }

    private var uvColor: Color {
        let uv = Int(park.wx.uvIndex) ?? 0
        if uv >= 11 { return Color(oklch: 0.55, 0.16, 30) }
        if uv >= 8 { return Color(oklch: 0.66, 0.13, 70) }
        return Color(oklch: 0.55, 0.09, 150)
    }

    private var windColor: Color {
        let numbers = park.wx.wind.components(separatedBy: CharacterSet.decimalDigits.inverted)
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

            Text(park.wx.note)
                .font(WP.bodyItalic(13)).lineSpacing(3).opacity(0.8)
                .padding(.top, 14)

            SourceLine("August normals from the curated library. Online, the seven-day forecast is blended in and the panel says which you are reading.")
                .padding(.top, 16)
        }
    }
}

// MARK: - Stay

struct StaySection: View {
    var park: CuratedPark

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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

            SourceLine("Campgrounds and stays — curated. Recreation.gov availability for your dates lands when the trip is live.")
        }
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

            SourceLine("Day plans — curated for this park, written around the light and the crowds.")
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

            SourceLine("Nearby units — curated. The NPS registry lookup within 160 miles is being re-wired onto this list.")
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

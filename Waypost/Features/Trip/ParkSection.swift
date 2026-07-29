import SwiftUI

/// One park on the itinerary: the plate, the heading, the tab tray, and whichever panel
/// is selected.
struct ParkSection: View {
    @Environment(TripStore.self) private var store
    var stop: Stop

    private var park: Park { stop.park }

    private var tab: ParkTab {
        store.tabByPark[park.code] ?? .overview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("\(numeral).")
                    .font(WP.heading(26, weight: .regular))
                    .foregroundStyle(WP.accent)
                    .tnum()
                Rectangle().fill(WP.divider).frame(height: 1)
                Text("\(dateRange) · \(stop.days) day\(stop.days > 1 ? "s" : "")")
                    .font(WP.body(11.5))
                    .tnum()
                    .opacity(0.6)
            }

            ParkPlate(url: store.photoByPark[park.code], name: park.name)
                .padding(.top, 14)

            Text(park.full)
                .font(WP.heading(29, weight: .regular))
                .padding(.top, 15)

            Text("\(park.tagline) · gateway \(park.gateway)")
                .font(WP.body(14))
                .italic()
                .opacity(0.75)
                .padding(.top, 8)

            if let website = safeURL(park.website) {
                Link("Official park website ↗", destination: website)
                    .font(WP.body(13.5))
                    .foregroundStyle(WP.accent700)
                    .padding(.top, 7)
            }

            HStack(spacing: 12) {
                Text(park.state).font(WP.body(13)).italic().opacity(0.75)
                Text("|").opacity(0.28)
                Text(park.fee).font(WP.body(13)).tnum().opacity(0.85)
            }
            .padding(.top, 12)

            if store.reservation(for: park)?.required == true {
                Text("Reservation required")
                    .font(WP.body(13))
                    .foregroundStyle(WP.accent700)
                    .padding(.top, 4)
            }

            tabTray.padding(.top, 18)

            Group {
                switch tab {
                case .overview: OverviewPanel(stop: stop)
                case .weather: WeatherPanel(stop: stop)
                case .stay: StayPanel(stop: stop)
                case .plan: DayPlanPanel(stop: stop)
                case .stamps: PassportPanel(stop: stop)
                case .know: KnowPanel(stop: stop)
                }
            }
            .padding(.top, 20)

            Text(sourceLine)
                .font(WP.body(11.5))
                .opacity(0.5)
                .lineSpacing(3)
                .padding(.top, 20)
                .padding(.top, 12)
                .overlay(alignment: .top) { Hairline().padding(.top, 20) }
        }
    }

    private var numeral: String {
        let index = store.order.firstIndex(of: park.code) ?? 0
        return TripStore.numeral(index)
    }

    private var dateRange: String {
        "\(WPDate.short(stop.start)) – \(WPDate.short(stop.end))"
    }

    /// Every panel names where its rows came from — the same source badge discipline the
    /// web app keeps.
    private var sourceLine: String {
        switch tab {
        case .overview:
            if park.tier == .state {
                return "Overview — bundled Wikidata record. No nationwide feed publishes hours, fees or gates for state parks."
            }
            if store.npsRefused(park) {
                return "Overview — NPS did not answer; the fees, gates and hours shown are this app's bundled record. Airports are ranked from the OurAirports dataset."
            }
            return "Overview — NPS API (fees, parking, gates) · airports ranked from the OurAirports dataset."
        case .weather:
            let day = store.weatherDay(for: park.code, iso: WPDate.iso(stop.start))
            return "Weather — \(day?.source ?? "not yet loaded")."
        case .stay:
            return "Camping & stay — NPS campgrounds, Recreation.gov availability, stays via the proxy."
        case .plan:
            return park.days.isEmpty ? "Day plan — NPS things-to-do feed." : "Day plan — curated for this park."
        case .stamps:
            return "Passport stamps — NPS API, units within 160 miles."
        case .know:
            return park.tier == .state
                ? "Know before you go — no nationwide alert feed exists for state parks."
                : "Know before you go — live NPS alerts."
        }
    }

    private var tabTray: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(ParkTab.allCases) { candidate in
                let active = candidate == tab
                Button {
                    store.tabByPark[park.code] = candidate
                } label: {
                    HStack(spacing: 5) {
                        Text(candidate.label.uppercased())
                            .font(WP.body(11))
                            .tracking(0.6)
                            .multilineTextAlignment(.center)
                        if store.isLive(candidate, for: stop) { LiveDot() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .padding(.horizontal, 5)
                    .background(active ? WP.ink : .clear)
                    .foregroundStyle(active ? WP.bg : WP.text)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WP.neutral200.opacity(0.62))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(WP.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

}

/// The framed photograph. A park with no published photo gets the frame and a line
/// saying so — not a stock image standing in for one.
struct ParkPlate: View {
    var url: URL?
    var name: String

    var body: some View {
        ZStack {
            WP.neutral200
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder("Photograph could not be loaded")
                    case .empty:
                        ProgressView().tint(WP.accent)
                    @unknown default:
                        placeholder("Photograph could not be loaded")
                    }
                }
            } else {
                placeholder("No photograph published for \(name)")
            }
        }
        .frame(height: 184)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WP.divider, lineWidth: 1))
        .padding(6)
        .background(WP.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(WP.body(12))
            .italic()
            .opacity(0.5)
            .multilineTextAlignment(.center)
            .padding()
    }
}

// MARK: - Overview

struct OverviewPanel: View {
    @Environment(TripStore.self) private var store
    var stop: Stop
    private var park: Park { stop.park }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let reservation = store.reservation(for: park) {
                if reservation.required {
                    CardBox(borderColor: WP.accent) {
                        HStack(alignment: .firstTextBaseline) {
                            Kicker(text: "Reserve before you arrive")
                            Spacer(minLength: 8)
                            Tag(text: store.factsByPark[park.code] == nil ? "Curated" : "Live — NPS",
                                style: .neutral,
                                showsLiveDot: store.factsByPark[park.code] != nil)
                        }
                        Text(reservation.note).font(WP.body(13.5)).lineSpacing(3)
                    }
                } else {
                    Text(reservation.note)
                        .font(WP.body(13.5))
                        .italic()
                        .opacity(0.75)
                        .lineSpacing(3)
                }
            }

            if !park.gates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Entry gates")
                    ForEach(park.gates, id: \.self) { gate in
                        Text(gate)
                            .font(WP.body(14))
                            .lineSpacing(2)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { Hairline() }
                    }
                }
            }

            let parking = store.parking(for: park)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Parking", badge: parking.badge, live: !parking.lots.isEmpty)
                if parking.lots.isEmpty {
                    Text(parking.note.isEmpty ? "NPS publishes no parking detail for this park." : parking.note)
                        .font(WP.body(13.5))
                        .italic()
                        .opacity(0.7)
                        .lineSpacing(3)
                } else {
                    ForEach(parking.lots) { lot in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lot.name).font(WP.body(14))
                            if let detail = lot.whereText, !detail.isEmpty {
                                Text(detail).font(WP.body(12.5)).opacity(0.7).lineSpacing(2)
                            }
                        }
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Hours · fee")
                Text("\(park.hours) · \(park.fee)").font(WP.body(14)).lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Fly-in airports")
                ForEach(store.flyInAirports(for: park)) { airport in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(airport.code)
                            .font(WP.heading(19, weight: .regular))
                            .frame(minWidth: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(airport.name).font(WP.body(13.5)).lineSpacing(2)
                            Text(airport.drive).font(WP.body(12.5)).tnum().opacity(0.6)
                            if !airport.note.isEmpty {
                                Text(airport.note).font(WP.body(12)).italic().opacity(0.6)
                            }
                        }
                        Spacer(minLength: 0)
                        if airport.best == true { Tag(text: "Best", style: .accent) }
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }

            let fuel = store.fuel(for: park)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Fuel & charging", badge: fuel.badge, live: fuel.badge.hasPrefix("Live"))
                fuelGroup("Gasoline", fuel.gas, emptyNote: "No stations published within 9 miles of the gateway.")
                fuelGroup("DC fast", fuel.fast, emptyNote: "No fast-charging record for this park — check PlugShare.")
                fuelGroup("Level 2 (slow)", fuel.slow, emptyNote: nil)
            }
        }
    }

    @ViewBuilder
    private func fuelGroup(_ title: String, _ rows: [String], emptyNote: String?) -> some View {
        if !rows.isEmpty || emptyNote != nil {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(WP.body(12)).foregroundStyle(WP.accent700)
                if rows.isEmpty {
                    if let emptyNote {
                        Text(emptyNote).font(WP.body(13)).italic().opacity(0.62)
                    }
                } else {
                    ForEach(rows, id: \.self) { row in
                        Text(row).font(WP.body(13)).lineSpacing(2).padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Weather

struct WeatherPanel: View {
    @Environment(TripStore.self) private var store
    var stop: Stop

    private var day: WeatherDay? {
        store.weatherDay(for: stop.park.code, iso: WPDate.iso(stop.start))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Conditions for \(WPDate.short(stop.start))")
                .font(WP.body(14))
                .italic()
                .opacity(0.78)

            if let day {
                HStack(spacing: 10) {
                    Tag(text: badge(day), style: .neutral, showsLiveDot: !day.isNormals)
                    if let light = lightLabel(day) {
                        HStack(spacing: 8) {
                            Circle().fill(WP.accent400).frame(width: 10, height: 10)
                            Text(light).font(WP.body(13))
                        }
                    }
                }
                .padding(.top, 8)

                let columns = [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(cells(day), id: \.label) { cell in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle().fill(cell.dot).frame(width: 7, height: 7)
                                Text(cell.label.uppercased())
                                    .font(WP.body(10.5))
                                    .tracking(1.1)
                                    .opacity(0.65)
                            }
                            Text(cell.value).font(WP.heading(22, weight: .regular)).tnum()
                            if let sub = cell.sub {
                                Text(sub).font(WP.body(11)).opacity(0.6)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { Hairline() }

                if let note = day.note ?? day.shortForecast {
                    Text(note)
                        .font(WP.body(13.5))
                        .italic()
                        .lineSpacing(3)
                        .opacity(0.8)
                        .padding(.top, 14)
                }
            } else {
                Text("Weather has not answered yet for these dates. Nothing is shown until it does — no seasonal stand-in.")
                    .font(WP.body(13.5))
                    .italic()
                    .opacity(0.7)
                    .lineSpacing(3)
                    .padding(.top, 10)
            }
        }
    }

    private func badge(_ day: WeatherDay) -> String {
        day.isNormals
            ? "\(day.years ?? 10)-year normals — \(day.source)"
            : "Live — \(day.source)"
    }

    private func lightLabel(_ day: WeatherDay) -> String? {
        guard let sunrise = day.sunrise, let sunset = day.sunset else { return nil }
        return "Light \(sunrise) – \(sunset)"
    }

    private struct Cell {
        var label: String
        var value: String
        var sub: String?
        var dot: Color
    }

    private func cells(_ day: WeatherDay) -> [Cell] {
        var rows: [Cell] = [
            Cell(label: "High", value: "\(day.hi)°", sub: day.isNormals ? "10-year mean" : nil, dot: WP.accent500),
            Cell(label: "Low", value: "\(day.lo)°", sub: day.isNormals ? "10-year mean" : nil, dot: WP.neutral500),
            Cell(label: day.isNormals ? "Wet days" : "Precipitation", value: day.precip, sub: nil, dot: WP.accent300),
            Cell(label: "Wind", value: day.wind, sub: nil, dot: WP.neutral400),
        ]
        if let uv = day.uv {
            rows.append(Cell(label: "UV index", value: "\(uv)",
                             sub: day.uvModelled ? "· modelled from solar geometry" : nil,
                             dot: WP.accent600))
        }
        if let humidity = day.humidity {
            rows.append(Cell(label: "Humidity", value: humidity, sub: nil, dot: WP.neutral300))
        }
        return rows
    }
}

// MARK: - Camping & stay

struct StayPanel: View {
    @Environment(TripStore.self) private var store
    var stop: Stop
    private var park: Park { stop.park }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Campgrounds", badge: store.campgroundBadge(for: park),
                             live: !(store.campsByPark[park.code] ?? []).isEmpty)

                let camps = store.campsByPark[park.code] ?? []
                if camps.isEmpty {
                    Text(park.tier == .state
                         ? "No nationwide campsite feed covers state parks. Check the park website for camping."
                         : "No campground is published for this park.")
                        .font(WP.body(13.5))
                        .italic()
                        .opacity(0.7)
                        .lineSpacing(3)
                        .padding(.top, 8)
                } else {
                    ForEach(camps) { camp in
                        campRow(camp)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Lodges & hotels", badge: store.stayBadge(for: park),
                             live: store.proxy.isConnected && !(store.staysByPark[park.code] ?? []).isEmpty)

                let stays = store.staysByPark[park.code] ?? []
                if stays.isEmpty {
                    Text(store.proxy.isConnected
                         ? "No stays published near this gateway."
                         : "Connect the data proxy to pull stays for your dates.")
                        .font(WP.body(13.5))
                        .italic()
                        .opacity(0.7)
                        .padding(.top, 8)
                } else {
                    ForEach(stays) { stay in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                if let link = safeURL(stay.link) {
                                    Link(destination: link) {
                                        Text("\(stay.name) ↗")
                                            .font(WP.heading(18, weight: .regular))
                                            .foregroundStyle(WP.text)
                                    }
                                } else {
                                    Text(stay.name).font(WP.heading(18, weight: .regular))
                                }
                                Spacer(minLength: 8)
                                if let price = stay.price {
                                    Text(price).font(WP.body(13)).tnum().foregroundStyle(WP.accent700)
                                }
                            }
                            if let sub = [stay.whereText, stay.note].compactMap({ $0 }).filter({ !$0.isEmpty }).first {
                                Text(sub).font(WP.body(12.5)).opacity(0.75).lineSpacing(2)
                            }
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
            }
        }
    }

    private func campRow(_ camp: Campground) -> some View {
        let level = store.availability(park: park.code, campground: camp.name, start: stop.start)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if let link = camp.link {
                    Link(destination: link) {
                        Text("\(camp.name) ↗")
                            .font(WP.heading(18, weight: .regular))
                            .foregroundStyle(WP.text)
                    }
                } else {
                    Text(camp.name).font(WP.heading(18, weight: .regular))
                }
                Spacer(minLength: 8)
                Tag(text: camp.src, style: .neutral)
            }
            Text("\(camp.whereText) · \(camp.sites) · \(camp.price)")
                .font(WP.body(12.5))
                .tnum()
                .opacity(0.75)
                .lineSpacing(2)
            HStack(spacing: 9) {
                Tag(text: level.text, style: availabilityStyle(level))
                Text(camp.status).font(WP.body(12.5)).italic().foregroundStyle(WP.accent700)
            }
            .padding(.top, 3)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func availabilityStyle(_ level: AvailabilityLevel) -> Tag.Style {
        switch level {
        case .open: return .accent
        case .partial: return .accent
        case .none, .firstCome, .unknown: return .neutral
        }
    }
}

// MARK: - Day plan

struct DayPlanPanel: View {
    @Environment(TripStore.self) private var store
    var stop: Stop

    var body: some View {
        let plans = store.dayPlans(for: stop)
        VStack(alignment: .leading, spacing: 12) {
            if plans.isEmpty {
                Text("No day plan yet — NPS publishes the activity feed through the proxy, and this park has not answered. Nothing is invented to fill the space.")
                    .font(WP.body(13.5))
                    .italic()
                    .opacity(0.7)
                    .lineSpacing(3)
            } else {
                ForEach(Array(plans.enumerated()), id: \.offset) { index, plan in
                    CardBox {
                        Kicker(text: "Day \(index + 1) · \(WPDate.short(WPDate.addDays(stop.start, index)))")
                        Text(plan.title).font(WP.heading(19, weight: .regular))
                        ForEach(plan.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Text(item.time)
                                    .font(WP.body(12))
                                    .tnum()
                                    .foregroundStyle(WP.accent700)
                                    .frame(minWidth: 52, alignment: .leading)
                                Text(item.text).font(WP.body(13)).lineSpacing(2)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { Hairline() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Passport stamps (next pass)

struct PassportPanel: View {
    var stop: Stop

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The passport pages beyond the big parks — monuments, historic sites and memorials within striking distance of \(stop.park.name).")
                .font(WP.body(13.5))
                .italic()
                .opacity(0.8)
                .lineSpacing(3)
            Text("Not built in this pass. The nearby-units lookup lands with the next release; until then this panel stays empty rather than showing a guess.")
                .font(WP.body(13))
                .opacity(0.62)
                .lineSpacing(3)
        }
    }
}

// MARK: - Know before you go

struct KnowPanel: View {
    @Environment(TripStore.self) private var store
    var stop: Stop
    private var park: Park { stop.park }

    private func badge(alerts: [Alert], refused: Bool) -> String {
        if refused { return store.proxy.isConnected ? "Source did not answer" : "Needs the proxy" }
        if alerts.isEmpty { return park.tier == .state ? "No feed exists" : "None published" }
        return "Live — NPS"
    }

    var body: some View {
        let answered = store.alertsByPark[park.code]
        let alerts = answered ?? []
        let refused = store.npsRefused(park) && answered == nil
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Know before you go",
                         badge: badge(alerts: alerts, refused: refused),
                         live: store.alertsAreLive.contains(park.code))

            if alerts.isEmpty {
                Text(park.tier == .state
                     ? "No nationwide alert feed exists for state parks, so none are shown. Another park's warnings are never borrowed to fill the gap."
                     : refused
                       ? "NPS did not answer, so no alerts are shown. This is not the same as there being none — check the park page before you travel."
                       : "NPS publishes no current alerts for this park.")
                    .font(WP.body(13.5))
                    .italic()
                    .opacity(0.72)
                    .lineSpacing(3)
                    .padding(.top, 6)
            } else {
                ForEach(alerts) { alert in
                    VStack(alignment: .leading, spacing: 5) {
                        Tag(text: alert.cat, style: .outline)
                        Text(alert.title).font(WP.heading(18, weight: .regular)).padding(.top, 2)
                        if !alert.body.isEmpty {
                            Text(alert.body).font(WP.body(13)).opacity(0.8).lineSpacing(3)
                        }
                    }
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }

            Text("Timed-entry deadlines and calendar exports arrive with the next pass.")
                .font(WP.body(12.5))
                .italic()
                .opacity(0.55)
                .padding(.top, 12)
        }
    }
}

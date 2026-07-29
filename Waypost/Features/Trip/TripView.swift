import MapKit
import SwiftUI

/// The composed itinerary: the route, the legs between parks, and a section per park.
struct TripView: View {
    @Environment(TripStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: "Field itinerary", subtitle: nil) {
                Button { store.backToPlan() } label: {
                    Text("← Edit")
                        .font(WP.body(13))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.bg.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } trailing: {
                Color.clear.frame(width: 44, height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statsGrid.padding(.top, 4)

                    if let budget = store.budgetLine {
                        Text(budget)
                            .font(WP.body(12.5))
                            .italic()
                            .tnum()
                            .opacity(0.7)
                            .padding(.top, 12)
                    }
                    Text(store.liveNote)
                        .font(WP.body(12.5))
                        .italic()
                        .opacity(0.55)
                        .padding(.top, 6)

                    if let failure = store.failures.summary {
                        Text(failure)
                            .font(WP.body(12.5))
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WP.accent100)
                            .foregroundStyle(WP.accent800)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 10)
                    }

                    routeMap.padding(.top, 18)

                    if !store.warnings.isEmpty { fieldNotes.padding(.top, 18) }

                    ForEach(store.timeline) { entry in
                        switch entry {
                        case .leg(let leg): LegSection(leg: leg).padding(.top, 38)
                        case .park(let stop): ParkSection(stop: stop).padding(.top, 44)
                        }
                    }

                    Hairline().padding(.top, 44)
                    sources.padding(.top, 18)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, WP.gutter)
            }
        }
        .background(WP.bg)
        .refreshable { await store.fetchLive() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.tripDates.uppercased())
                .font(WP.body(10.5))
                .tracking(1.5)
                .foregroundStyle(WP.accent)
                .padding(.top, 20)
            Text(store.routeLine)
                .font(WP.heading(30, weight: .regular))
                .padding(.top, 9)
                .padding(.bottom, 16)
        }
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(store.stats) { stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.label.uppercased())
                        .font(WP.body(10))
                        .tracking(1.2)
                        .opacity(0.6)
                    Text(stat.value)
                        .font(WP.heading(21, weight: .regular))
                        .tnum()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
        .overlay(alignment: .top) { Hairline() }
    }

    private var fieldNotes: some View {
        CardBox(borderColor: WP.accent300) {
            Kicker(text: "Field notes on this plan")
            ForEach(store.warnings, id: \.self) { note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("※").font(WP.heading(15)).foregroundStyle(WP.accent700)
                    Text(note).font(WP.body(13)).lineSpacing(3)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    private var routeMap: some View {
        CardBox {
            Kicker(text: "The route · dotted line home")
            RouteMap(schedule: store.schedule)
                .frame(height: 236)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var sources: some View {
        Text("Sources — weather & sun: NWS inside 7 days + Open-Meteo to 16 days, real 10-year climate normals beyond. Alerts, campgrounds, fees, parking & photography: NPS API. Campsite availability: Recreation.gov. Drive times & mileage: OSRM open routing. Fuel: OpenStreetMap. Stays & EV charging: via the Waypost proxy. Always confirm before travel.")
            .font(WP.body(11.5))
            .italic()
            .lineSpacing(4)
            .opacity(0.55)
    }
}

/// The route drawn on a real map — the phone has MapKit, so it gets the actual roads
/// rather than the web app's d3 state outline.
struct RouteMap: View {
    var schedule: Schedule

    private var points: [(name: String, coordinate: CLLocationCoordinate2D, isOrigin: Bool)] {
        var rows: [(String, CLLocationCoordinate2D, Bool)] = [(
            schedule.city.shortName,
            CLLocationCoordinate2D(latitude: schedule.city.lat, longitude: schedule.city.lon),
            true
        )]
        rows += schedule.stops.map {
            ($0.park.name, CLLocationCoordinate2D(latitude: $0.park.lat, longitude: $0.park.lon), false)
        }
        return rows.map { (name: $0.0, coordinate: $0.1, isOrigin: $0.2) }
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            if points.count > 1 {
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(WP.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                if schedule.home != nil, let first = points.first, let last = points.last {
                    MapPolyline(coordinates: [last.coordinate, first.coordinate])
                        .stroke(WP.accent300, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
                }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                Annotation(point.name, coordinate: point.coordinate) {
                    Circle()
                        .fill(point.isOrigin ? WP.accent700 : WP.bg)
                        .frame(width: point.isOrigin ? 9 : 11, height: point.isOrigin ? 9 : 11)
                        .overlay(Circle().stroke(WP.accent700, lineWidth: 1.8))
                }
                .annotationTitles(.automatic)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    /// Framed on every stop with a margin, so the whole route is visible at a glance.
    private var region: MKCoordinateRegion {
        let lats = points.map(\.coordinate.latitude)
        let lons = points.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39, longitude: -105),
                                      span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(1.4, (maxLat - minLat) * 1.6),
                                   longitudeDelta: max(1.4, (maxLon - minLon) * 1.6))
        )
    }
}

/// One travel leg: the road option, and the air option when a real one exists.
struct LegSection: View {
    var leg: LegPresentation
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(leg.kicker.uppercased())
                    .font(WP.body(10.5))
                    .tracking(1.5)
                    .foregroundStyle(WP.accent)
                Rectangle().fill(WP.divider).frame(height: 1)
                Text(leg.dateText).font(WP.body(11.5)).tnum().opacity(0.6)
            }
            Text("\(leg.fromName) → \(leg.toName)")
                .font(WP.heading(22, weight: .regular))
                .padding(.top, 9)
                .padding(.bottom, 14)

            VStack(spacing: 12) {
                CardBox(borderColor: leg.driveRecommended ? WP.accent300 : WP.divider) {
                    HStack(alignment: .firstTextBaseline) {
                        Kicker(text: "By road")
                        Tag(text: leg.roadBadge, style: .neutral, showsLiveDot: leg.roadIsLive)
                        Spacer(minLength: 0)
                        if leg.driveRecommended { Tag(text: "Recommended", style: .accent) }
                    }
                    Text("\(leg.miles.formatted(.number)) mi · \(leg.drive)")
                        .font(WP.heading(19, weight: .regular))
                        .tnum()
                    Text(leg.route)
                        .font(WP.body(13))
                        .opacity(0.8)
                        .lineSpacing(3)

                    if let caveat = leg.driveCaveat {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caveat)
                                .font(WP.body(13))
                                .italic()
                                .foregroundStyle(WP.accent700)
                            if let url = leg.flightSearchURL {
                                Button("Search flights ↗") { openURL(url) }
                                    .font(WP.body(13))
                                    .foregroundStyle(WP.accent700)
                            }
                        }
                    }

                    if leg.showChargers && !leg.chargers.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Hairline()
                            HStack(spacing: 8) {
                                Text("Fast-charging stops".uppercased())
                                    .font(WP.body(11))
                                    .tracking(1.3)
                                    .opacity(0.65)
                                Tag(text: leg.chargeBadge, style: .neutral, showsLiveDot: leg.chargersLive)
                            }
                            ForEach(leg.chargers, id: \.self) { charger in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("⚡").foregroundStyle(WP.accent)
                                    Text(charger).font(WP.body(13)).lineSpacing(2)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                if leg.flyAvailable {
                    CardBox(borderColor: leg.flyRecommended ? WP.accent300 : WP.divider) {
                        HStack(alignment: .firstTextBaseline) {
                            Kicker(text: "By air")
                            Spacer(minLength: 0)
                            if leg.flyRecommended { Tag(text: "Recommended", style: .accent) }
                        }
                        Text(leg.flyVia).font(WP.heading(19, weight: .regular)).tnum()
                        if !leg.flyTime.isEmpty {
                            Text(leg.flyTime).font(WP.body(13)).opacity(0.8)
                        }
                        if !leg.flyNote.isEmpty {
                            Text(leg.flyNote).font(WP.body(13)).italic().opacity(0.8)
                        }
                    }
                }
            }
        }
    }
}

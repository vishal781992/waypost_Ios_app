import MapKit
import SwiftUI

/// Trips — what is on the books, and what is behind you.
struct TripsScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.myTrips.isEmpty
                             ? "One trip on the books, one in the field."
                             : "\(app.trips.count) trips on the books.")
                            .kickerStyle()
                        Text("Trips").font(WP.display(31))
                    }
                    Spacer(minLength: 0)
                    newTripButton
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("On the books".uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.5)
                        .padding(.bottom, 10)

                    VStack(spacing: 14) {
                        ForEach(app.trips) { trip in
                            TripCard(trip: trip).liftOnScroll()
                        }
                    }

                    Text("Behind you".uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.5)
                        .padding(.top, 26)
                        .padding(.bottom, 4)

                    ForEach(SavedTrip.past, id: \.title) { past in
                        Button {
                            app.show("Past trips are read-only in this pass")
                        } label: {
                            DividedRow(vertical: 13) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(past.title).font(WP.rowTitle(17))
                                        Text(past.sub).font(WP.body(12)).opacity(0.6)
                                    }
                                    Spacer(minLength: 0)
                                    Text(past.dates).font(WP.body(11.5)).opacity(0.5)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(WP.accent700)
                                }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }

                    Text("Trips live on this iPhone. A shared trip opens read-only for whoever you send it to.")
                        .font(WP.bodyItalic(11.5))
                        .lineSpacing(3)
                        .opacity(0.5)
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 18)
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var newTripButton: some View {
        Button {
            app.startBuilder()
        } label: {
            ZStack {
                WP.ink
                ButtonGlow(strong: true)
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(WP.bg)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
    }
}

/// A trip on the shelf: its tag, dates, the route drawn as a dotted polyline from real
/// coordinates, and the parks in visiting order.
struct TripCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    var trip: SavedTrip

    private var points: [(lat: Double, lon: Double)] {
        let origin = app.library.city(trip.origin)
        let parks = trip.codes.compactMap { app.library.park($0) }
        return ([origin.map { (lat: $0.lat, lon: $0.lon) }].compactMap { $0 })
            + parks.map { (lat: $0.lat, lon: $0.lon) }
    }

    @State private var confirmingDelete = false

    var body: some View {
        // The delete control sits over the card rather than inside its button, so the
        // tap target is its own and does not open the trip on the way past.
        ZStack(alignment: .topTrailing) {
            cardButton
            deleteButton.padding(10)
        }
        .confirmationDialog("Remove this trip?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove trip", role: .destructive) { app.deleteTrip(trip.id) }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("\(trip.title) and its day plans come off this iPhone. This cannot be undone.")
        }
    }

    /// A liquid-glass disc, so it reads as chrome floating over the card rather than
    /// another row of content.
    private var deleteButton: some View {
        Button {
            confirmingDelete = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WP.danger)
                .frame(width: 34, height: 34)
                .liquidGlass(.pill, radius: 999, interactive: true)
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel("Remove \(trip.title)")
    }

    private var cardButton: some View {
        Button {
            app.push(.trip(id: trip.id))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text(trip.tag)
                        .font(WP.body(11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(trip.live ? WP.accent100 : WP.neutral100, in: Capsule())
                        .foregroundStyle(trip.live ? WP.accent800 : WP.neutral800)
                    Spacer(minLength: 0)
                    Text(trip.dates).font(WP.body(11.5)).opacity(0.6)
                        .padding(.trailing, 38)
                }

                Text(trip.title).font(WP.heading(23)).padding(.top, 9)
                    .multilineTextAlignment(.leading)
                Text(trip.route).font(WP.bodyItalic(12.5)).opacity(0.65).padding(.top, 4)
                    .multilineTextAlignment(.leading)

                RouteMapPlate(points: points)
                    .frame(height: 132)
                    .padding(.top, 11)

                Hairline().padding(.top, 9)

                FlowRow(spacing: 14, rowSpacing: 5) {
                    ForEach(Array(trip.codes.enumerated()), id: \.element) { index, code in
                        HStack(spacing: 5) {
                            Text(["I", "II", "III", "IV", "V"][min(index, 4)])
                                .font(WP.headingUI(12))
                                .foregroundStyle(WP.accent700)
                            Text(app.library.park(code)?.name ?? code).font(WP.body(12))
                        }
                    }
                }
                .padding(.top, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.top, 15)
            .padding(.bottom, 13)
            .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WP.divider, lineWidth: 1))
            .zoomSource("trip:" + trip.id, in: zoom)
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .contextMenu {
            Button {
                app.push(.trip(id: trip.id))
            } label: {
                Label("Open the itinerary", systemImage: "arrow.up.forward.square")
            }
            Button {
                app.show("Sharing sends a read-only copy")
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Remove trip", systemImage: "trash")
            }
        }
    }
}

/// The route on a real map.
///
/// MapKit has no monochrome style, so the map is rendered normally and desaturated in
/// the view: `saturation(0)` with a touch of contrast to hold the coastlines. The result
/// is a grey basemap that sits inside the Classical palette instead of fighting it, and
/// leaves the brass route line as the only colour on the plate.
///
/// It is a picture, not a map to explore — no interaction modes, so a drag over it
/// scrolls the list underneath.
struct RouteMapPlate: View {
    var points: [(lat: Double, lon: Double)]

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        // The basemap is desaturated, the route is not — so the filter is applied to the
        // map alone and the line is drawn over it, projected through MapReader.
        MapReader { proxy in
            Map(initialPosition: .region(region), interactionModes: [])
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .saturation(0)
                .contrast(1.04)
                .overlay {
                    RouteOverlay(coordinates: coordinates, proxy: proxy)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(WP.divider, lineWidth: 1))
        .allowsHitTesting(false)
    }

    /// Framed on every stop with a margin, so the whole route reads at a glance.
    private var region: MKCoordinateRegion {
        let lats = points.map(\.lat), lons = points.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39, longitude: -105),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(1.2, (maxLat - minLat) * 1.7),
                                   longitudeDelta: max(1.2, (maxLon - minLon) * 1.7))
        )
    }
}

/// The route, drawn over the map rather than inside it: the map carries a greyscale
/// filter, and anything drawn as map content would be greyed with it.
struct RouteOverlay: View {
    var coordinates: [CLLocationCoordinate2D]
    var proxy: MapProxy

    var body: some View {
        GeometryReader { _ in
            let points = coordinates.compactMap { proxy.convert($0, to: .local) }
            if points.count == coordinates.count, points.count > 1 {
                Path { path in
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(WP.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == 0 ? WP.accent700 : WP.bg)
                        .overlay(Circle().stroke(WP.accent700, lineWidth: 1.5))
                        .frame(width: index == 0 ? 6 : 8, height: index == 0 ? 6 : 8)
                        .position(point)
                }
            }
        }
    }
}

/// A wrapping row — the parks list on a trip card flows onto a second line when it must.
struct FlowRow: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

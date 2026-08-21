import MapKit
import SwiftUI

/// Trips — what is on the books, and what is behind you.
struct TripsScreen: View {
    @Environment(AppState.self) private var app

    /// Counted, not asserted. With the seed trip gone this read "One trip on the books,
    /// one in the field" over a screen that said "No trips yet".
    private var kicker: String {
        let planned = app.trips.count
        let visited = app.visitedParks.count
        if planned == 0 && visited == 0 { return "Nothing planned yet" }
        var parts: [String] = []
        if planned > 0 { parts.append("\(planned) trip\(planned == 1 ? "" : "s") on the books") }
        if visited > 0 { parts.append("\(visited) park\(visited == 1 ? "" : "s") behind you") }
        return parts.joined(separator: ", ")
    }


    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kicker).kickerStyle()
                        Text("Trips").font(WP.displayBold(44)).tracking(-0.4)
                    }
                    Spacer(minLength: 0)
                    newTripButton
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if app.trips.isEmpty {
                        NoTripsYet()
                    } else {
                        Text("On the books".uppercased())
                            .font(WP.body(10)).tracking(1.4).opacity(0.5)
                            .padding(.bottom, 10)

                        VStack(spacing: 14) {
                            ForEach(app.trips) { trip in
                                TripCard(trip: trip).liftOnScroll()
                            }
                        }
                    }

                    // Behind you is where you have actually been — a park with a
                    // cancellation stamp against it. Nothing invented, and nothing at all
                    // until the first stamp is collected.
                    if !app.visitedParks.isEmpty {
                        Text("Behind you".uppercased())
                            .font(WP.body(10)).tracking(1.4).opacity(0.5)
                            .padding(.top, 26)
                            .padding(.bottom, 4)

                        ForEach(app.visitedParks) { park in
                        Button {
                            app.openPark(park.code)
                        } label: {
                            DividedRow(vertical: 13) {
                                HStack(spacing: 12) {
                                    ParkImage(park: park, showsScrim: false, topLight: false)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(park.name).font(WP.rowTitle(17))
                                        Text([park.stateName, park.designationLabel]
                                                .filter { !$0.isEmpty }
                                                .joined(separator: " · "))
                                            .font(WP.body(12)).opacity(0.6)
                                    }
                                    Spacer(minLength: 0)
                                    Text("Stamped").font(WP.body(11.5)).opacity(0.5)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(WP.accent700)
                                }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }

                    Text("A shared trip opens read-only for whoever you send it to.")
                        .font(WP.bodyItalic(11.5))
                        .lineSpacing(3)
                        .opacity(0.5)
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 18)
                .padding(.bottom, WP.rootScrollBottom)
            }
            .tracksTabBarMinimize()
            .scrollIndicators(.hidden)
            .captureScrollPosition()
        }
    }

    private var newTripButton: some View {
        Button {
            // Straight into the builder. This opened the park finder, so `+` on the Trips
            // tab answered "which park?" and then needed "Plan a trip instead" to get to
            // what was being asked for — while the empty state's own button on this very
            // screen already went directly. Planning a trip is what this tab is for.
            app.startBuilder()
        } label: {
            // The mark's orange, same as the round controls on the other tabs — this is the
            // one button on the screen that starts something, and it was the ink plate, so
            // it read as chrome rather than as the thing to press.
            ZStack {
                WP.mark
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            }
        }
        .buttonStyle(PressStyle(scale: 0.92))
    }
}

/// Nothing planned at all — the design gives this its own screen rather than an empty
/// list, because the first trip is the whole point of the app.
struct NoTripsYet: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("I")
                .font(WP.display(25))
                .foregroundStyle(WP.accent700)
                .frame(width: 64, height: 64)
                .overlay(
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(WP.accent400)
                )

            Text("No trips yet.").font(WP.display(27)).padding(.top, 17)
            Text("Pick the parks and say when. ParkHop works out the order, the mileage and which permit windows you have to be awake for.")
                .font(WP.body(13.5)).lineSpacing(3).opacity(0.78).padding(.top, 9)
                .fixedSize(horizontal: false, vertical: true)

            GlowButton(title: "Plan the first one", minHeight: 50) { app.startBuilder() }
                .padding(.top, 20)

            Text("Saved parks are the usual place to start — Explore keeps them for you.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 14)
        }
        .padding(.top, 30)
    }
}

/// A trip on the shelf: its tag, dates, the route drawn as a dotted polyline from real
/// coordinates, and the parks in visiting order.
struct TripCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    var trip: SavedTrip

    private var points: [(lat: Double, lon: Double)] {
        let origin = trip.resolvedOrigin(app.library)
        let parks = trip.codes.compactMap { app.park($0) }
        return ([origin.map { (lat: $0.lat, lon: $0.lon) }].compactMap { $0 })
            + parks.map { (lat: $0.lat, lon: $0.lon) }
    }

    /// The trip as stretches, each knowing how it is travelled.
    ///
    /// This used to flatten every leg into one continuous line, dropping the repeated point
    /// where legs meet at a park so the path did not double back. Each stretch is stroked
    /// separately now, so a shared endpoint costs nothing and the flattening is gone with
    /// the thing that needed it.
    ///
    /// A driven leg is one road. A flown leg is three: the drive to the airport, the
    /// flight, and the drive from the far airport to the park — which on a leg like
    /// Chicago to Yellowstone is 327 miles and most of a day, and was previously drawn as
    /// part of one unbroken road line running the whole way.
    private var routeLegs: [RouteLeg] {
        let legs = app.routing.legs(for: trip)
        guard !legs.isEmpty else { return [] }

        var out: [RouteLeg] = []
        for leg in legs {
            guard let path = leg.flightPath else {
                out.append(RouteLeg(.road, leg.coordinates.map(Self.coordinate)))
                continue
            }
            let departure = CLLocationCoordinate2D(latitude: path.departure.lat,
                                                   longitude: path.departure.lon)
            let arrival = CLLocationCoordinate2D(latitude: path.arrival.lat,
                                                 longitude: path.arrival.lon)
            if path.drawsOriginStub {
                out.append(Self.drive(path.toAirport, from: path.origin,
                                      to: (path.departure.lat, path.departure.lon)))
            }
            out.append(RouteLeg(.air, [departure, arrival]))
            if path.drawsArrivalStub {
                out.append(Self.drive(path.fromAirport, from: (path.arrival.lat, path.arrival.lon),
                                      to: path.destination))
            }
        }
        return out
    }

    /// A drive as the router gave it, or the straight line the app already uses to say a
    /// road has not been measured. Never a straight line drawn as though it were a road.
    private static func drive(_ routed: [(lat: Double, lon: Double)],
                              from: (lat: Double, lon: Double),
                              to: (lat: Double, lon: Double)) -> RouteLeg {
        routed.count > 1
            ? RouteLeg(.road, routed.map(coordinate))
            : RouteLeg(.provisional, [coordinate(from), coordinate(to)])
    }

    private static func coordinate(_ point: (lat: Double, lon: Double)) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    /// Every airport this trip actually passes through, in order.
    private var airports: [(lat: Double, lon: Double)] {
        app.routing.legs(for: trip).compactMap(\.flightPath).flatMap {
            [($0.departure.lat, $0.departure.lon), ($0.arrival.lat, $0.arrival.lon)]
        }
    }

    @State private var confirmingDelete = false

    var body: some View {
        // The delete control sits over the card rather than inside its button, so the
        // tap target is its own and does not open the trip on the way past.
        cardButton
        // The roads, asked for by the card that draws them. Routing used to be kicked off
        // by the trip's own screen alone, so the shelf could only ever draw the straight
        // line — and a reader who never opened a trip never saw its actual drive. `route`
        // returns early when the legs are already cached, so this costs nothing on the way
        // back from the detail screen.
        .task(id: trip.id) {
            let parks = trip.codes.compactMap { app.park($0) }
            guard !parks.isEmpty else { return }
            app.routing.route(trip, parks: parks, origin: trip.resolvedOrigin(app.library))
        }
        .confirmationDialog("Remove this trip?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove trip", role: .destructive) { app.deleteTrip(trip.id) }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("\(trip.title) and its day plans are removed. This cannot be undone.")
        }
    }

    /// Reopens the builder on this trip — its parks, its dates, its days in each park.
    private var editButton: some View {
        Button {
            app.editTrip(trip)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(WP.onInk)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel("Edit \(trip.title)")
    }

    /// A liquid-glass disc, so it reads as chrome floating over the card rather than
    /// another row of content.
    private var deleteButton: some View {
        Button {
            confirmingDelete = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(WP.onInk)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 0.5))
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
                        .background(.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.5))
                    Spacer(minLength: 0)
                    Text(trip.dates).font(WP.body(11.5)).opacity(0.62)
                }

                Text(trip.title).font(WP.display(23)).padding(.top, 9)
                    .multilineTextAlignment(.leading)
                Text(trip.route).font(WP.bodyItalic(12.5)).opacity(0.68).padding(.top, 4)
                    .multilineTextAlignment(.leading)

                RouteMapPlate(id: trip.id, points: points, legs: routeLegs, airports: airports)
                    .frame(height: 132)
                    .padding(.top, 11)

                Rectangle().fill(.white.opacity(0.18)).frame(height: 1).padding(.top, 9)

                HStack(alignment: .center, spacing: 10) {
                    FlowRow(spacing: 14, rowSpacing: 5) {
                        ForEach(Array(trip.codes.enumerated()), id: \.element) { index, code in
                            HStack(spacing: 5) {
                                Text(["I", "II", "III", "IV", "V"][min(index, 4)])
                                    .font(WP.display(13))
                                    .foregroundStyle(WP.accent400)
                                Text(app.park(code)?.name ?? code)
                                    .font(WP.body(12)).opacity(0.92)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    // Correcting a trip used to mean deleting it and picking every park
                    // again. Beside the control that removes it, the one that changes it.
                    editButton
                    deleteButton
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.top, 15)
            .padding(.bottom, 13)
            .background {
                // Round 2 puts the trip on an ink plate with its own weather inside it:
                // a dusk bloom top-left, a brass one bottom-right, a lit top edge.
                ZStack {
                    Color(hex: 0x231F1D)
                    Ellipse().fill(Color(oklch: 0.55, 0.10, 250)).opacity(0.34)
                        .frame(width: 240, height: 190).offset(x: -110, y: -80).blur(radius: 26)
                    Ellipse().fill(WP.accent700).opacity(0.3)
                        .frame(width: 230, height: 200).offset(x: 120, y: 120).blur(radius: 26)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                        .padding(.horizontal, 18)
                }
            }
            .foregroundStyle(WP.onInk)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: Color(hex: 0x181008, opacity: 0.3), radius: 15, y: 12)
            .zoomSource("trip:" + trip.id, in: zoom, clip: .card(20))
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
    /// The trip this map is of — the key its picture is filed under.
    var id: String
    /// Where the route starts, stops and ends.
    var points: [(lat: Double, lon: Double)]
    /// The trip as stretches, each knowing how it is travelled.
    ///
    /// `TripRouting.Leg` has carried OSRM's own geometry all along and this plate drew a
    /// straight line between origin and park regardless — so a trip over the Sierra read
    /// as a ruler laid across the mountains, through country with no road in it. That was
    /// fixed by drawing the road; this is the other half of the same fault. A leg the app
    /// decided to *fly* was still drawn as one unbroken road from the origin city to the
    /// park, and the two drives that flight actually involves — one of which is routinely
    /// the longest single stretch of the day — were nowhere.
    ///
    /// Empty until the router answers, at which point the straight placeholder below is
    /// replaced, and it is dashed until then to say so.
    var legs: [RouteLeg] = []
    /// The airports a flown trip passes through. Drawn as diamonds, and counted in the
    /// framing — an arc whose far end is off the plate reads as a line to nowhere.
    var airports: [(lat: Double, lon: Double)] = []

    /// The straight line between the places, for while the road is still being asked for.
    private var straightCoordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// What the plate draws. The stretches once they exist; until then the straight line
    /// between the places, dashed, exactly as before.
    private var drawn: [RouteLeg] {
        legs.isEmpty ? [RouteLeg(.provisional, straightCoordinates)] : legs
    }

    private var airportCoordinates: [CLLocationCoordinate2D] {
        airports.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Everything the picture has to contain: the stops, and the airports a flight uses.
    private var framed: [(lat: Double, lon: Double)] { points + airports }

    /// Where the route starts, stops and ends — drawn as discs on top of the line. Off the
    /// places, not off the geometry, which has thousands of points and no idea which of
    /// them is a park.
    private var stops: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    @State private var plate: UIImage?

    /// What identifies this trip's map: where it stops, and how big the plate is.
    ///
    /// Deliberately not the road. The road is fetched again on every launch and lands a
    /// moment after the card is drawn — a key that included it disagreed with itself twice
    /// per launch, so every trip re-rendered its map from the network every time the app
    /// opened. The stops are what a reader changes when they change a trip, and the road
    /// follows from them.
    private func key(size: CGSize, scale: CGFloat) -> String {
        // Airports are part of what the picture is *of*, so a trip that starts flying gets
        // a new key and a new picture rather than the old one at the old zoom.
        let places = framed.map { String(format: "%.4f,%.4f", $0.lat, $0.lon) }
        return (["\(Int(size.width))x\(Int(size.height))@\(Int(scale))"] + places)
            .joined(separator: "|")
    }

    var body: some View {
        // A drawn picture rather than a live map. The route is composited into it, so the
        // basemap can be greyed without greying the line — the same trick the `MapReader`
        // overlay used to do, moved to where the drawing now happens.
        GeometryReader { geo in
            let size = geo.size
            let scale = UIScreen.main.scale

            ZStack {
                // Never blank. A trip whose map has not been drawn yet, on a phone with no
                // signal to draw it, shows the plate rather than a hole in the card.
                WP.surface.opacity(0.5)

                if let plate {
                    Image(uiImage: plate)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: plate != nil)
            // Re-runs when the road lands, so a card that came up with the dashed straight
            // line replaces it with the drive as soon as the router answers.
            .task(id: key(size: size, scale: scale) + "|" + drawn.map(\.mode.tag).joined(separator: ",")) {
                // Let the layout settle before drawing anything. `GeometryReader` reports
                // the card's width twice — an intermediate 126pt and then the real 332pt —
                // and the plate's size is part of what a snapshot is filed under, so both
                // passes rendered and each overwrote the other's file. Every launch went
                // back to the network for maps it already had. `.task(id:)` cancels the
                // previous run when the id changes, so a transient size never gets past
                // this line.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }

                // Nothing to draw from until the trip has both ends of a drive. The
                // origin resolves after the first layout pass, so asking before that is
                // asking about a route that does not exist yet.
                guard framed.count > 1 else { return }
                plate = await RouteSnapshotStore.shared.snapshot(
                    id: id,
                    key: key(size: size, scale: scale),
                    region: region,
                    size: size,
                    scale: scale,
                    route: drawn,
                    stops: stops,
                    airports: airportCoordinates,
                    style: .init(line: UIColor(WP.accent),
                                 start: UIColor(WP.accent700),
                                 stopFill: UIColor(WP.bg),
                                 stopStroke: UIColor(WP.accent700),
                                 air: UIColor(WP.accent800))
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(WP.divider, lineWidth: 1))
        .allowsHitTesting(false)
    }

    /// Framed on every stop with a margin, so the whole route reads at a glance.
    private var region: MKCoordinateRegion {
        let lats = framed.map(\.lat), lons = framed.map(\.lon)
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
    /// The places on the route — where it starts, where it stops, where it ends.
    var stops: [CLLocationCoordinate2D]
    /// Whether `coordinates` is the road or the straight line standing in for it. A real
    /// route is drawn solid; a placeholder stays dashed, which is the difference between
    /// "this is the drive" and "this is roughly where you are going".
    var routed: Bool
    var proxy: MapProxy
    /// Not read: it exists so that the projection becoming available re-runs this body.
    /// The conversion below is only meaningful once the map has laid out.
    var projection: Int

    var body: some View {
        GeometryReader { _ in
            let points = coordinates.compactMap { proxy.convert($0, to: .local) }
            let stopPoints = stops.compactMap { proxy.convert($0, to: .local) }
            if points.count == coordinates.count, points.count > 1 {
                Path { path in
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(WP.accent, style: StrokeStyle(lineWidth: routed ? 2.4 : 2,
                                                      lineCap: .round,
                                                      lineJoin: .round,
                                                      dash: routed ? [] : [5, 4]))

                ForEach(Array(stopPoints.enumerated()), id: \.offset) { index, point in
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

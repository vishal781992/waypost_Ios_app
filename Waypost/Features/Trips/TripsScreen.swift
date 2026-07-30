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
                        Text("Trips").font(WP.heading(31))
                    }
                    Spacer(minLength: 0)
                    newTripButton
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("On the books".uppercased())
                        .font(WP.body(9.5)).tracking(1.5).opacity(0.5)
                        .padding(.bottom, 10)

                    VStack(spacing: 14) {
                        ForEach(app.trips) { trip in
                            TripCard(trip: trip)
                        }
                    }

                    Text("Behind you".uppercased())
                        .font(WP.body(9.5)).tracking(1.5).opacity(0.5)
                        .padding(.top, 26)
                        .padding(.bottom, 4)

                    ForEach(SavedTrip.past, id: \.title) { past in
                        Button {
                            app.show("Past trips are read-only in this pass")
                        } label: {
                            DividedRow(vertical: 13) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(past.title).font(WP.heading(18))
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
    var trip: SavedTrip

    private var points: [(lat: Double, lon: Double)] {
        let origin = app.library.city(trip.origin)
        let parks = trip.codes.compactMap { app.library.park($0) }
        return ([origin.map { (lat: $0.lat, lon: $0.lon) }].compactMap { $0 })
            + parks.map { (lat: $0.lat, lon: $0.lon) }
    }

    var body: some View {
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
                }

                Text(trip.title).font(WP.heading(23)).padding(.top, 9)
                    .multilineTextAlignment(.leading)
                Text(trip.route).font(WP.bodyItalic(12.5)).opacity(0.65).padding(.top, 4)
                    .multilineTextAlignment(.leading)

                RouteSpark(points: points)
                    .frame(height: 52)
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
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }
}

/// The little route sketch on a trip card: a dashed line through the stops, the origin a
/// filled dot and each park a hollow one.
struct RouteSpark: View {
    var points: [(lat: Double, lon: Double)]

    var body: some View {
        GeometryReader { geo in
            let placed = place(in: geo.size)
            ZStack {
                Path { path in
                    guard let first = placed.first else { return }
                    path.move(to: first)
                    placed.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(WP.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))

                ForEach(Array(placed.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == 0 ? WP.accent700 : WP.bg)
                        .overlay(Circle().stroke(WP.accent700, lineWidth: 1.5))
                        .frame(width: index == 0 ? 5.2 : 7.2, height: index == 0 ? 5.2 : 7.2)
                        .position(point)
                }
            }
        }
    }

    private func place(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let lons = points.map(\.lon), lats = points.map(\.lat)
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 1
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 1
        return points.map { point in
            let x = 6 + ((point.lon - minLon) / max(0.001, maxLon - minLon)) * (size.width - 12)
            let y = size.height - 8 - ((point.lat - minLat) / max(0.001, maxLat - minLat)) * (size.height - 16)
            return CGPoint(x: x, y: y)
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

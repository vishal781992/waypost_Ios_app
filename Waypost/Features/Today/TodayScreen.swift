import SwiftUI

// The home screen itself is `HomeCarouselView`. What is left in this file is everything
// that screen still shows: the rail of parks near you, the stamps within reach, and a
// driving day when there is one.

// MARK: - Near here

/// What else is within reach of where you are standing. Measured from the park's own
/// coordinates rather than chosen — and the heading says how far the rail reaches, so
/// "nearby" is a number and not a claim.
struct NearbyRail: View {
    @Environment(AppState.self) private var app
    /// The park the rail is measured around — the one currently showing in the carousel.
    /// Nil before the rotation has drawn its first park.
    var park: CuratedPark?

    /// Measured from where the phone is when it will say, and from the park on screen
    /// when it will not — because "near" has to be near something, and the honest
    /// fallback is the park you are looking at.
    private var origin: (lat: Double, lon: Double)? {
        app.recommender.fix ?? park.map { ($0.lat, $0.lon) }
    }

    private var neighbours: [(park: CuratedPark, miles: Int)] {
        guard let origin else { return [] }
        let all = app.library.orderedParks + NationalParks.allCurated
        // The same park carries different codes in the curated library and the on-device
        // list — "romo" and "np-rocky-mountain" — so the park on screen was appearing
        // again as the first tile under itself. Names are what a reader compares.
        var seen: Set<String> = park.map { [$0.name] } ?? []
        return all
            .filter { $0.code != park?.code && seen.insert($0.name).inserted }
            .map { ($0, Geo.haversine(origin, ($0.lat, $0.lon))) }
            .sorted { $0.1 < $1.1 }
            .prefix(8)
            .map { (park: $0.0, miles: Int(($0.1 / 5).rounded()) * 5) }
    }

    /// Computed from the farthest park actually in the rail, rounded up to the nearest
    /// twenty-five — a radius, not a constant. The old rounding was to five, which put a
    /// number like "within 235 miles" in a line that is meant to read as a rule of thumb.
    /// Takes the rail rather than asking for it again. `neighbours` builds the whole
    /// register, measures every park against where you are and sorts it, and the label and
    /// the rail below it both read it — so the home screen did all of that twice on every
    /// redraw to print one line and eight tiles from the same answer.
    private func radiusLabel(_ rail: [(park: CuratedPark, miles: Int)]) -> String {
        guard let farthest = rail.last?.miles, farthest > 0 else { return "" }
        return "within \(Int((Double(farthest) / 25).rounded(.up)) * 25) miles"
    }

    var body: some View {
        let rail = neighbours
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                app.push(.explore)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: 0xF7F0E5, opacity: 0.75))
                        Text("parks near you")
                            .font(WP.body(13))
                            .foregroundStyle(Color(hex: 0xF7F0E5, opacity: 0.82))
                    }
                    Text(radiusLabel(rail))
                        .font(WP.bodyItalic(12.5))
                        .foregroundStyle(Color(hex: 0xF7F0E5, opacity: 0.45))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("all")
                        .font(WP.body(12.5))
                        .foregroundStyle(Color(hex: 0xC9974A))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .padding(.bottom, 9)

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(rail, id: \.park.code) { neighbour in
                        NearbyTile(park: neighbour.park, miles: neighbour.miles)
                    }
                }
                .padding(.horizontal, WP.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .padding(.horizontal, -WP.gutter)
        }
    }
}

struct NearbyTile: View {
    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    var park: CuratedPark
    var miles: Int

    private static let width: CGFloat = 126
    private static let plateHeight: CGFloat = 74
    private static let radius: CGFloat = 16

    var body: some View {
        VStack(spacing: 6) {
            Button {
                app.openPark(park.code)
            } label: {
                ZStack {
                    // Blurred, as the design has it: the photograph is texture behind the
                    // name, not something you are meant to read.
                    ParkImage(park: park, blur: 5, saturation: 1.15,
                              showsScrim: false, topLight: false)

                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x100A06, opacity: 0.42), location: 0),
                            .init(color: Color(hex: 0x100A06, opacity: 0), location: 0.68),
                        ],
                        startPoint: .bottom, endPoint: .top
                    )

                    Text(park.name)
                        .font(WP.display(15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: Color(hex: 0x0A0603, opacity: 0.55), radius: 4, y: 1)
                        .padding(.horizontal, 8)
                }
                .frame(width: Self.width, height: Self.plateHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                // The sheen along the top edge, inset either side so it fades before it
                // reaches the corner rather than lighting the arc itself.
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.clear, .white.opacity(0.80), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                        .padding(.horizontal, Self.width * 0.08)
                }
                .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .stroke(.white.opacity(0.50), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x060301, opacity: 0.30), radius: 8, y: 6)
                .zoomSource("park:" + park.code, in: zoom, clip: .card(Self.radius))
            }
            .buttonStyle(PressStyle(scale: 0.97))

            Text("\(miles) mi · \(USStates.name(for: park.state) ?? park.state)")
                .font(WP.body(10.5))
                .foregroundStyle(Color(hex: 0xF7F0E5, opacity: 0.60))
                .lineLimit(1)
        }
        .frame(width: Self.width)
    }
}

// MARK: - Stamps nearby

/// The passport pages within reach of today — plural now. The design shows the list
/// rather than a single nudge.
struct StampsNearby: View {
    @Environment(AppState.self) private var app

    private var stamps: [CuratedStamp] {
        Array((app.todayPark?.stamps ?? []).prefix(3))
    }

    var body: some View {
        if !stamps.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RuledHeading(title: "Stamps nearby")
                    .padding(.bottom, 2)

                ForEach(stamps) { stamp in
                    Button {
                        app.sheet = .stamp(name: stamp.name, city: stamp.city, dist: stamp.dist)
                    } label: {
                        DividedRow(vertical: 12) {
                            HStack(spacing: 12) {
                                Text("stamp")
                                    .font(WP.headingUI(10))
                                    .foregroundStyle(WP.accent700)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                                            .foregroundStyle(WP.accent400)
                                    )
                                    .pulseRing(active: !app.isStamped(app.stampKey(forName: stamp.name)))

                                VStack(alignment: .leading, spacing: 3) {
                                    Kicker(text: "\(stamp.dist) from here")
                                    Text(stamp.name).font(WP.rowTitle(17))
                                    Text(stamp.city).font(WP.body(12)).opacity(0.6)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WP.accent700)
                            }
                        }
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            }
        }
    }
}

// MARK: - Driving day

/// A driving day keeps the ink plate and its numbers — the one card the redesign left
/// alone, because a leg is not a place.
struct DrivingDayCard: View {
    var leg: CuratedLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                WP.ink
                ButtonGlow(strong: true).opacity(0.5)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.26), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.34),
                        .init(color: .clear, location: 0.54),
                        .init(color: .white.opacity(0.10), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "Driving day", color: .white.opacity(0.95), size: 10)
                        HStack(spacing: 6) {
                            Text(leg.from)
                            Text("→").foregroundStyle(WP.accent400)
                            Text(leg.to)
                        }
                        .font(WP.display(26))
                        .foregroundStyle(.white)

                        HStack(spacing: 18) {
                            legStat("Distance", "\(leg.mi) mi")
                            legStat("Wheel time", leg.drive)
                        }
                        .padding(.top, 12)
                        .overlay(alignment: .top) {
                            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(.onPhoto, radius: 18)

                    Text(leg.road)
                        .font(WP.body(12.5))
                        .foregroundStyle(WP.onInk.opacity(0.85))
                        .padding(.horizontal, 2)
                        .padding(.top, 12)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color(hex: 0x180F08, opacity: 0.2), radius: 17, y: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text("Charge stops on this leg".uppercased())
                    .font(WP.body(12))
                    .tracking(1.5)
                    .foregroundStyle(WP.accent700)
                    .padding(.bottom, 4)
                ForEach(leg.ev, id: \.self) { stop in
                    DividedRow(vertical: 9) {
                        HStack(alignment: .top, spacing: 9) {
                            Text("⚡").foregroundStyle(WP.accent)
                            Text(stop).font(WP.body(13)).lineSpacing(2)
                        }
                    }
                }
                Text(leg.fly.map { "\($0.via) · \($0.time)" } ?? "No flight beats the drive on this leg")
                    .font(WP.bodyItalic(12))
                    .opacity(0.6)
                    .padding(.top, 9)
            }
        }
    }

    private func legStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(WP.body(9))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value).font(WP.statValue(20)).foregroundStyle(.white).tnum()
        }
    }
}

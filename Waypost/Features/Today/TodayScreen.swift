import SwiftUI

/// Today — round 2 of the design. The three "takes" are gone; there is one screen, and
/// it answers one question: where are you, and what is within reach of it.
///
/// The date, the day stepper, the permit card, the next-leg block, the pack card and the
/// journal all came off. What is left is the park you are in at full height, the parks
/// near it, and the stamps you could collect on the way.
struct TodayScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    if let park = app.todayPark {
                        WhereYouAreCard(park: park)
                        NearbyRail(park: park)
                    }
                    if let leg = app.todayLeg {
                        DrivingDayCard(leg: leg)
                    }
                    StampsNearby()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 16)
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The masthead: the app's name at display size, and one glass control that starts a
    /// trip. No plate behind it — the design lets the page colour run to the top.
    private var header: some View {
        HStack(spacing: 10) {
            Text("ParkHop")
                .font(.system(size: 42, weight: .bold))
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Button {
                app.startBuilder()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(WP.accent700)
                    .frame(width: 52, height: 52)
                    .liquidGlass(.pill, radius: 999, interactive: true)
                    .overlay(alignment: .top) {
                        // The lit crown the design puts on its round glass controls.
                        Ellipse()
                            .fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 40, height: 23)
                            .padding(.top, 3)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: Color(hex: 0x181008, opacity: 0.16), radius: 8, y: 5)
            }
            .buttonStyle(PressStyle(scale: 0.94))
            .accessibilityLabel("Add a park")
        }
        .frame(minHeight: 52)
        .padding(.horizontal, WP.gutter)
        .padding(.top, WP.headerTop)
        .padding(.bottom, 11)
    }
}

// MARK: - Where you are

/// The park you are in, at 456pt — nearly half the screen. The design gives it the room
/// because it is the answer to the only question this screen asks.
struct WhereYouAreCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    var park: CuratedPark

    var body: some View {
        Button {
            app.openPark(park.code)
        } label: {
            ZStack(alignment: .bottomLeading) {
                ParkImage(park: park)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Where you are".uppercased())
                        .font(.system(size: 9.5))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(park.name)
                        .font(WP.display(34))
                        .foregroundStyle(.white)
                        .shadow(color: Color(hex: 0x181008, opacity: 0.28), radius: 10, y: 1)
                    Text("Day \(app.today.n ?? 1) of \(app.today.of ?? 1) in park · \(park.gw)")
                        .font(WP.bodyItalic(12))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(.onPhoto, radius: 18)
                .padding(10)

                // Why this park and not another: it is the one today's trip puts you in.
                Text("Recommended".uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.35)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5.5)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.5))
                    .shadow(color: Color(hex: 0x181008, opacity: 0.2), radius: 6, y: 4)
                    .padding(.leading, 15)
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 456)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.42), lineWidth: 0.5))
            .shadow(color: Color(hex: 0x1E1208, opacity: 0.2), radius: 17, y: 14)
            .zoomSource("park:" + park.code, in: zoom)
        }
        .buttonStyle(PressStyle(scale: 0.995))
    }
}

// MARK: - Near here

/// What else is within reach of where you are standing. Measured from the park's own
/// coordinates rather than chosen — and the heading says how far the rail reaches, so
/// "nearby" is a number and not a claim.
struct NearbyRail: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark

    private var neighbours: [(park: CuratedPark, miles: Int)] {
        app.library.orderedParks
            .filter { $0.code != park.code }
            .map { ($0, Geo.haversine((park.lat, park.lon), ($0.lat, $0.lon))) }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map { (park: $0.0, miles: Int(($0.1 / 5).rounded()) * 5) }
    }

    private var radiusLabel: String {
        guard let farthest = neighbours.last?.miles else { return "" }
        return "within \(farthest) miles"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.go(.discover)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text("Near \(park.gw)")
                            .font(WP.body(13.5))
                    }
                    Text(radiusLabel)
                        .font(WP.bodyItalic(13))
                        .opacity(0.5)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        Text("all").font(WP.body(12.5))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(WP.accent700)
                }
                .foregroundStyle(WP.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .padding(.bottom, 11)

            ScrollView(.horizontal) {
                HStack(spacing: 11) {
                    ForEach(neighbours, id: \.park.code) { neighbour in
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

    var body: some View {
        VStack(spacing: 8) {
            Button {
                app.openPark(park.code)
            } label: {
                ZStack {
                    // Blurred, as the design has it: the photograph is texture behind the
                    // name, not something you are meant to read.
                    ParkImage(park: park, blur: 6, saturation: 1.15, topLight: false)
                    // The design's specular sweep, so the tile reads as glass over colour.
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.44), location: 0),
                            .init(color: .white.opacity(0.13), location: 0.30),
                            .init(color: .white.opacity(0.02), location: 0.52),
                            .init(color: .white.opacity(0.26), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Text(park.name)
                        .font(WP.display(19))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: Color(hex: 0x181008, opacity: 0.5), radius: 9)
                        .padding(.horizontal, 12)
                }
                .frame(width: 200, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.6), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x1E1208, opacity: 0.2), radius: 10, y: 7)
                .zoomSource("park:" + park.code, in: zoom)
            }
            .buttonStyle(PressStyle(scale: 0.98))

            Text("\(miles) mi · \(park.region.lowercased())")
                .font(WP.body(11.5))
                .opacity(0.62)
        }
        .frame(width: 200)
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
                        .foregroundStyle(WP.bg.opacity(0.85))
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

import MapKit
import SwiftUI

// MARK: - What the atlas is of

/// One national park on the atlas, and whether it has been stood in.
struct AtlasPark: Identifiable, Hashable {
    var park: CuratedPark
    var visited: Bool
    /// When it was stood in, where that is known. A park added by hand carries no date and
    /// says so by saying nothing — the rail's rule, kept.
    var when: String?

    var id: String { park.code }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: park.lat, longitude: park.lon)
    }
}

/// One state's share of the register: how many parks it holds, and how many are collected.
///
/// Only the states that hold a park exist here. Twenty states hold none, and they are
/// outside the count rather than permanently failing it — a denominator of thirty is the
/// true one, and *four of fifty* would be a figure about geography rather than about
/// anywhere anybody could go.
struct AtlasState: Identifiable, Hashable {
    var code: String
    var held: Int
    var collected: Int

    var id: String { code }
    var name: String { USState.spellOut(code) }
    var isFilled: Bool { held > 0 && collected == held }
}

@MainActor
enum Atlas {
    /// Every national park in the register, marked against where the traveller has been.
    ///
    /// The visited set is the rail's, not `visitedCodes` — that one folds in parks merely
    /// *saved for later*, which on a map of where you have been would be a claim nobody
    /// made. A park counts here when a past trip carried it, a stamp was collected, or it
    /// was added by hand.
    static func parks(_ rail: [AppState.Visit]) -> [AtlasPark] {
        var stood: [String: AppState.Visit] = [:]
        for visit in rail { stood[visit.id] = visit }
        return NationalParks.all.map { park in
            let visit = stood[park.code]
            return AtlasPark(park: CuratedPark(bundled: park),
                             visited: visit != nil,
                             when: visit?.when)
        }
    }

    /// The register by state, most complete first, then most parks, then alphabetically —
    /// so the order is stable and a state never swaps places with another on a redraw.
    static func states(_ parks: [AtlasPark]) -> [AtlasState] {
        var held: [String: Int] = [:]
        var collected: [String: Int] = [:]
        for entry in parks {
            held[entry.park.state, default: 0] += 1
            if entry.visited { collected[entry.park.state, default: 0] += 1 }
        }
        return held
            .map { AtlasState(code: $0.key, held: $0.value, collected: collected[$0.key] ?? 0) }
            .sorted {
                if $0.isFilled != $1.isFilled { return $0.isFilled }
                if $0.collected != $1.collected { return $0.collected > $1.collected }
                if $0.held != $1.held { return $0.held > $1.held }
                return $0.code < $1.code
            }
    }
}

/// Which parks the atlas is drawing.
///
/// Only what is *drawn* changes — never where anything is. A filter that moved the map
/// would make the four choices four different pictures rather than four readings of one.
enum AtlasFilter: Hashable, CaseIterable {
    case all, visited, notYet, filled

    var label: String {
        switch self {
        case .all: return "All"
        case .visited: return "Visited"
        case .notYet: return "Not yet"
        case .filled: return "Filled"
        }
    }

    /// What the chip means, for VoiceOver, where "Not yet" on its own says nothing.
    var spoken: String {
        switch self {
        case .all: return "Every national park"
        case .visited: return "Only the parks you have visited"
        case .notYet: return "Only the parks you have not visited"
        case .filled: return "Only the states where you have collected every park"
        }
    }

    func matches(_ entry: AtlasPark, filled: Set<String>) -> Bool {
        switch self {
        case .all: return true
        case .visited: return entry.visited
        case .notYet: return !entry.visited
        case .filled: return filled.contains(entry.park.state)
        }
    }
}

// MARK: - The card on the profile

/// The atlas at thumbnail size: a picture of the collection, and a door to the screen where
/// it can actually be read.
///
/// One tap target and no gestures of its own. It is a drawn picture rather than a live map
/// for the reason the trip plates are — a map in a card re-streams its basemap on every
/// appearance and comes up blank with no signal — and it shows the lower forty-eight only,
/// because at this height there is no room for the Alaska and Hawai‘i insets a full atlas
/// needs. The count beside it carries all sixty-two whatever the picture shows.
struct AtlasCard: View {
    @Environment(AppState.self) private var app

    /// Taller than the trip card's 132-point plate, and for a reason rather than for
    /// looks: the lower forty-eight is about 1.86 times as wide as it is tall once the
    /// longitude is narrowed for latitude, and a snapshotter fits a region into whatever
    /// frame it is handed by widening the short side. At the trip plate's proportions the
    /// country would sit small between two stripes of ocean. At the gutter, this is close
    /// enough to the shape of the thing being drawn that almost none of the card is sea.
    ///
    /// Fixed, so the profile does not move when the picture lands — the discipline
    /// `ParkImage` keeps by drawing its colour field first.
    private static let plateHeight: CGFloat = 180

    @State private var plate: UIImage?

    private var visited: Set<String> { Set(app.visitRail.map(\.id)) }
    private var parks: [AtlasPark] { Atlas.parks(app.visitRail) }
    private var filledStates: Int { Atlas.states(parks).filter(\.isFilled).count }
    private var openStates: Int { Atlas.states(parks).count }

    var body: some View {
        Button {
            app.push(.atlas)
            Haptics.tap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                plateView
                    .frame(height: Self.plateHeight)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0,
                                                      bottomTrailingRadius: 0, topTrailingRadius: 14,
                                                      style: .continuous))
                summary
            }
            .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(visited.count) of \(NationalParks.all.count) national parks visited. Open the atlas.")
    }

    private var plateView: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = UIScreen.main.scale

            ZStack {
                // Never a hole. A card whose picture has not been drawn yet, on a phone
                // with no signal to draw it, shows the plate.
                WP.surface.opacity(0.5)

                if let plate {
                    Image(uiImage: plate)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: plate != nil)
            .task(id: "\(Int(size.width))x\(Int(size.height))|\(visited.sorted().joined(separator: ","))") {
                // The same settle the trip plates take. `GeometryReader` reports a card's
                // width twice — an intermediate one and then the real one — and the size is
                // part of what the picture is filed under, so both passes would render and
                // each overwrite the other's file.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                plate = await AtlasSnapshot.shared.card(visited: visited, size: size, scale: scale)
            }
        }
    }

    /// Parks first, states second — and thirty as the denominator, never fifty. Twenty
    /// states hold no national park at all, and counting them would make this a figure
    /// about geography rather than about anywhere anybody could go.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(visited.count)").font(WP.statValue(20)).tnum()
            Text("of \(NationalParks.all.count) parks").font(WP.body(12.5)).opacity(0.62)

            Text("·").font(WP.body(12.5)).opacity(0.36)

            Text("\(filledStates)").font(WP.statValue(20)).tnum()
            Text("of \(openStates) states").font(WP.body(12.5)).opacity(0.62)

            Spacer(minLength: 0)

            Text("Open the atlas").font(WP.headingUI(12.5)).foregroundStyle(WP.accent700)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WP.accent700)
        }
        // One line, whatever the phone. The counts are three characters at most and the
        // labels shrink before anything truncates — a row that wrapped would make the
        // card two different heights on two different devices.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - The screen

/// The atlas, on a whole display.
///
/// A map wants room, and on the profile it never gets any. Here it is the entire screen:
/// every national park in the country as a pin, the ones that have been stood in lit and
/// the rest present but quiet, and — close enough in — each one opening into a tile with
/// its photograph and its name. It is a real map, so Alaska and Hawai‘i are a pan away
/// rather than an inset, which is the one thing the card below cannot do.
struct AtlasScreen: View {
    @Environment(AppState.self) private var app

    /// Below this span a pin has room to become a tile. About three degrees of latitude —
    /// a little under the height of Colorado, which is close enough that a tile has
    /// somewhere to sit.
    private static let tileSpan: CLLocationDegrees = 3.0
    /// At most three tiles at once, nearest the middle of the frame. Utah holds five parks
    /// within two hundred miles of each other and five photographs in one frame is a wall
    /// rather than a map. The rest stay pins until you go closer.
    private static let tileCap = 3

    @State private var camera: MapCameraPosition = .region(AtlasSnapshot.region)
    @State private var filter: AtlasFilter = .all
    @State private var visible: MKCoordinateRegion?

    private var visited: Set<String> { Set(app.visitRail.map(\.id)) }
    private var parks: [AtlasPark] { Atlas.parks(app.visitRail) }
    private var states: [AtlasState] { Atlas.states(parks) }
    private var filled: Set<String> { Set(states.filter(\.isFilled).map(\.code)) }
    private var shown: [AtlasPark] { parks.filter { filter.matches($0, filled: filled) } }

    var body: some View {
        // Only the map ignores the safe area. The back control sits in a `ZStack` that
        // does not, which is the arrangement `FloatingBack` documents and the design lint
        // checks — one control, one placement, owned by the control.
        ZStack(alignment: .topLeading) {
            map.ignoresSafeArea()
            FloatingBack(label: "Profile") { app.pop() }
        }
        .overlay(alignment: .bottom) { cuff }
        .task { StateShapes.shared.load() }
    }

    // MARK: The map

    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            // A state fills when its last park is collected. Drawn under the pins, so the
            // achievement is the ground rather than something on top of it.
            ForEach(filledRings) { ring in
                MapPolygon(coordinates: ring.coordinates)
                    .foregroundStyle(WP.lime.opacity(0.40))
                    .stroke(WP.accent800.opacity(0.5), lineWidth: 1)
            }

            ForEach(shown) { entry in
                Annotation(coordinate: entry.coordinate) {
                    if tiled.contains(entry.id) {
                        ParkTile(entry: entry) { app.openPark(entry.park.code) }
                    } else {
                        ParkPin(visited: entry.visited)
                            .onTapGesture { zoom(to: entry) }
                    }
                } label: {
                    Text(entry.park.name)
                }
            }
        }
        // The map's own surface, quietened: this screen's colours are the app's, and a
        // basemap arguing with them makes the lit pins harder to find rather than easier.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        // `.onEnd`, not `.continuous`. The frame is read to decide which pins have room to
        // become tiles, and reading it every frame of a pinch would rebuild sixty-two
        // annotations sixty times a second to answer a question that only matters once the
        // hand has stopped.
        .onMapCameraChange(frequency: .onEnd) { context in
            visible = context.region
        }
    }

    /// The states with every park collected, as rings to fill.
    ///
    /// Empty when no boundary file is bundled, and the map simply draws no fills. An
    /// absent outline is a shape this app has not been given — not a state nobody has
    /// finished — so nothing is claimed either way.
    private var filledRings: [AtlasRing] {
        guard StateShapes.shared.isAvailable else { return [] }
        var out: [AtlasRing] = []
        for state in states where state.isFilled {
            for (index, ring) in StateShapes.shared.polygons(for: state.code).enumerated() {
                out.append(AtlasRing(id: "\(state.code)-\(index)", coordinates: ring))
            }
        }
        return out
    }

    /// Which pins have earned a tile: only when the frame is close enough for one to fit,
    /// only those actually on screen, and never more than three.
    private var tiled: Set<String> {
        guard let visible, visible.span.latitudeDelta < Self.tileSpan else { return [] }
        let inFrame = shown.filter { Self.region(visible, contains: $0.coordinate) }
        guard inFrame.count > Self.tileCap else { return Set(inFrame.map(\.id)) }
        let centre = visible.center
        return Set(inFrame
            .sorted { Self.spread($0.coordinate, centre) < Self.spread($1.coordinate, centre) }
            .prefix(Self.tileCap)
            .map(\.id))
    }

    /// Frames a park close enough for its tile to open. Tapping a pin is the only way in
    /// on a phone — pinching to a three-degree frame with one thumb is a lot to ask.
    private func zoom(to entry: AtlasPark) {
        withAnimation(.easeInOut(duration: 0.55)) {
            camera = .region(MKCoordinateRegion(
                center: entry.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.6, longitudeDelta: 1.6)
            ))
        }
        Haptics.tap()
    }

    // MARK: The cuff

    private var cuff: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(visited.count)").font(WP.statValue(20)).tnum()
                Text("of \(NationalParks.all.count) parks").font(WP.body(12.5)).opacity(0.62)
                Text("·").font(WP.body(12.5)).opacity(0.36)
                Text("\(filled.count)").font(WP.statValue(20)).tnum()
                // Thirty, not fifty. Twenty states hold no national park at all, and a
                // denominator that counted them would be a figure about geography rather
                // than about anywhere anybody could go.
                Text("of \(states.count) states filled").font(WP.body(12.5)).opacity(0.62)
                Spacer(minLength: 0)
            }

            // Labelled explicitly. An array of bare tuples does not convert to an array
            // of labelled ones the way a literal does, and the control's options are
            // labelled.
            SegmentedTrough(
                options: AtlasFilter.allCases.map { (value: $0, label: $0.label) },
                selection: $filter
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WP.onInk)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(WP.divider, lineWidth: 1))
                .shadow(color: Color(hex: 0x181008, opacity: 0.18), radius: 14, y: 6)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.bottom, WP.tabBarHeight + 12)
        .accessibilityElement(children: .contain)
    }

    // MARK: Geometry

    private static func region(_ frame: MKCoordinateRegion,
                               contains point: CLLocationCoordinate2D) -> Bool {
        abs(point.latitude - frame.center.latitude) <= frame.span.latitudeDelta / 2 &&
        abs(point.longitude - frame.center.longitude) <= frame.span.longitudeDelta / 2
    }

    /// How far apart two coordinates are, near enough. Squared, unrooted and with the
    /// longitude narrowed for latitude — this only ever sorts, and a sort does not care
    /// about the units it is sorting in.
    private static func spread(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat = a.latitude - b.latitude
        let lon = (a.longitude - b.longitude) * cos(b.latitude * .pi / 180)
        return lat * lat + lon * lon
    }
}

/// One ring of one filled state. `MapPolygon` takes a ring at a time, and a state with
/// islands is several.
private struct AtlasRing: Identifiable {
    var id: String
    var coordinates: [CLLocationCoordinate2D]
}

// MARK: - What sits on the map

/// A park, as a mark. Lit for one that has been stood in, hollow for one that has not —
/// the same diameter either way, so the whole register reads as one field rather than as a
/// bright list with faint decoration around it.
private struct ParkPin: View {
    var visited: Bool

    var body: some View {
        Circle()
            .fill(visited ? WP.lime : WP.onInk.opacity(0.8))
            .frame(width: visited ? 14 : 11, height: visited ? 14 : 11)
            .overlay {
                Circle().stroke(visited ? WP.accent800 : WP.text.opacity(0.45),
                                lineWidth: visited ? 1.6 : 1.3)
            }
            .shadow(color: Color(hex: 0x181008, opacity: visited ? 0.28 : 0.12), radius: 3, y: 1)
            // A fourteen-point dot is a nine-point tap target once a thumb is involved.
            // The mark keeps its size; the frame around it is what answers the tap.
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .accessibilityHidden(true)
    }
}

/// A park at close range: its photograph, its name and its state.
///
/// One fixed size for both states. A tile that grew when a photograph arrived would drag
/// the map under it, which is the reason `ParkImage` draws the park's colour field first
/// and lays the photograph over the top.
private struct ParkTile: View {
    var entry: AtlasPark
    var open: () -> Void

    private static let width: CGFloat = 132

    /// The state either way, and then either when it was stood in or that it has not been.
    /// A visited park with no date — one added by hand — says only where it is, which is
    /// the rail's rule: nothing here is guessed to fill the line.
    private static func caption(for entry: AtlasPark) -> String {
        if !entry.visited { return "\(entry.park.stateName) · not visited yet" }
        guard let when = entry.when else { return entry.park.stateName }
        return "\(entry.park.stateName) · \(when)"
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ParkImage(park: entry.park, blur: 3,
                          saturation: entry.visited ? 1.1 : 0.3,
                          showsScrim: false, topLight: false)
                    .frame(width: Self.width, height: 64)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.park.name)
                        .font(WP.display(16))
                        .lineLimit(1).minimumScaleFactor(0.72)
                    // The state either way. Where it has not been stood in, the tile says
                    // so in as many words rather than leaving the reader to notice that it
                    // is paler than its neighbour.
                    Text(Self.caption(for: entry).uppercased())
                        .font(WP.body(9.5)).tracking(0.9)
                        .foregroundStyle(entry.visited ? WP.accent700 : WP.text.opacity(0.5))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 9)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(width: Self.width, alignment: .leading)
            }
            .background(WP.onInk)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(entry.visited ? WP.accent300 : WP.divider, lineWidth: 1)
            }
            .opacity(entry.visited ? 1 : 0.66)
            .shadow(color: Color(hex: 0x181008, opacity: 0.24), radius: 7, y: 3)
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.park.full), \(entry.park.stateName). "
                            + (entry.visited
                               ? (entry.when.map { "Visited \($0)." } ?? "Visited.")
                               : "Not visited yet."))
    }
}

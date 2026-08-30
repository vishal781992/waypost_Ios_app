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
        // `allCurated` rather than sixty-two fresh `CuratedPark`s: this is read from the
        // card's body and from four computed properties on the atlas screen, so building
        // the register here meant building it several times per redraw.
        return NationalParks.allCurated.map { park in
            let visit = stood[park.code]
            return AtlasPark(park: park, visited: visit != nil, when: visit?.when)
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

    /// The lower forty-eight, framed once: where the atlas opens.
    ///
    /// Alaska, Hawai‘i and the territories are outside it deliberately — this is a real
    /// map and pans to them, and opening wide enough to hold them would put the whole of
    /// the country's middle in a strip. It lived on the snapshotter while there was one
    /// and has come home to the only thing that ever used it.
    private static var opening: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.6, longitude: -98.4),
            span: MKCoordinateSpan(latitudeDelta: 25.5, longitudeDelta: 61)
        )
    }

    @State private var camera: MapCameraPosition = .region(AtlasScreen.opening)
    @State private var filter: AtlasFilter = .all
    @State private var visible: MKCoordinateRegion?

    /// Whether a live map has been built in this process yet.
    ///
    /// The first one is expensive in a way the rest are not: MapKit brings up its tile
    /// engine, opens its connection to the location daemon and loads a basemap, and all of
    /// that lands on the main thread the moment the view is built. Everywhere else in the
    /// app a map is a drawn picture — the trip plates and the profile's own ground are
    /// snapshots — so the atlas is the first live map the process ever makes, and it was
    /// making it in the middle of the push animation. That is the stall.
    ///
    /// Static, because the cost belongs to the process rather than to the screen: the
    /// second visit pays nothing and must not wait.
    private static var mapKitIsWarm = false

    /// Long enough for the push to finish. `NavigationStack` slides in on the system's own
    /// curve, which is a little over three tenths of a second.
    private static let settle: Duration = .milliseconds(360)

    @State private var showsMap = AtlasScreen.mapKitIsWarm

    /// The register, its states and the filter applied — worked out once per redraw.
    ///
    /// These were five computed properties reading each other: `shown` asked for `parks`
    /// and for `filled`, `filled` asked for `states`, and `states` asked for `parks` again.
    /// A single pass of `body` marked sixty-two parks against the rail four times over and
    /// grouped them by state twice, and every annotation on the map read `shown` again on
    /// top of that.
    private struct Reading {
        var visited: Set<String>
        var states: [AtlasState]
        var filled: Set<String>
        var shown: [AtlasPark]
    }

    private func read() -> Reading {
        let rail = app.visitRail
        let parks = Atlas.parks(rail)
        let states = Atlas.states(parks)
        let filled = Set(states.filter(\.isFilled).map(\.code))
        return Reading(visited: Set(rail.map(\.id)),
                       states: states,
                       filled: filled,
                       shown: parks.filter { filter.matches($0, filled: filled) })
    }

    var body: some View {
        let reading = read()
        // Only the map ignores the safe area. The back control sits in a `ZStack` that
        // does not, which is the arrangement `FloatingBack` documents and the design lint
        // checks — one control, one placement, owned by the control.
        return ZStack(alignment: .topLeading) {
            // The ground the map will cover, and what stands in for it while the screen is
            // still sliding. The same ink the profile's map sits on, so arriving here is a
            // continuation rather than a flash of a different colour.
            WP.ink.ignoresSafeArea()

            if showsMap {
                map(reading).ignoresSafeArea().transition(.opacity)
            }

            FloatingBack(label: "Profile") { app.pop() }
        }
        // At the foot, under the thumb. It sat at the top for one release, next to the
        // back control, which is where the park and trip screens keep their segments —
        // but those screens have a tab bar under them and this one does not, so the whole
        // bottom of the display is free and the counts were as far from a hand as they
        // could be put.
        .overlay(alignment: .bottom) { cuff(reading) }
        .task { StateShapes.shared.load() }
        // The back control and the counts are up immediately; only the map waits, and only
        // the first time. A screen that arrives complete a third of a second late is a
        // screen that arrived; one that judders on its way in is a screen that broke.
        .task { await liven() }
    }

    /// Builds the live map once the screen has finished arriving.
    ///
    /// Returns on its first line on every visit after the first, so the wait is paid once
    /// per launch and never again.
    private func liven() async {
        guard !showsMap else { return }
        try? await Task.sleep(for: Self.settle)
        Self.mapKitIsWarm = true
        withAnimation(.easeOut(duration: 0.3)) { showsMap = true }
    }

    // MARK: The map

    private func map(_ reading: Reading) -> some View {
        // Worked out before the builder rather than inside it: which pins have earned a
        // tile is one answer for the whole map, and asking per annotation walked the
        // register once for every one of the sixty-two.
        let tiledIDs = tiled(reading.shown)
        return Map(position: $camera, interactionModes: [.pan, .zoom]) {
            // A state fills when its last park is collected. Drawn under the pins, so the
            // achievement is the ground rather than something on top of it.
            ForEach(filledRings(reading.states)) { ring in
                MapPolygon(coordinates: ring.coordinates)
                    .foregroundStyle(WP.lime.opacity(0.40))
                    .stroke(WP.accent800.opacity(0.5), lineWidth: 1)
            }

            ForEach(reading.shown) { entry in
                Annotation(coordinate: entry.coordinate) {
                    if tiledIDs.contains(entry.id) {
                        ParkTile(entry: entry) { app.openPark(entry.park.code) }
                            // Out of the pin it replaces rather than on top of it.
                            .transition(.scale(scale: 0.7, anchor: .bottom)
                                .combined(with: .opacity))
                    } else {
                        ParkPin(visited: entry.visited)
                            .onTapGesture { zoom(to: entry) }
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                } label: {
                    Text(entry.park.name)
                }
            }
        }
        // The map's own surface, quietened: this screen's colours are the app's, and a
        // basemap arguing with them makes the lit pins harder to find rather than easier.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        // Continuous, but filtered. `.onEnd` meant a pinch did nothing at all until the
        // hand came off and then every tile arrived at once, which is what made opening
        // and closing them feel like a jump rather than a zoom. Writing the frame on every
        // gesture tick instead would rebuild sixty-two annotations sixty times a second,
        // so `hasMoved` lets through only the changes that could alter the answer — the
        // tile threshold being crossed, or a pan or zoom big enough to bring different
        // parks into view.
        .onMapCameraChange(frequency: .continuous) { context in
            let next = context.region
            guard Self.hasMoved(from: visible, to: next) else { return }
            withAnimation(.easeInOut(duration: 0.22)) { visible = next }
        }
        // Changing what is drawn is a change of subject, not a jump. The pins that leave
        // and the tiles that arrive cross-fade at the same speed the panels do.
        .animation(Motion.panel, value: filter)
    }

    /// Whether the frame moved enough for the tile answer to be worth working out again.
    ///
    /// Three ways it can: there was no frame before, the span crossed the threshold a tile
    /// needs, or the map moved or zoomed by more than a fifth of what is on screen.
    private static func hasMoved(from old: MKCoordinateRegion?, to new: MKCoordinateRegion) -> Bool {
        guard let old else { return true }
        if (old.span.latitudeDelta < tileSpan) != (new.span.latitudeDelta < tileSpan) { return true }
        if abs(old.span.latitudeDelta - new.span.latitudeDelta) > old.span.latitudeDelta * 0.2 { return true }
        if abs(old.center.latitude - new.center.latitude) > old.span.latitudeDelta * 0.2 { return true }
        if abs(old.center.longitude - new.center.longitude) > old.span.longitudeDelta * 0.2 { return true }
        return false
    }

    /// The states with every park collected, as rings to fill.
    ///
    /// Empty when no boundary file is bundled, and the map simply draws no fills. An
    /// absent outline is a shape this app has not been given — not a state nobody has
    /// finished — so nothing is claimed either way.
    private func filledRings(_ states: [AtlasState]) -> [AtlasRing] {
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
    private func tiled(_ shown: [AtlasPark]) -> Set<String> {
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

    private func cuff(_ reading: Reading) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(reading.visited.count)").font(WP.statValue(20)).tnum()
                Text("of \(NationalParks.all.count) parks").font(WP.body(12.5)).opacity(0.62)
                Text("·").font(WP.body(12.5)).opacity(0.36)
                Text("\(reading.filled.count)").font(WP.statValue(20)).tnum()
                // Thirty, not fifty. Twenty states hold no national park at all, and a
                // denominator that counted them would be a figure about geography rather
                // than about anywhere anybody could go.
                Text("of \(reading.states.count) states filled").font(WP.body(12.5)).opacity(0.62)
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
        // The atlas is a pushed screen, so the tab bar is hidden and this can sit on the
        // safe area's own line rather than clearing a bar that is not there.
        .padding(.bottom, 8)
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
        // Two rings rather than a shadow. A drop shadow is an offscreen pass per view, and
        // there are sixty-two of these on the map at once — the pale outer ring does the
        // same job of lifting the mark off whatever the basemap put underneath it, and
        // costs a stroke.
        Circle()
            .fill(visited ? WP.lime : WP.onInk.opacity(0.9))
            .frame(width: visited ? 13 : 10, height: visited ? 13 : 10)
            .overlay {
                Circle().stroke(visited ? WP.accent800 : WP.text.opacity(0.5),
                                lineWidth: visited ? 1.6 : 1.3)
            }
            .padding(2)
            .overlay {
                Circle().stroke(WP.onInk.opacity(visited ? 0.85 : 0.5), lineWidth: 1.6)
            }
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
                // No blur. The tile is a hundred and thirty two points wide and the
                // photograph is the reason to open it — three points of blur was borrowed
                // from the tiny thumbnails on the near-you card, where the name is set
                // over the picture and has to stay legible. Here the name sits underneath
                // it on its own plate, so the photograph can just be the photograph.
                ParkImage(park: entry.park, blur: 0,
                          saturation: entry.visited ? 1.04 : 0.62,
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
            // Dimmed, not washed out. Two thirds opacity over a desaturated picture left
            // an unvisited park as grey mush; the picture is most of the way to its own
            // colour now and the plate under it does the quietening.
            .opacity(entry.visited ? 1 : 0.82)
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

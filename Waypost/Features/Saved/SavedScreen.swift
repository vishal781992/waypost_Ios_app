import SwiftUI

/// Saved — bookmarked parks, and the passport book.
struct SavedScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                Text(app.stamps.count == 1 ? "1 stamp collected" : "\(app.stamps.count) stamps collected")
                    .kickerStyle()
                    .rollingNumber(app.stamps.count)
                Text("Saved").font(WP.displayBold(44)).tracking(-0.4).padding(.top, 2).padding(.bottom, 11)
                SegmentedTrough(
                    options: [(false, "Parks"), (true, "Passport")],
                    selection: $app.savedShowsPassport
                )
            }

            ScrollView(.vertical) {
                Group {
                    if app.savedShowsPassport {
                        PassportBook()
                    } else {
                        SavedParksList()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 16)
                .padding(.bottom, WP.rootScrollBottom)
                .panelTransition(id: app.savedShowsPassport)
            }
            .tracksTabBarMinimize()
            .scrollIndicators(.hidden)
            .captureScrollPosition()
        }
    }
}

struct SavedParksList: View {
    @Environment(AppState.self) private var app

    /// Whether the two-colour key at the bottom has anything to explain.
    private var mixed: Bool {
        let parks = app.saved.compactMap { app.park($0) }
        return parks.contains { $0.isStatePark } && parks.contains { !$0.isStatePark }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(app.saved, id: \.self) { code in
                if let park = app.park(code) {
                    SavedParkRow(park: park, code: code)
                }
            }
            .animation(Motion.panel, value: app.saved)

            if app.saved.isEmpty {
                Text("Nothing saved yet. Bookmark a park from Explore and it waits here for the next trip.")
                    .font(WP.bodyItalic(14)).opacity(0.6).padding(.top, 24)
            }

            // A saved list held national parks and state parks in identical rows, and
            // nothing on the row said which was which. The colour says it now, and this
            // says what the colour means.
            if mixed {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(WP.ink)
                        .frame(width: 22, height: 14)
                    Text("Dark rows are state parks. The pale ones are the park service's.")
                        .font(WP.bodyItalic(11.5)).opacity(0.6).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
            }

            Text("Saved parks appear first when you build a trip.")
                .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3).padding(.top, mixed ? 10 : 20)
        }
    }
}

/// One saved park.
///
/// A state park is drawn the other way up — ink plate, pale type — because the list mixes
/// two catalogues that behave differently: a national park here carries a fee, hours and a
/// stamp, and a state park carries a name, a place and a link to whoever runs it. Telling
/// them apart was impossible when both rows were the same pale glass.
struct SavedParkRow: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark
    var code: String

    private var dark: Bool { park.isStatePark }

    /// The state and what kind of unit this is.
    ///
    /// The fee used to sit here, off the bundled record — which meant a written-down price
    /// for eight parks and "Not published" for the other fifty-five. A saved row is not
    /// worth a network request for a number, and a stale price is worse than no price, so
    /// it names the park rather than costing it. The park's own screen prints the fee the
    /// park service publishes today.
    private var subtitle: String {
        "\(park.stateName) · \(park.designationLabel)"
    }

    /// The remove button: the mark's orange, laid solid, on both kinds of row.
    ///
    /// It used to be two controls — pale glass on the park-service rows, a translucent
    /// white disc on the state-park plate — which put two different-looking buttons doing
    /// the same job one above the other in the same list. Opaque orange is legible on
    /// either ground and does not take its colour from the row behind it.
    private var dismiss: some View {
        Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: 44, height: 44)
            .background(Circle().fill(WP.mark))
            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
            .contentShape(Circle())
    }

    var body: some View {
        HStack(spacing: 13) {
            Button { app.openPark(code) } label: {
                ParkImage(park: park, blur: 7, saturation: 1.15,
                          showsScrim: false, topLight: false)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressStyle(scale: 0.95))

            Button { app.openPark(code) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(park.name).font(WP.rowTitle(17))
                    Text(subtitle)
                        .font(WP.body(12)).opacity(0.62).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))

            Button { app.toggleSaved(code) } label: {
                dismiss
            }
            .buttonStyle(PressStyle(scale: 0.9))
        }
        .foregroundStyle(dark ? WP.onInk : WP.text)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .modifier(SavedPlate(dark: dark))
        .overlay(alignment: .top) {
            // The lit edge both plates carry, dimmed on the dark one — white at nine
            // tenths over ink is a hairline scar rather than a highlight.
            LinearGradient(colors: [.clear, .white.opacity(dark ? 0.22 : 0.9), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
        .shadow(color: Color(hex: 0x181008, opacity: dark ? 0.18 : 0.1), radius: 7, y: 4)
        .padding(.bottom, 11)
        .contextMenu {
            Button {
                app.openPark(code)
            } label: {
                Label("Open \(park.name)", systemImage: "arrow.up.forward.square")
            }
            Button(role: .destructive) {
                app.toggleSaved(code)
            } label: {
                Label("Remove from saved", systemImage: "bookmark.slash")
            }
        }
    }
}

/// The passport: a grid of scalloped stamps, collected by standing in the park.
///
/// The page reads in the order somebody at a trailhead needs it. **What is in reach** —
/// one plate, present only when there is somewhere to stamp. **What is nearby** — the next
/// ones out, so the book is useful before you arrive. **What is collected** — the brass
/// faces, most recent first. Then the trip's own book, which is the one list here with a
/// denominator a progress bar can honestly measure.
///
/// Where the stamps come from is the whole of what changed. They used to come from tapping
/// a tile, which meant a passport could be filled from a sofa. Now they come from standing
/// somewhere: `StampWatch` matches the phone against every national park, state park and
/// park-service unit the app holds a coordinate for, and a page is offered when you are
/// inside that place's own reach. The tiles are what they always looked like — a record —
/// rather than buttons that made one.
struct PassportBook: View {
    @Environment(AppState.self) private var app

    @State private var watch = StampWatch.shared

    /// Everything in the book, most recent first — wherever it was collected. The page used
    /// to split these by provenance, showing the bundled twelve in one grid and everything
    /// else in another, which asked the reader to care where a stamp came from. They care
    /// when they got it.
    ///
    /// One with no date was carried over from a build that kept only codes, so it sorts to
    /// the back rather than to today.
    private var collected: [CollectedStamp] {
        app.stampBook
            .sorted { a, b in
                switch (a.on, b.on) {
                case let (x?, y?): return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.name < b.name
                }
            }
    }

    private var bundledCollected: Int {
        app.library.passport.filter { app.isStamped($0.code) }.count
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 11), count: 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StampNowCard()
                .padding(.bottom, watch.inReach.isEmpty ? 0 : 12)

            StampsItselfRow()

            if !watch.nearby.isEmpty {
                heading("Nearby, not yet in reach")
                Text("Ordered by how far you are from each one's edge, not its middle — a park thirty miles wide is nearer than its pin says.")
                    .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 11)
                VStack(spacing: 8) {
                    ForEach(watch.nearby) { ranked in
                        NearbyStampRow(ranked: ranked)
                    }
                }
                .animation(Motion.panel, value: watch.nearby)
            }

            if !collected.isEmpty {
                heading("Collected")
                LazyVGrid(columns: columns, spacing: 11) {
                    ForEach(collected) { stamp in
                        CollectedTile(stamp: stamp)
                    }
                }
            }

            heading("On this trip")
            Text("The stops along the trip in the book. They fill as you pass them.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 11)
            ProgressTrack(fraction: Double(bundledCollected) / Double(max(1, app.library.passport.count)))
                .animation(Motion.counter, value: bundledCollected)
            Text("\(bundledCollected) of the \(app.library.passport.count) stops in the book.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).padding(.top, 7).padding(.bottom, 12)
            LazyVGrid(columns: columns, spacing: 11) {
                ForEach(app.library.passport) { unit in
                    StampTile(unit: unit)
                }
            }

            if app.unnamedStampCount > 0 {
                Text(app.unnamedStampCount == 1
                     ? "One stamp was collected before this book kept names. It still counts, but its name was never written down, so there is no page for it."
                     : "\(app.unnamedStampCount) stamps were collected before this book kept names. They still count, but their names were never written down, so there are no pages for them.")
                    .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The paper book still wants a rubber stamp at the visitor centre. This one just remembers where you stood.")
                .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3).padding(.top, 18)
        }
    }

    /// A band heading, ruled off — the same one the park screen's Nearby tab uses.
    private func heading(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(WP.body(11)).tracking(1.3)
                .foregroundStyle(WP.accent700)
            Rectangle().fill(WP.divider).frame(height: 1)
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

/// A stamp collected somewhere the app had no page waiting for it.
///
/// It does not toggle. A stamp is a claim about where the phone stood, and nothing in the
/// app takes one back — the same reason the visited rail suppresses rather than deletes.
/// The place sits under the face because, unlike the bundled page, nothing else on this
/// screen says where the unit is.
struct CollectedTile: View {
    var stamp: CollectedStamp

    var body: some View {
        VStack(spacing: 5) {
            StampFace(name: stamp.name, caption: stamp.caption)
                .rotationEffect(.degrees(Double(stamp.code.first?.asciiValue ?? 0)
                    .truncatingRemainder(dividingBy: 5) - 2))
                .aspectRatio(1, contentMode: .fit)

            if !stamp.place.isEmpty {
                Text(stamp.place)
                    .font(WP.bodyItalic(10.5)).opacity(0.6)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stamp.name), \(stamp.caption)")
    }
}

/// One page of the trip's book: cancelled, or waiting to be.
///
/// Not a button any more. It was one, and tapping it collected the stamp — which meant the
/// whole passport could be filled without leaving the house, and made the line under the
/// grid about standing in a park a decoration. A stamp is a claim about where the phone
/// was, so the only things that can make one now are being there and saying yes.
struct StampTile: View {
    @Environment(AppState.self) private var app
    var unit: PassportUnit

    private var collected: Bool { app.isStamped(unit.code) }

    var body: some View {
        Group {
            ZStack {
                if collected {
                    StampFace(name: unit.name, caption: "stamped")
                        .rotationEffect(.degrees(Double(unit.code.first?.asciiValue ?? 0) .truncatingRemainder(dividingBy: 5) - 2))
                        .transition(.scale(scale: 0.35).combined(with: .opacity))
                } else {
                    VStack(spacing: 3) {
                        Text(unit.name)
                            .font(WP.headingUI(12))
                            .multilineTextAlignment(.center)
                            .opacity(0.8)
                        Text("unstamped".uppercased())
                            .font(WP.body(7.5)).tracking(0.9).opacity(0.55)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(WP.neutral400)
                    )
                    .foregroundStyle(WP.neutral600)
                    .pulseRing()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .animation(Motion.stamp, value: collected)
        }
        .sensoryFeedback(.success, trigger: collected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.name), \(collected ? "stamped" : "not yet stamped")")
    }
}

/// One cancelled page: brass gradient inside a scalloped edge, with a ring of rule.
struct StampFace: View {
    var name: String
    var caption: String
    var nameSize: CGFloat = 12
    var captionSize: CGFloat = 6.5

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(oklch: 0.98, 0.02, 80), WP.accent100, Color(oklch: 0.86, 0.08, 70)],
                center: UnitPoint(x: 0.32, y: 0.24),
                startRadius: 0,
                endRadius: 120
            )
            .clipShape(StampShape())

            GeometryReader { geo in
                Circle()
                    .strokeBorder(WP.accent600.opacity(0.65), lineWidth: 1)
                    .padding(geo.size.width * 0.12)
            }

            VStack(spacing: 3) {
                Text(name)
                    .font(WP.headingUI(nameSize))
                    .multilineTextAlignment(.center)
                Text(caption.uppercased())
                    .font(WP.body(captionSize))
                    .tracking(1)
                    .opacity(0.7)
            }
            .foregroundStyle(WP.accent800)
            .padding(nameSize)
        }
        .shadow(color: Color(hex: 0x3C260A, opacity: 0.26), radius: 5, y: 5)
    }
}

/// The plate under a saved row: glass for a national park, ink for a state one.
private struct SavedPlate: ViewModifier {
    var dark: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if dark {
            content.background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WP.ink))
        } else {
            content.liquidGlass(.pill, radius: 18)
        }
    }
}

import SwiftUI

/// Saved — bookmarked parks, and the passport book.
struct SavedScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                Text("\(app.stamps.count) of 63 stamps").kickerStyle()
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
struct PassportBook: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Stand inside a park and the stamp unlocks. Tap it to cancel the page — the phone taps back.")
                .font(WP.body(13)).lineSpacing(3).opacity(0.8)
                .padding(.bottom, 12)

            ProgressTrack(fraction: Double(app.stamps.count) / 63)
                .animation(Motion.counter, value: app.stamps.count)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 3), spacing: 11) {
                ForEach(app.library.passport) { unit in
                    StampTile(unit: unit)
                }
            }
            .padding(.top, 18)

            Text("The paper book still wants a rubber stamp at the visitor centre. This one just remembers where you were.")
                .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3).padding(.top, 18)
        }
    }
}

struct StampTile: View {
    @Environment(AppState.self) private var app
    var unit: PassportUnit

    private var collected: Bool { app.isStamped(unit.code) }

    var body: some View {
        Button {
            app.collectStamp(unit.code, name: unit.name)
        } label: {
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
        .buttonStyle(PressStyle(scale: 0.94))
        .sensoryFeedback(.success, trigger: collected)
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

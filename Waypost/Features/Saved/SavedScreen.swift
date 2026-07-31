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
                Text("Saved").font(WP.display(31)).padding(.top, 4).padding(.bottom, 11)
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
                .padding(.bottom, WP.tabBarClearance)
                .panelTransition(id: app.savedShowsPassport)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct SavedParksList: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(app.saved, id: \.self) { code in
                if let park = app.library.park(code) {
                    VStack(spacing: 0) {
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
                                    Text("\(park.state) · \(park.fee)")
                                        .font(WP.body(12)).opacity(0.62).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(scale: 0.99))

                            Button { app.toggleSaved(code) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(WP.neutral700)
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(WP.divider, lineWidth: 1))
                            }
                            .buttonStyle(PressStyle(scale: 0.9))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .liquidGlass(.pill, radius: 18)
                        .overlay(alignment: .top) {
                            LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(height: 1)
                                .padding(.horizontal, 14)
                        }
                        .shadow(color: Color(hex: 0x181008, opacity: 0.1), radius: 7, y: 4)
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
            }
            .animation(Motion.panel, value: app.saved)

            if app.saved.isEmpty {
                Text("Nothing saved yet. Bookmark a park from Discover and it waits here for the next trip.")
                    .font(WP.bodyItalic(14)).opacity(0.6).padding(.top, 24)
            }

            Text("Saved parks appear first when you build a trip.")
                .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3).padding(.top, 20)
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

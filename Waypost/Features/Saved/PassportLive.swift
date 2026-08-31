import SwiftUI

/// The passport, standing somewhere.
///
/// Three pieces, and the page shows whichever of them has something to say: the plate for
/// what is in reach right now, the rows for what is near but not yet, and the one switch
/// that decides whether the phone may stamp on its own.
///
/// None of them draws an empty state. A passport with nothing near it is a book of stamps,
/// which is what it was before any of this — the live parts appear when there is somewhere
/// to appear about.

// MARK: - What is in reach

/// The plate at the top of the book: where you are, and the one thing to do about it.
///
/// The app's own tile, the one a trip on the shelf is drawn on: an ink plate with a dusk
/// bloom at the top left, a brass one at the bottom right, and a lit top edge. Where you
/// are standing is the same weight of thing as a trip you have planned, and the two should
/// not be two different objects on two different surfaces.
struct StampNowCard: View {
    @Environment(AppState.self) private var app
    @State private var watch = StampWatch.shared

    var body: some View {
        if let place = watch.inReach.first {
            plate(place)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .animation(Motion.panel, value: place.key)
        }
    }

    @ViewBuilder
    private func plate(_ place: Stampable) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                LiveDot()
                Text("You are here".uppercased())
                    .font(WP.body(11)).tracking(1.3)
                    .foregroundStyle(WP.lime)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            HStack(alignment: .center, spacing: 14) {
                if let dwell = watch.dwell, app.stampsItself {
                    DwellRing(dwell: dwell)
                } else {
                    ReadyDisc(name: place.name)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(WP.rowTitle(17))
                        .lineLimit(2)
                    Text(subtitle(place))
                        .font(WP.body(12.5)).opacity(0.72)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10, weight: .semibold))
                        Text(standing(place))
                    }
                    .font(WP.body(12)).opacity(0.6)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            buttons(place)
                .padding(.top, 15)

            Text(footnote)
                .font(WP.bodyItalic(11.5)).opacity(0.55)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .inkPlate(radius: 22)
    }

    @ViewBuilder
    private func buttons(_ place: Stampable) -> some View {
        if watch.dwell != nil, app.stampsItself {
            HStack(spacing: 8) {
                Button { stamp(place) } label: {
                    Text("Stamp it now")
                        .font(WP.headingUI(16))
                        .frame(maxWidth: .infinity).frame(minHeight: 46)
                        .limeControl()
                }
                .buttonStyle(PressStyle())

                Button { watch.decline(place.key); Haptics.tap() } label: {
                    Text("Not now")
                        .font(WP.headingUI(16))
                        .frame(width: 108).frame(minHeight: 46)
                        .foregroundStyle(WP.onInk)
                        .overlay {
                            Capsule().stroke(WP.onInk.opacity(0.28), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        } else {
            Button { stamp(place) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Stamp it").font(WP.headingUI(17))
                }
                .frame(maxWidth: .infinity).frame(minHeight: 48)
                .limeControl()
            }
            .buttonStyle(PressStyle())
        }
    }

    private func stamp(_ place: Stampable) {
        app.collectStamp(app.stampKey(forName: place.name),
                         name: place.name, place: place.place)
    }

    // MARK: What it says

    private func subtitle(_ place: Stampable) -> String {
        place.place.isEmpty ? place.designation : "\(place.designation) · \(place.place)"
    }

    /// Where you are, in the terms the reach is decided in. Never a bare "you are here":
    /// the reason this park counts from six miles out and the next one from three is its
    /// size, and saying so is what stops the number reading as a mistake.
    private func standing(_ place: Stampable) -> String {
        guard let here = watch.here else { return "Inside the reach" }
        let miles = place.miles(from: here.coordinate.latitude, here.coordinate.longitude)
        return String(format: "%.1f mi in · %.0f mi reach", miles, place.reachMiles)
    }

    private var footnote: String {
        if app.stampsItself {
            return "Or leave it. Stay fifteen minutes and it stamps itself."
        }
        return "A stamp cannot be taken back, so this one waits for you."
    }
}

/// The green pulse that says a reading is live, not remembered.
private struct LiveDot: View {
    @State private var wide = false

    var body: some View {
        Circle()
            .fill(WP.live)
            .frame(width: 7, height: 7)
            .overlay {
                Circle().stroke(WP.live.opacity(wide ? 0 : 0.5), lineWidth: 2)
                    .scaleEffect(wide ? 2.6 : 1)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    wide = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// The page waiting to be cancelled: the stamp's own outline, lit.
private struct ReadyDisc: View {
    var name: String

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(WP.accent, lineWidth: 2)
                .background { Circle().fill(WP.accent.opacity(0.14)) }
            VStack(spacing: 3) {
                Text(name)
                    .font(WP.headingUI(11))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text("ready".uppercased())
                    .font(WP.body(6.5)).tracking(0.9)
                    .foregroundStyle(WP.accent300)
            }
            .padding(9)
            .foregroundStyle(WP.onInk)
        }
        .frame(width: 74, height: 74)
        .pulseRing()
        .accessibilityHidden(true)
    }
}

/// The fifteen minutes, running.
///
/// A `TimelineView` rather than a timer of our own: the clock belongs to the visit and is
/// stored against it, so this only has to redraw a number that is already true. Nothing
/// here decides anything — the stamp lands in `StampWatch`, whether or not this is on
/// screen or the app is even running.
private struct DwellRing: View {
    var dwell: StampWatch.Dwell

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let left = dwell.remaining
            let done = 1 - (left / StampWatch.dwellSeconds)

            ZStack {
                Circle().stroke(WP.onInk.opacity(0.16), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.001, done))
                    .stroke(WP.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(Self.clock(left))
                        .font(WP.mono(19)).monospacedDigit()
                    Text("left".uppercased())
                        .font(WP.body(7)).tracking(1).opacity(0.6)
                }
                .foregroundStyle(WP.onInk)
            }
            .frame(width: 74, height: 74)
            .accessibilityLabel("\(Int(left / 60) + 1) minutes until it stamps itself")
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

// MARK: - What is near

/// One place near enough to be worth naming, and not near enough to stamp.
///
/// The trip tile at a row's size: the same ink plate, the same weather, the same lit edge,
/// with the blooms brought down so they still read as light rather than as a wash. The
/// only thing on it that is the passport's own is the dashed disc — a page waiting to be
/// cancelled, which is what this row is about.
struct NearbyStampRow: View {
    var ranked: RankedStamp

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.white.opacity(0.34))
                Text(short)
                    .font(WP.headingUI(9.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .padding(5)
                    .opacity(0.78)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(ranked.place.name)
                    .font(WP.display(19))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(WP.bodyItalic(11.5)).opacity(0.68)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.0f mi", ranked.miles))
                    .font(WP.body(13, semibold: true)).monospacedDigit()
                // How much further there is to go before it can be stamped, which is a
                // different number from how far away it is — and the one that matters
                // when a park's reach is thirty miles wide.
                Text(String(format: "%.0f to go", ranked.toEdge))
                    .font(WP.bodyItalic(10.5)).opacity(0.6)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .inkPlate(radius: 18, scale: 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ranked.place.name), \(subtitle), \(Int(ranked.miles)) miles away")
    }

    private var subtitle: String {
        ranked.place.place.isEmpty
            ? ranked.place.designation
            : "\(ranked.place.designation) · \(ranked.place.place)"
    }

    private var short: String {
        ranked.place.name.split(separator: " ").prefix(2).joined(separator: " ")
    }
}

// MARK: - Whether it may stamp on its own

/// The one switch, and the invitation that stands in for it before permission is given.
///
/// Two different things wearing one row. Before the phone is allowed to watch, this is an
/// offer and tapping it asks. After, it is a switch and tapping it flips. They are the
/// same row because they are the same question, and splitting them would have the book
/// grow a settings section for one preference.
struct StampsItselfRow: View {
    @Environment(AppState.self) private var app
    @State private var watch = StampWatch.shared

    var body: some View {
        Button {
            if watch.isWatching {
                app.setStampsItself(!app.stampsItself)
            } else {
                app.setStampsItself(true)
            }
            Haptics.tap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: watch.isWatching ? "location.fill" : "location")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WP.accent700)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WP.rowTitle(15))
                    Text(detail)
                        .font(WP.bodyItalic(11.5))
                        .foregroundStyle(WP.neutral600)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)

                if watch.isWatching {
                    WPSwitch(isOn: app.stampsItself)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WP.neutral500)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .liquidGlass(.pill, radius: 18)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    private var title: String {
        watch.isWatching ? "Stamp it for me" : "Let the book find you"
    }

    private var detail: String {
        guard watch.isWatching else {
            return "Turn on location and the book knows what you are standing in, wherever you are."
        }
        if !app.stampsItself {
            return "Off. Everything nearby still appears; nothing lands without your thumb."
        }
        return watch.wakesInBackground
            ? "Fifteen unbroken minutes inside a park and it stamps, whether the app is open or not."
            : "Fifteen unbroken minutes inside a park. With location set to While Using, it lands the next time you open the app."
    }
}

import SwiftUI

/// The year pass: a park under your name, turning with the phone.
///
/// Four things and no more — whose it is, which year, and how much of each register has
/// been stood in. Everything else on it is surface: an engraving over the photograph the
/// way security print puts a guilloché, a specular that rakes across as the phone turns,
/// and a foil whose hue turns with it.
///
/// All three of those come off the same pair of numbers, which is what makes it read as
/// one surface rather than three effects laid over each other.
struct YearPassCard: View {
    @Environment(AppState.self) private var app
    @State private var tilt = DeviceTilt.shared

    /// A credit card, near enough: 85.6 by 54 millimetres.
    static let ratio: CGFloat = 300.0 / 190.0

    var width: CGFloat

    /// Never zero, never negative.
    ///
    /// A `GeometryReader` reports nothing on its first pass, and the size this is handed is
    /// arithmetic on that — a width less two gutters, a height less the sheet. On the pass
    /// where the reader says nothing, both come out negative, and a negative frame is not a
    /// small card: it is a trap in SwiftUI, and so is a radial gradient with a negative
    /// radius. Everything below is measured off `side`, so one floor covers all of it.
    private var side: CGFloat { max(120, width) }
    private var height: CGFloat { side / Self.ratio }

    /// How far the card turns at the ends of the range. Past about ten degrees a rectangle
    /// starts reading as a room rather than as a card on a table.
    private static let turn: Double = 9

    var body: some View {
        ZStack {
            photograph
            Contours().stroke(Color(hex: 0xF3E3C2, opacity: 0.26), lineWidth: 0.7)
                .frame(height: height * 0.62)
                .frame(maxHeight: .infinity, alignment: .top)
            band
            words
            foil
            sheen
            rim
        }
        .frame(width: side, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x000000, opacity: 0.52), radius: 22, y: 14)
        // Two axes, chained. A single combined axis turns the card about a diagonal, which
        // reads as a wobble rather than as a thing being tipped.
        .rotation3DEffect(.degrees(-tilt.pitch * Self.turn),
                          axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(tilt.roll * Self.turn * 1.4),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .readsTilt()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: The picture

    /// The park the year belongs to: the last one stood in, or the app's own hero before
    /// there is one. Never an empty frame.
    private var park: CuratedPark? { app.visitRail.first?.park }

    @ViewBuilder
    private var photograph: some View {
        if let park, let photo = ParkPhotos.shared.photo(for: park) {
            AsyncImage(url: photo.url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                hero
            }
        } else {
            hero
        }
    }

    private var hero: some View {
        Image("Onboarding-Hero").resizable().aspectRatio(contentMode: .fill)
    }

    // MARK: The type

    /// The band the words are read off. A pass is a photograph you can still read a name on.
    private var band: some View {
        LinearGradient(
            colors: [Color(hex: 0x071A16, opacity: 0.96),
                     Color(hex: 0x09201B, opacity: 0.84),
                     Color(hex: 0x0B2B26, opacity: 0)],
            startPoint: .bottom, endPoint: .top
        )
        .frame(height: height * 0.44)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("ParkHop".uppercased())
                    .font(WP.body(8)).tracking(1.7)
                    .foregroundStyle(Color(hex: 0xFFF8E8, opacity: 0.9))
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                // Over the sky, the one part of a landscape with nothing to read under it,
                // so the year can be large without crowding anything.
                Text(String(year))
                    .font(WP.display(side * 0.12))
                    .foregroundStyle(WP.brass)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 14) {
                Text(holder)
                    .font(WP.body(side * 0.047)).tracking(2.4)
                    .foregroundStyle(Color(hex: 0xF0E4CB))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    stat("National", nationalCount)
                    stat("State", stateCount)
                }
            }
        }
        .padding(.horizontal, side * 0.053)
        .padding(.top, side * 0.043)
        .padding(.bottom, side * 0.047)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(WP.body(7.5)).tracking(1.4)
                .foregroundStyle(WP.brass.opacity(0.55))
            Text(value)
                .font(WP.body(11)).monospacedDigit()
                .foregroundStyle(Color(hex: 0xF0E4CB))
        }
    }

    // MARK: The surface

    /// The lit edge. Brass, and brighter along the top, so the card has a rim rather than
    /// a border.
    private var rim: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color(hex: 0xFFE1AA, opacity: 0.42),
                                        Color(hex: 0xC69E56, opacity: 0.5),
                                        Color(hex: 0x000000, opacity: 0.36)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
    }

    /// The highlight, wherever the light would be coming from. This is what sells metal.
    private var sheen: some View {
        RadialGradient(
            colors: [Color(hex: 0xFFF6E0, opacity: 0.38),
                     Color(hex: 0xFFF0D2, opacity: 0.11),
                     Color(hex: 0xFFFFFF, opacity: 0)],
            center: UnitPoint(x: 0.5 + tilt.roll * 0.42, y: 0.42 - tilt.pitch * 0.34),
            startRadius: 0, endRadius: side * 0.62
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    /// The foil: the app's own colours going round, turned by the same wrist.
    private var foil: some View {
        AngularGradient(
            colors: [WP.accent700, WP.lime, Color(hex: 0x8ECFB4), WP.accent, WP.accent700],
            center: .center,
            angle: .degrees(tilt.roll * 180)
        )
        .blendMode(.colorDodge)
        .opacity(0.16)
        .allowsHitTesting(false)
    }

    // MARK: What it says

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    private var holder: String {
        let name = (app.profileName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "ADD YOUR NAME" : name.uppercased()
    }

    /// The rail split the way `CuratedPark` already splits itself, so the card counts the
    /// same parks the profile above it counts.
    private var stood: (national: Int, state: Int) {
        let rail = app.visitRail
        let state = rail.filter { $0.park.isStatePark }.count
        return (rail.count - state, state)
    }

    private var nationalCount: String {
        "\(stood.national) of \(NationalParks.all.count)"
    }

    private var stateCount: String {
        "\(stood.state) of \(StateParkTable.all.count.formatted())"
    }

    private var spoken: String {
        "\(year) year pass. \(holder). \(nationalCount) national parks, \(stateCount) state parks."
    }
}

/// The contour lines engraved over the photograph.
///
/// A park app's one mark that belongs to all sixty-three is the shape of the ground, so
/// the card is engraved with the ground rather than with a crest.
private struct Contours: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 9
        for row in 0..<rows {
            let y = rect.height * (0.11 + Double(row) * 0.105)
            let amplitude = rect.height * (0.055 + Double(row % 4) * 0.022)
            path.move(to: CGPoint(x: -8, y: y))
            path.addCurve(to: CGPoint(x: rect.width * 0.64, y: y - amplitude * 0.6),
                          control1: CGPoint(x: rect.width * 0.21, y: y - amplitude),
                          control2: CGPoint(x: rect.width * 0.41, y: y + amplitude))
            path.addCurve(to: CGPoint(x: rect.width + 8, y: y),
                          control1: CGPoint(x: rect.width * 0.82, y: y - amplitude * 0.2),
                          control2: CGPoint(x: rect.width * 0.93, y: y + amplitude * 0.5))
        }
        return path
    }
}

// MARK: - Where it sits

/// What the profile stands on now: the pass, and the way into the atlas.
///
/// This took the place of the map. The map was a picture of the country that could not be
/// touched or read — a door with a photograph on it — and the door is still here, as the
/// control it always was. What fills the space instead is the one object on the profile
/// worth looking at twice.
struct YearPassBackdrop: View {
    /// How far the ground runs on behind the sheet's rounded corners, so nothing shows
    /// through them. The caller adds it to the height it asks for.
    static let underlap: CGFloat = 44

    var size: CGSize
    var onAtlas: () -> Void

    var body: some View {
        // The same floor the card keeps, for the same reason: the first layout pass hands
        // a `GeometryReader` nothing, and every number here is arithmetic on that.
        let across = max(120, size.width)
        let down = max(120, size.height)

        return ZStack {
            // The stage. Darker at the foot so the sheet has something to stand on rather
            // than a hard edge to cut against.
            WP.ink
            RadialGradient(colors: [Color(hex: 0x24322C), Color(hex: 0x101314, opacity: 0)],
                           center: UnitPoint(x: 0.5, y: 0.22),
                           startRadius: 0, endRadius: across * 0.9)

            YearPassCard(width: min(330, across - WP.gutter * 2))
                // Clear of the sheet's top edge and the avatar that straddles it.
                .offset(y: -(Self.underlap / 2) - 18)
        }
        .frame(width: across, height: down)
        .clipped()
        .overlay(alignment: .bottomTrailing) { atlas }
    }

    /// The way into the atlas, and now a real button.
    ///
    /// It used to be a label with `allowsHitTesting(false)` sitting on a map that was
    /// itself the button. With the map gone it has to carry the tap on its own, which is
    /// the honest arrangement anyway: one control, one job.
    private var atlas: some View {
        Button(action: onAtlas) {
            HStack(spacing: 5) {
                Image(systemName: "map")
                    .font(.system(size: 11, weight: .semibold))
                Text("Open the atlas").font(WP.headingUI(12.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .glassControl()
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .padding(.trailing, WP.gutter)
        .padding(.bottom, Self.underlap + 16)
        .accessibilityLabel("Open the atlas")
    }
}

import SwiftUI
import WidgetKit

/// The plate: the photograph is the widget, and everything else sits on it.
///
/// The kicker at the top, the name in the display face at the foot, the save disc in the
/// corner it occupies everywhere else in the app.
struct ParkPlateView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ParkEntry

    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ground
            scrim
            words
            if SavedParks.isShared { save }
        }
        // A small plate gets one tap for the whole tile: WidgetKit gives a small widget a
        // single URL and no room for anything else. The medium one has links of its own,
        // so the words carry the tap and the disc stays a button.
        .widgetURL(isSmall ? ParkPlateView.open(entry.park) : nil)
    }

    // MARK: The picture

    @ViewBuilder
    private var ground: some View {
        if let photo = entry.photo {
            // No `widgetAccentedRenderingMode` here, deliberately.
            //
            // It is a method on `Image`, not a view modifier, so it has to come before
            // `scaledToFill` rather than after it — and it exists only from iOS 18, which
            // this target does not require. It buys one thing: a say in how the picture is
            // treated when somebody tints their home screen. Without it iOS still renders
            // the plate in those modes, desaturated, which is the same answer every other
            // photographic widget gives. Worth adding back once the rest of this is known
            // to build, not worth another round of guessing at an API from here.
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            // What the app draws before a photograph lands, rather than an empty frame:
            // three soft fields in the park's own colours, hashed off its code so the same
            // park is always the same colour.
            BlobGround(seed: entry.park.code)
        }
    }

    private var scrim: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.72), Color.black.opacity(0.20), Color.black.opacity(0.06)],
            startPoint: .bottom, endPoint: .top
        )
    }

    // MARK: The words

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker.uppercased())
                .font(Plate.kicker(isSmall ? 8.5 : 9))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(entry.park.name)
                .font(Plate.display(isSmall ? 25 : 31))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)

            if !isSmall {
                Text(entry.park.full)
                    .font(Plate.body(11.5))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
        .padding(isSmall ? 13 : 16)
        // The medium plate's words are the way in. The small one's whole tile is.
        .modifier(OpensPark(park: entry.park, active: !isSmall))
        // Room for the disc, so a long name never runs under it.
        .padding(.trailing, isSmall ? 30 : 34)
    }

    private var kicker: String {
        entry.park.state.isEmpty ? "National Park" : "\(entry.park.state) · National Park"
    }

    // MARK: Saving

    private var save: some View {
        Button(intent: ToggleSaveIntent(code: entry.park.code)) {
            Image(systemName: entry.isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: isSmall ? 13 : 14, weight: .semibold))
                .foregroundStyle(entry.isSaved ? Plate.accent : Plate.text)
                .frame(width: isSmall ? 32 : 36, height: isSmall ? 32 : 36)
                .background(entry.isSaved ? AnyShapeStyle(Plate.onInk.opacity(0.92))
                                          : AnyShapeStyle(Plate.lime),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .padding(isSmall ? 11 : 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityLabel(entry.isSaved ? "Saved. Remove from saved." : "Save for later")
    }

    /// Where a tap on this park goes. Read by the app's `onOpenURL`.
    static func open(_ park: WidgetPark) -> URL? {
        URL(string: "parkhop://park/\(park.code)")
    }
}

/// Wraps its content in a `Link` on the sizes that may carry one.
///
/// A `Link` inside a small widget is ignored — the family has one URL and it is
/// `widgetURL` — so this is a modifier rather than a branch at every call site.
private struct OpensPark: ViewModifier {
    var park: WidgetPark
    var active: Bool

    func body(content: Content) -> some View {
        if active, let url = ParkPlateView.open(park) {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

/// The park's own colours, for a plate whose photograph has not arrived.
///
/// The same idea as the app's `BlobField` — three soft fields and a lit top edge — built
/// from the park's code so one park is always one colour. Blur is expensive to render in
/// an extension, so these are gradients with soft stops rather than blurred shapes.
private struct BlobGround: View {
    var seed: String

    private var hues: [Double] {
        var hash = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ Int(byte) }
        let base = Double(abs(hash) % 360)
        return [base, (base + 42).truncatingRemainder(dividingBy: 360),
                (base + 310).truncatingRemainder(dividingBy: 360)]
    }

    private func shade(_ hue: Double, _ light: Double) -> Color {
        Color(hue: hue / 360, saturation: 0.34, brightness: light)
    }

    var body: some View {
        let hue = hues
        ZStack {
            shade(hue[0], 0.42)
            RadialGradient(colors: [shade(hue[1], 0.58).opacity(0.95), .clear],
                           center: UnitPoint(x: 0.16, y: 0.18), startRadius: 0, endRadius: 190)
            RadialGradient(colors: [shade(hue[2], 0.34).opacity(0.95), .clear],
                           center: UnitPoint(x: 0.88, y: 0.12), startRadius: 0, endRadius: 170)
            RadialGradient(colors: [shade(hue[1], 0.26).opacity(0.9), .clear],
                           center: UnitPoint(x: 0.52, y: 0.96), startRadius: 0, endRadius: 200)
            LinearGradient(colors: [.white.opacity(0.20), .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
    }
}

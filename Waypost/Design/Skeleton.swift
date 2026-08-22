import SwiftUI

/// The shape of an answer that has been asked for and has not arrived.
///
/// Drawn only where the app can say, before it asks, how many things are coming — a trip
/// has one leg per park, the overview has three points, a leg row has one forecast. Where
/// the count is unknown and may be zero the screen keeps saying a sentence instead: five
/// grey rows resolving to no campgrounds is an invented value with a shape rather than a
/// number, and the rule this app is built on covers both.
///
/// `ParkImage` has done this since the beginning — the park's own colour field is drawn at
/// once and the photograph laid over it, so the frame never changes and nothing below it
/// moves. These are the same idea for the places that have no colour field to fall back on.
///
/// A skeleton makes a slow screen feel considered. It does not make it fast, and it is not
/// a substitute for asking for less.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat
    var corner: CGFloat

    init(width: CGFloat? = nil, height: CGFloat = 12, corner: CGFloat = 4) {
        self.width = width
        self.height = height
        self.corner = corner
    }

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(WP.neutral200)
            .frame(width: width, height: height)
    }
}

/// The breathe, applied once to a whole group so its parts move as one thing.
///
/// One opacity, and no shimmer sweeping across the bars. A sweep is a second animation
/// running at the display's rate on every row at once, and this app already keeps a
/// `Canvas` redrawing itself twenty-four times a second on the park screen — a loading
/// state is the last place to spend more of the frame budget.
///
/// Frozen flat under Reduce Motion, the way `WaveFill` freezes. A block quietly pulsing at
/// the edge of vision is close to the top of the list of things that setting exists for.
private struct SkeletonBreath: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.85 : (dim ? 0.55 : 1))
            .animation(reduceMotion
                       ? nil
                       : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: dim)
            .onAppear { dim = true }
            // Nothing here is readable, so VoiceOver is not offered it. Every screen that
            // draws a skeleton keeps the sentence saying what is being waited for, which
            // is what a reader who cannot see the bars needs and the bars never were.
            .accessibilityHidden(true)
    }
}

extension View {
    /// Marks a group of `SkeletonBar`s as one waiting thing.
    func skeletonBreath() -> some View { modifier(SkeletonBreath()) }
}

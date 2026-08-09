import SwiftUI

/// The app's motion vocabulary, transcribed from the design's keyframes and then given
/// the iOS-native equivalents where the platform does it better.
///
/// The design writes five: `wp-push`/`wp-pop` for screens, `wp-up`/`wp-down` for sheets,
/// `wp-panel` for a section swapping in, `wp-stamp` for a stamp landing, `wp-pulse` for
/// one waiting to be collected. Push, pop and the sheets are handed to the system —
/// `NavigationStack` and `.sheet` do them with interactive dismissal, which no keyframe
/// can. The other three live here.
enum Motion {

    /// `wp-panel` — a section swapping in under a segment control: 8pt up, fading.
    /// 0.28s ease in the design; a snappy spring reads the same and settles better when
    /// a second tap interrupts it.
    static let panel: Animation = .snappy(duration: 0.28, extraBounce: 0.05)

    /// The transition that goes with it.
    static var panelTransition: AnyTransition {
        .opacity.combined(with: .offset(y: 8))
    }

    /// `wp-stamp` — 0.35 scale and a 16° tilt, overshooting to 1.1 before it settles.
    /// `cubic-bezier(0.3, 1.4, 0.5, 1)` is an overshoot curve, which is a spring.
    static let stamp: Animation = .spring(response: 0.42, dampingFraction: 0.52)

    /// Screens and sheets: the system's own, so the interactive back-swipe and the
    /// sheet's rubber-banding come with them.
    static let navigation: Animation = .spring(response: 0.38, dampingFraction: 0.88)

    /// A value ticking over — a countdown, a day number, a stamp count. Paired with
    /// `.contentTransition(.numericText())` so digits roll rather than cross-fade.
    static let counter: Animation = .snappy(duration: 0.32)

    /// The toast, matching `wp-toast`: 12pt up, fading.
    static let toast: Animation = .snappy(duration: 0.24)
}

// MARK: - wp-pulse

/// `wp-pulse` — a ring that swells out of an uncollected stamp and fades, twice a second
/// slowed to two seconds. It marks the one thing on the screen you can still do.
struct PulseRing: ViewModifier {
    var colour: Color = WP.accent
    var active: Bool = true

    @State private var expanded = false

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    Circle()
                        .stroke(colour.opacity(expanded ? 0 : 0.5), lineWidth: expanded ? 8 : 0)
                        .scaleEffect(expanded ? 1.18 : 1)
                        .animation(
                            .easeOut(duration: 2).repeatForever(autoreverses: false),
                            value: expanded
                        )
                }
            }
            .onAppear { expanded = active }
            .onChange(of: active) { _, isActive in expanded = isActive }
    }
}

extension View {
    /// The waiting-stamp pulse.
    func pulseRing(_ colour: Color = WP.accent, active: Bool = true) -> some View {
        modifier(PulseRing(colour: colour, active: active))
    }

    /// A panel that swaps in when a segment changes.
    func panelTransition(id: some Hashable) -> some View {
        self
            .id(id)
            .transition(Motion.panelTransition)
            .animation(Motion.panel, value: id)
    }

    /// A number that changes in place: digits roll, and the layout does not jump because
    /// the figures are already tabular.
    func rollingNumber<V: Equatable>(_ value: V) -> some View {
        self
            .contentTransition(.numericText())
            .animation(Motion.counter, value: value)
    }

    /// Cards easing in as they reach the top of the fold. iOS 17's scroll transitions do
    /// this against real scroll position rather than on appearance, so it holds up when
    /// you scroll back.
    func liftOnScroll(_ enabled: Bool = true) -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(enabled ? (phase.isIdentity ? 1 : 0.55) : 1)
                .scaleEffect(enabled ? (phase.isIdentity ? 1 : 0.97) : 1)
                .blur(radius: enabled ? (phase.isIdentity ? 0 : 1.2) : 0)
        }
    }
}

// MARK: - Zoom navigation

/// The zoom transition, where the tapped card becomes the screen it opens.
///
/// iOS 18 added `matchedTransitionSource` / `navigationTransition(.zoom:)`, and it is
/// exactly the gesture this app wants: a park's colour field is its identity, so the card
/// growing into the header reads as the same object rather than a new page. Below 18 the
/// push slides, as the design's `wp-push` does.
struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

/// The outlines a zoom source can take. `matchedTransitionSource` accepts a
/// `RoundedRectangle` and nothing else — a `Capsule` is a compile error there — so a
/// round-ended control is written as a rectangle whose radius is half its height.
extension RoundedRectangle {
    /// The shape of the app's round-ended controls. Circular corners, not continuous:
    /// at radius = height / 2 a squircle is visibly not a capsule.
    static func pill(height: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: height / 2, style: .circular)
    }

    /// The shape of a card. The radius has to be the card's own — the zoom draws this
    /// outline over the real one, and a 22 over a 28 is a visible corner popping.
    static func card(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    /// Marks the view a pushed screen should grow out of.
    ///
    /// The shape is not optional in practice. Left unconfigured, UIKit lays its own plate
    /// under the source for the length of the transition — an opaque rounded *rectangle*
    /// with a drop shadow, sized to the frame — so a capsule pill flashed as a block for
    /// the half-second the zoom ran. Handing it the control's real outline, no fill and no
    /// shadow leaves nothing to see but the view itself growing.
    @ViewBuilder
    func zoomSource(_ id: String, in namespace: Namespace.ID?, clip: RoundedRectangle) -> some View {
        if #available(iOS 18.0, *), let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source
                    .clipShape(clip)
                    .background(Color.clear)
                    .shadow(color: .clear, radius: 0)
            }
        } else {
            self
        }
    }

    /// Marks the pushed screen as the destination of that zoom.
    @ViewBuilder
    func zoomDestination(_ id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

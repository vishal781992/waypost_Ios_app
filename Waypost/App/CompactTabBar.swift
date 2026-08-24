import SwiftUI

/// The floating tab bar, drawn rather than borrowed.
///
/// The system bar on iOS 26 owns its own geometry: it spans the screen, spaces its items
/// across that width, and exposes no knob for either. The legacy `UITabBar.appearance()`
/// layout properties — `itemWidth`, `itemSpacing`, `itemPositioning` — are read by the old
/// bar and ignored by the new one, which was measured, not assumed. So a bar that hugs its
/// four items instead of stretching past them has to be this: the native bar hidden, and
/// this in its place.
///
/// Two things the native bar gave for free come back by hand — the selection pill morphing
/// between items, and the bar minimising as you read down a screen. Everything else about
/// the tabs is still the system's: `TabView` keeps the selection, the per-tab navigation
/// stacks and the zoom transitions.
struct CompactTabBar: View {
    @Binding var selection: AppTab
    var isMinimized: Bool

    @Namespace private var pill

    /// Wide enough for "Profile" at 11pt and no wider. The whole point of the bar is
    /// that it ends where its items do.
    ///
    /// 68×52 rather than 62×46: the bar is the app's most-used control and it was the
    /// smallest target on the screen, a couple of points over the 44pt floor in one
    /// direction and reached with a thumb at the far end of its stretch.
    private let itemWidth: CGFloat = 68
    private let itemHeight: CGFloat = 52

    /// What an item is *drawn* at when the bar is held out of the way: the name and
    /// nothing else, on one line. Sixteen points of ink and ten of type — as slim as four
    /// names go before the type stops being legible or one of them has to leave.
    private let slimItemHeight: CGFloat = 16

    /// Apple's floor for anything a finger has to find. The bar was already grown once for
    /// this reason, and a twenty-six point strip puts it back under the line — so the ink
    /// shrinks and the target does not. Each item keeps a forty-four point frame with the
    /// extra height transparent, above and below the capsule.
    private let minimumTarget: CGFloat = 44

    /// The height of the drawn capsule. The frame around it is taller; this is the glass.
    private var plateHeight: CGFloat { inkHeight + 10 }
    private var inkHeight: CGFloat { isMinimized ? slimItemHeight : itemHeight }
    /// Transparent, and only ever positive where the ink is smaller than a thumb.
    private var overhang: CGFloat { max(0, (minimumTarget - inkHeight) / 2) }

    /// What the bar takes up in the layout: whichever is taller, the glass or the targets.
    ///
    /// Stated rather than left to the content, because the two disagree in both directions.
    /// Whole, the plate is taller than the items and the glass would otherwise draw outside
    /// the bar's own bounds — which moved it five points down the screen, under the home
    /// indicator. Slim, the targets are taller than the plate.
    private var barHeight: CGFloat { max(plateHeight, inkHeight + overhang * 2) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: barHeight)
        // The glass is a background rather than a wrapper, because the stack is as tall as
        // a thumb needs and the capsule is only as tall as the ink. Wrapped, the plate
        // would grow to the touch area and the bar would not look slim at all.
        .background {
            Color.clear
                .frame(height: plateHeight)
                .liquidGlass(.tabBar, radius: 999)
                .shadow(color: Color(hex: 0x181008, opacity: 0.10), radius: 12, y: 4)
        }
        .animation(Motion.panel, value: isMinimized)
        .animation(Motion.panel, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                // The glyph is what goes. Every name stays, in the same order, in the same
                // places — so the bar folds rather than emptying, and the destination you
                // want is where it was a moment ago.
                if !isMinimized {
                    TabIcon(tab: tab)
                        .frame(width: 29, height: 29)
                }
                Text(tab.label)
                    .font(WP.body(isMinimized ? 10 : 11, semibold: isSelected))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? WP.neutral900 : WP.neutral600)
            .frame(width: itemWidth, height: inkHeight)
            .background {
                if isSelected {
                    // Not quite opaque: the bar is glass, and a flat fill on top of it
                    // reads as a sticker rather than as part of the same pane.
                    Capsule()
                        .fill(WP.tabSelection.opacity(0.90))
                        .matchedGeometryEffect(id: "selection", in: pill)
                }
            }
            // Transparent, and the whole point: the ink is sixteen points and the finger
            // gets forty-four. Zero when the bar is whole, because fifty-two already is.
            .padding(.vertical, overhang)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Minimise on scroll

/// Whether the bar is currently held out of the way. Owned by the shell and read by the
/// bar, so any root screen can drive it without knowing the bar exists.
@MainActor
@Observable
final class TabBarChrome {
    var isMinimized = false

    func reset() {
        guard isMinimized else { return }
        withAnimation(Motion.panel) { isMinimized = false }
    }
}

extension View {
    /// Applied to a root screen's *vertical* scroll view. Reading down minimises the bar,
    /// reading back up brings it out again — the `onScrollDown` behaviour the system bar
    /// has on iOS 26, which went away with the system bar.
    ///
    /// It goes on the scroll view itself rather than on the shell because a screen like
    /// Today also carries horizontal rails, and a shell-level observer would take a sideways
    /// flick through one of those for a downward read of the page.
    func tracksTabBarMinimize() -> some View {
        modifier(TabBarMinimizeTracker())
    }
}

private struct TabBarMinimizeTracker: ViewModifier {
    @Environment(TabBarChrome.self) private var chrome
    @State private var lastOffset: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Reading.self) { geometry in
                Reading(
                    offset: geometry.contentOffset.y,
                    limit: geometry.contentSize.height - geometry.containerSize.height
                )
            } action: { _, reading in
                update(with: reading)
            }
        } else {
            content
        }
    }

    /// Where the scroll is, and how far it can go. The limit is what tells a real read
    /// apart from a bounce.
    private struct Reading: Equatable {
        var offset: CGFloat
        var limit: CGFloat
    }

    private func update(with reading: Reading) {
        // A page with barely anything below the fold keeps its bar. Hiding it to uncover
        // another forty points of content is the worse trade.
        guard reading.limit > 120 else { return }

        // Inside the content only. Overscroll at either end runs backwards as it springs
        // home, and that return reads as a scroll the other way — the bar minimised on the
        // flick and came back 200ms later, which looked like it was not working at all.
        guard reading.offset >= 0, reading.offset <= reading.limit else { return }

        let delta = reading.offset - lastOffset
        // Below the threshold this fires on the settling after a flick, and the bar
        // flickers between the two states.
        guard abs(delta) > 6 else { return }
        lastOffset = reading.offset

        // Never minimised at the top of a screen: the bar should be whole when the page is.
        let shouldMinimize = delta > 0 && reading.offset > 24
        guard chrome.isMinimized != shouldMinimize else { return }
        withAnimation(Motion.panel) { chrome.isMinimized = shouldMinimize }
    }
}

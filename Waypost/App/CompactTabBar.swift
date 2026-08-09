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

    /// Wide enough for "Profile" at 10.5pt and no wider. The whole point of the bar is
    /// that it ends where its items do.
    private let itemWidth: CGFloat = 62
    private let itemHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .liquidGlass(.tabBar, radius: 999)
        .shadow(color: Color(hex: 0x181008, opacity: 0.10), radius: 12, y: 4)
        .animation(Motion.panel, value: isMinimized)
        .animation(Motion.panel, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// Minimised, the bar carries the selected tab alone — the same reduction the system
    /// bar makes, which is what tells you it is still there without holding the page.
    private var visibleTabs: [AppTab] {
        isMinimized ? [selection] : AppTab.allCases
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                TabIcon(tab: tab)
                    .frame(width: 26, height: 26)
                Text(tab.label)
                    .font(WP.body(10.5, semibold: isSelected))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? WP.neutral900 : WP.neutral600)
            .frame(width: itemWidth, height: itemHeight)
            .background {
                if isSelected {
                    // Not quite opaque: the bar is glass, and a flat fill on top of it
                    // reads as a sticker rather than as part of the same pane.
                    Capsule()
                        .fill(WP.tabSelection.opacity(0.90))
                        .matchedGeometryEffect(id: "selection", in: pill)
                }
            }
            .contentShape(Capsule())
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

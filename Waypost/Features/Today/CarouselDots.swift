import SwiftUI

/// Where you are in the rotation, and a way to jump.
///
/// The active dot is a pill rather than a brighter circle: width reads at a glance on a
/// photograph where opacity alone does not, and it is the one part of the indicator that
/// survives a pale sky behind it.
///
/// The playlist is every national park, and sixty-three dots is not an indicator — it is a
/// hairline of noise under the wordmark. So the row is a window of seven, centred on the
/// dot showing, with the outermost pair shrunk whenever there is more playlist past them.
/// That is the convention iOS's own page control falls back on, and it says the two things
/// worth saying: roughly where you are, and that there is more in both directions.
struct CarouselDots: View {
    var count: Int
    var index: Int
    var onSelect: (Int) -> Void

    /// Seven is about forty points of row. More reads as a ruler.
    private static let maxVisible = 7
    /// The gap the design draws between dots. Spent as target rather than as air: the
    /// spacing lives inside each dot's own hit rect, so the row looks identical and every
    /// pixel between two dots belongs to one of them.
    private static let gap: CGFloat = 7

    /// `cubic-bezier(0.32, 0.72, 0, 1)` — the app's own curve, the one the tab pill and
    /// the push transition already move on.
    private static let morph = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.5)

    /// The first playlist position the row is showing. Held still at either end so the
    /// window stops rather than running off the playlist.
    private var start: Int {
        guard count > Self.maxVisible else { return 0 }
        return min(max(index - Self.maxVisible / 2, 0), count - Self.maxVisible)
    }

    private var visible: Range<Int> { start..<min(start + Self.maxVisible, count) }

    var body: some View {
        // Spacing 0 — each dot carries its own gap. An `HStack` gap is dead space, and at
        // this size the whole row is only about forty points wide.
        HStack(spacing: 0) {
            ForEach(visible, id: \.self) { position in
                dot(at: position)
            }
        }
        .animation(Self.morph, value: index)
        .frame(height: 44)
        // One control, not seven: VoiceOver swipes through the rotation rather than
        // hunting for a 6pt circle, and it counts the whole playlist, not the window.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo \(index + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(index + 1, count - 1))
            case .decrement: onSelect(max(index - 1, 0))
            @unknown default: break
            }
        }
    }

    private func dot(at position: Int) -> some View {
        let isActive = position == index
        // Shrunk only when it is standing in for playlist the row cannot show. At the ends
        // of the playlist the edge dot is a real last dot and stays full size.
        let isFading = (position == visible.lowerBound && visible.lowerBound > 0)
            || (position == visible.upperBound - 1 && visible.upperBound < count)
        let width: CGFloat = isActive ? 22 : (isFading ? 4 : 6)

        return Button {
            onSelect(position)
        } label: {
            Capsule(style: .circular)
                .fill(Color(hex: 0xFBF6EE))
                .frame(width: width, height: isFading ? 4 : 6)
                .opacity(isActive ? 1 : (isFading ? 0.24 : 0.40))
                .shadow(color: Color(hex: 0x060301, opacity: 0.4), radius: 2.5, y: 1)
                // The dot is 6pt tall and the finger is not. The target grows to the full
                // height and to its own slot; the mark does not move.
                .frame(width: width + Self.gap, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

// The onboarding screens are photographic and always dark, so they carry their own palette
// and type rather than borrowing `WP`, whose tokens are tuned for paper.

enum PH {
    /// Behind the photograph, and the only thing visible before it decodes.
    static let ink = Color(hex: 0x14100C)
    /// Display type on the photograph.
    static let paperWarm = Color(hex: 0xFAF5EC)
    /// The primary button's label, a shade brighter than the headline.
    static let paperBright = Color(hex: 0xFFFAF2)
    /// Gold. A stroke and a small mark; never a fill.
    static let accent = Color(hex: 0xB68235)
}

extension Font {
    /// Cormorant Garamond, at a weight that is never bold.
    ///
    /// The regular and italic faces are not in the bundle yet — only SemiBold and Bold are —
    /// so this falls back to SemiBold rather than to `.custom`'s silent system default, which
    /// would put a sans-serif where the design calls for a serif. Drop
    /// `CormorantGaramond-Regular.ttf` and `-Italic.ttf` into Resources/Fonts, add them to
    /// `UIAppFonts`, and this corrects itself with no other change.
    static func phDisplay(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom(PHFont.available("CormorantGaramond-Regular"), size: size, relativeTo: style)
    }

    static func phDisplayItalic(_ size: CGFloat, relativeTo style: TextStyle = .title) -> Font {
        .custom(PHFont.available("CormorantGaramond-Italic"), size: size, relativeTo: style)
    }
}

enum PHFont {
    /// The named face if it registered, otherwise the nearest one that did.
    static func available(_ name: String) -> String {
        UIFont(name: name, size: 12) != nil ? name : "CormorantGaramond-SemiBold"
    }
}

// MARK: - The glass control

/// The pill both screens are built from: a material, a white fill, a hairline stroke, an
/// inner light and shade that make it read as glass rather than as a translucent rectangle,
/// and a sheen along the top edge.
/// How loud a pill is. Outside `GlassPill` so a call site can name it without naming the
/// pill's label type.
enum GlassEmphasis {
    case primary, secondary

    var fill: Double { self == .primary ? 0.19 : 0.13 }
    var stroke: Double { self == .primary ? 0.40 : 0.32 }
    var sheen: Double { self == .primary ? 0.78 : 0.60 }
}

struct GlassPill<Label: View>: View {
    var emphasis: GlassEmphasis = .secondary
    var height: CGFloat = 52
    var action: () -> Void
    @ViewBuilder var label: Label

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(surface)
                .overlay(sheen)
                .overlay(innerLight)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(emphasis.stroke), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.36), radius: 14, y: 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
        .animation(.spring(duration: 0.22), value: pressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            // No material at all: the point of the setting is that nothing behind shows
            // through, so a blur with a wash over it would be the same failure, quieter.
            Color.white.opacity(0.22)
        } else {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(emphasis.fill))
        }
    }

    /// A hairline along the top edge, inset at both ends, brightest in the middle — the
    /// thing that reads as a curved surface catching light.
    private var sheen: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(emphasis.sheen), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.84, height: 1)
            .position(x: geo.size.width / 2, y: 0.5)
        }
        .allowsHitTesting(false)
    }

    /// Light from the top-left, shade to the bottom-right. Without the pair the pill reads
    /// as a flat translucent panel.
    private var innerLight: some View {
        Capsule()
            .stroke(
                LinearGradient(colors: [.white.opacity(0.44), .clear, .white.opacity(0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.6
            )
            .blur(radius: 1)
            .allowsHitTesting(false)
    }
}

// MARK: - The photograph

/// The hero, and the scrims that make type legible on it.
///
/// The photograph is bundled rather than fetched: this runs before any network call, and a
/// welcome screen that waits on a request is not a welcome. Until `Onboarding-Hero` is in
/// the asset catalogue this falls back to the ink field, so the layout is still previewable.
struct OnboardingHero: View {
    enum Screen { case welcome, auth }

    var screen: Screen

    /// The buttes sit in the upper third; the crop anchor differs slightly per screen so the
    /// second one has more room for its controls.
    private var anchor: UnitPoint {
        screen == .welcome ? UnitPoint(x: 0.52, y: 0.34) : UnitPoint(x: 0.52, y: 0.30)
    }

    private var bottomStops: [Gradient.Stop] {
        screen == .welcome
            ? [.init(color: Color(hex: 0x100A06, opacity: 0.96), location: 0),
               .init(color: Color(hex: 0x100A06, opacity: 0.90), location: 0.20),
               .init(color: Color(hex: 0x120B07, opacity: 0.62), location: 0.38),
               .init(color: Color(hex: 0x140C08, opacity: 0.20), location: 0.58),
               .init(color: Color(hex: 0x140C08, opacity: 0.02), location: 0.76)]
            : [.init(color: Color(hex: 0x100A06, opacity: 0.97), location: 0),
               .init(color: Color(hex: 0x100A06, opacity: 0.93), location: 0.26),
               .init(color: Color(hex: 0x120B07, opacity: 0.72), location: 0.44),
               .init(color: Color(hex: 0x140C08, opacity: 0.26), location: 0.62),
               .init(color: Color(hex: 0x140C08, opacity: 0.02), location: 0.78)]
    }

    var body: some View {
        PH.ink
            .overlay {
                if let image = UIImage(named: "Onboarding-Hero") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .alignmentGuide(.top) { _ in 0 }
                        .clipped()
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(stops: bottomStops, startPoint: .bottom, endPoint: .top)
                    .frame(height: 620)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // So the status bar reads against a bright sky.
                LinearGradient(colors: [Color(hex: 0x0C0805, opacity: 0.34), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The legal line both screens end on.
struct OnboardingLegal: View {
    var opacity: Double
    var linkOpacity: Double
    var onTerms: () -> Void
    var onPrivacy: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("By continuing you agree to the ")
            Button("Terms", action: onTerms)
                .underline()
                .foregroundStyle(PH.paperWarm.opacity(linkOpacity))
            Text(" and ")
            Button("Privacy Policy", action: onPrivacy)
                .underline()
                .foregroundStyle(PH.paperWarm.opacity(linkOpacity))
            Text(".")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(PH.paperWarm.opacity(opacity))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

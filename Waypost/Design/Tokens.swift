import SwiftUI
import UIKit

/// The Classical design-system tokens, transcribed from `_ds/classical/styles.css`, plus
/// the values the mobile design layers on top of them.
///
/// Everything here is a literal from the design. Where the design writes a colour in
/// OKLCH — every park identity, every traffic light, every dashboard ramp — this file
/// keeps the OKLCH numbers and converts at runtime, so the colour on the phone is the
/// colour in the design rather than a hand-eyed hex approximation.
enum WP {

    // MARK: Palette

    /// The page. Read through `PageTint` so the colour can be tried on live while it is
    /// still being chosen; ships as #D1CFA5.
    @MainActor static var bg: Color { PageTint.shared.colour }
    /// What sits *on* ink — the trip cards, the permit plate, the glyph on a dark disc.
    /// This was `bg` when the page was near-white and the two were the same colour by
    /// coincidence; they are different things and now they look it.
    static let onInk = Color(hex: 0xF3F2F2)
    static let surface = Color(hex: 0xEAE9E9)
    static let text = Color(hex: 0x201F1D)
    static let accent = Color(hex: 0xB68235)
    static let accent2 = Color(hex: 0xAC803E)

    /// The orange out of the app's mark — the counter of the "o" in ParkHop.
    ///
    /// The one colour the icon and the interface share, so the round controls read as the
    /// same product as the thing on the home screen. Kept out of the accent ramp because it
    /// is the mark's colour rather than the page's, and it should stay that way: everything
    /// wearing it is a control you press.
    static let mark = Color(hex: 0xFF9932)
    /// The page behind the device in the design — used for the deepest scrim.
    static let clay = Color(hex: 0xDCD7CF)

    /// The booking pills: a campground's page on Recreation.gov or on nps.gov.
    ///
    /// One colour for both because they are one action — "go and read the official page
    /// for this campground" — and which register happens to hold it is the app's problem,
    /// not the reader's. Too pale to letter on the page, so the pill is filled with it and
    /// the type sits on top in ink.
    static let book = Color(hex: 0xDBE64C)

    static let neutral100 = Color(hex: 0xF8F4F4)
    static let neutral200 = Color(hex: 0xEAE7E7)
    static let neutral300 = Color(hex: 0xD7D3D3)
    static let neutral400 = Color(hex: 0xBAB6B6)
    static let neutral500 = Color(hex: 0x9B9797)
    static let neutral600 = Color(hex: 0x7D7979)
    static let neutral700 = Color(hex: 0x605D5D)
    static let neutral800 = Color(hex: 0x444141)
    static let neutral900 = Color(hex: 0x2D2B2B)

    /// The selected tab's capsule. The one place the palette leaves its warm neutrals and
    /// its amber: a marker, not a surface, and it earns the jump by only ever being on one
    /// item at a time.
    static let tabSelection = Color(hex: 0xDBE64C)

    static let accent100 = Color(hex: 0xFFF3E4)
    static let accent200 = Color(hex: 0xFFE3BF)
    static let accent300 = Color(hex: 0xFACB8D)
    static let accent400 = Color(hex: 0xE1AD66)
    static let accent500 = Color(hex: 0xC28D41)
    static let accent600 = Color(hex: 0xA06F24)
    static let accent700 = Color(hex: 0x7D5411)
    static let accent800 = Color(hex: 0x5A3B0A)
    static let accent900 = Color(hex: 0x3A270D)

    /// `color-mix(in srgb, #201f1d 16%, transparent)`
    static let divider = text.opacity(0.16)
    /// `color-mix(in srgb, var(--color-neutral-900) 94%, black)` — the ink plate.
    static let ink = Color(hex: 0x2A2829)
    /// Destructive actions — the design's `oklch(0.55 0.21 27)`.
    static let danger = Color(oklch: 0.55, 0.21, 27)
    /// The live-feed dot: `oklch(0.62 0.14 150)`
    static let live = Color(oklch: 0.62, 0.14, 150)

    // MARK: Type
    //
    // San Francisco throughout — Apple's own face, and the one iOS renders best at these
    // sizes. The Classical design system pairs Cormorant Garamond with Lora, and those
    // shipped in 2.0; on a phone they read unevenly, the numerals fight the labels and
    // the small sizes lose legibility. The design's *sizes* are kept, scaled for SF's
    // larger x-height, so the layout is unchanged — only the voice of the type is.

    /// Cormorant runs small for its point size; SF does not. Headings are scaled so a
    /// line that filled its space in the design still fills it here.
    private static let headingScale: CGFloat = 0.86

    static func heading(_ size: CGFloat, semibold: Bool = false) -> Font {
        .system(size: size * headingScale, weight: semibold ? .semibold : .regular)
    }

    /// Interface headings — the small, working titles — take the semibold cut.
    static func headingUI(_ size: CGFloat) -> Font {
        .system(size: size * headingScale, weight: .semibold)
    }

    static func body(_ size: CGFloat, semibold: Bool = false) -> Font {
        system(size, weight: semibold ? .semibold : .regular, style: .body, cap: 1.6)
    }

    static func bodyItalic(_ size: CGFloat) -> Font {
        Font.system(size: scaledSize(size, style: .body, cap: 1.6)).italic()
    }

    /// Cormorant Garamond SemiBold — the design system's serif, in the two roles big
    /// enough to carry it: a national park's name standing alone over its own colour
    /// field, and the title at the head of a screen.
    ///
    /// Nowhere smaller. In a list row or a nav bar the serif thins out and the app gets
    /// back the uneven texture 2.1.1 removed, so those stay on `heading`. Sizes are the
    /// design's own, with no SF scaling — they were drawn in this face.
    /// The masthead weight: Cormorant Garamond at 700, cut from the variable original.
    /// Only the app's own name is set in it — a display serif this heavy stops being a
    /// heading and starts being a logotype.
    static func displayBold(_ size: CGFloat) -> Font {
        scaled("CormorantGaramond-Bold", fallback: .system(size: size, weight: .bold, design: .serif),
               style: .largeTitle, size: size, cap: 1.4)
    }

    static func display(_ size: CGFloat) -> Font {
        scaled("CormorantGaramond-SemiBold",
               fallback: .system(size: size, weight: .semibold, design: .serif),
               style: .largeTitle, size: size, cap: 1.4)
    }

    /// A number that carries a label: a temperature, a countdown, a mileage, a stat cell.
    ///
    /// These were being set in `heading`, which exists to scale Cormorant's sizes onto
    /// SF — so every figure in the app came out at 0.86 of its intended size, in regular
    /// weight, and sat lighter than the label above it. Numbers get their own token:
    /// true size, semibold, and `.tnum()` at the call site so columns hold still.
    static func statValue(_ size: CGFloat) -> Font {
        system(size, weight: .semibold, style: .title2, cap: 1.5)
    }

    /// The name at the head of a row — a campground, a stamp, an alert, a park in a list.
    static func rowTitle(_ size: CGFloat = 17) -> Font {
        system(size, weight: .semibold, style: .headline, cap: 1.6)
    }

    /// Airport codes and other fixed-width runs — SF Mono.
    static func mono(_ size: CGFloat, semibold: Bool = true) -> Font {
        Font.system(size: scaledSize(size, style: .footnote, cap: 1.5),
                    weight: semibold ? .semibold : .regular,
                    design: .monospaced)
    }

    // MARK: Dynamic Type
    //
    // Every size here is the design's, and every size here also grows with the reader's
    // text setting. Fixed points would have been simpler and would have made the app
    // unusable for anyone who has turned text up — so sizes are run through
    // `UIFontMetrics` with a cap, tight enough that a stat row still fits its column and
    // loose enough to matter.

    private static func scaledSize(_ size: CGFloat, style: UIFont.TextStyle, cap: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size).clamped(to: size...(size * cap))
    }

    private static func system(_ size: CGFloat, weight: Font.Weight,
                               style: UIFont.TextStyle, cap: CGFloat) -> Font {
        .system(size: scaledSize(size, style: style, cap: cap), weight: weight)
    }

    /// The serif has no system metrics of its own, so it is scaled by the same rule.
    ///
    /// The face has to be carried through: this used to rebuild the font from a
    /// hard-coded `CormorantGaramond-SemiBold`, which meant `displayBold` asked for the
    /// Bold cut, passed the check that the Bold cut exists, and then drew SemiBold —
    /// including the masthead the weight was cut for.
    private static func scaled(_ name: String, fallback: Font,
                               style: UIFont.TextStyle, size: CGFloat, cap: CGFloat) -> Font {
        guard UIFont(name: name, size: size) != nil else { return fallback }
        return .custom(name, size: scaledSize(size, style: style, cap: cap))
    }

    // MARK: Metrics

    /// The design's page gutter on every screen.
    static let gutter: CGFloat = 20

    /// How round a sheet's corners are.
    ///
    /// The phone's own display corner, so a sheet strikes the same arc as the screen it
    /// sits in rather than a tighter one inside it — at 34 the two curves were visibly
    /// different radii wherever they met. 62pt is what the 17 Pro reports; the only way to
    /// read a device's real corner is `UIScreen._displayCornerRadius`, which is private and
    /// not worth an App Store review over, so it is written down instead. Older phones
    /// curve less (39–55pt), where this errs slightly round rather than slightly square.
    static let sheetCorner: CGFloat = 62

    /// Where a round close control sits so that it and the corner it sits in are drawn
    /// about the same point.
    ///
    /// A circle inset by the page gutter has its centre at (gutter + r) from the corner,
    /// while the corner's own arc is centred at (radius, radius) — so at a 20pt gutter and
    /// a 22pt disc the two curves were struck from points 20pt apart and never looked
    /// concentric. Insetting by `sheetCorner - r` puts both centres on the same point,
    /// whatever size the disc is.
    ///
    /// Held at the gutter, though, because concentricity stops being the thing worth having
    /// once the corner is bigger than the disc can nest inside. At a 62pt corner the formula
    /// asks for 40pt, which sets the disc further in than the words beside it — a close
    /// control floating in from the edge while its own header text sits at the gutter reads
    /// as misaligned, whatever the arcs are doing.
    static func sheetCloseInset(for discSize: CGFloat) -> CGFloat {
        min(sheetCorner - discSize / 2, gutter)
    }
    /// Status-bar clearance the design bakes into each header (`padding-top: 57px`).
    static let headerTop: CGFloat = 14
    /// Breathing room at the end of a scroll on a screen with no bar over it — a pushed
    /// screen. Just the design's trailing margin.
    static let tabBarClearance: CGFloat = 28
    /// The floating bar's own height: two 46pt items' worth of row plus its 5pt padding.
    static let tabBarHeight: CGFloat = 56
    /// What a root screen's scroll has to clear. The system bar used to inset content for
    /// us; ours floats in an overlay and cannot, so the last card is held clear by hand.
    static let rootScrollBottom: CGFloat = tabBarClearance + tabBarHeight + 10
}

// MARK: - Colour conversion

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// OKLCH, as the design writes it: `oklch(L C H)` with L in 0…1 and H in degrees.
    /// Converted through OKLab to linear sRGB and gamma-encoded, so the hue rotations the
    /// design uses for park identities land exactly where they were drawn.
    init(oklch l: Double, _ c: Double, _ h: Double, opacity: Double = 1) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)

        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b

        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        let r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        func encode(_ x: Double) -> Double {
            let v = min(max(x, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }

        self.init(.sRGB, red: encode(r), green: encode(g), blue: encode(bl), opacity: opacity)
    }

    /// Parses the CSS the curated dataset carries verbatim — `oklch(0.46 0.09 168)`,
    /// with an optional `/ alpha`. Anything unparseable falls back to the ink plate
    /// rather than crashing or silently rendering black.
    init(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("oklch(") {
            let inner = s.dropFirst(6).dropLast()
            let parts = inner.split(whereSeparator: { $0 == " " || $0 == "/" })
                .compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
            if parts.count >= 3 {
                self.init(oklch: parts[0], parts[1], parts[2], opacity: parts.count > 3 ? parts[3] : 1)
                return
            }
        }
        if s.hasPrefix("#"), let value = UInt32(s.dropFirst(), radix: 16) {
            self.init(hex: value)
            return
        }
        self = WP.ink
    }
}

// MARK: - Small shared helpers

extension View {
    /// Tabular figures — the design sets `font-feature-settings:'tnum'` on every number.
    func tnum() -> some View { monospacedDigit() }

    /// The design's uppercase kickers: tiny, wide-tracked, accent-coloured.
    func kickerStyle(size: CGFloat = 10, tracking: CGFloat = 1.4, color: Color = WP.accent) -> some View {
        font(WP.body(size))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// The traffic-light rating the design applies to a day's high temperature.
enum WeatherLight {
    case kind, warm, punishing

    init(high: Int) {
        if high >= 95 { self = .punishing }
        else if high >= 84 { self = .warm }
        else { self = .kind }
    }

    var color: Color {
        switch self {
        case .punishing: return Color(oklch: 0.55, 0.19, 27)
        case .warm: return Color(oklch: 0.72, 0.15, 75)
        case .kind: return Color(oklch: 0.60, 0.13, 150)
        }
    }

    var label: String {
        switch self {
        case .punishing: return "Punishing — dawn hiking only"
        case .warm: return "Warm — start early"
        case .kind: return "Kind — hike any hour"
        }
    }
}

/// The dashboard tile ramps, straight from the design's `ramp()`.
enum Ramp: String {
    case ember, brass, sage, dusk, plum, sepia, dust

    var colors: [Color] {
        switch self {
        case .ember: return [Color(oklch: 0.54, 0.19, 28), Color(oklch: 0.76, 0.15, 58), Color(oklch: 0.90, 0.10, 88)]
        case .brass: return [Color(oklch: 0.58, 0.14, 62), Color(oklch: 0.78, 0.13, 76), Color(oklch: 0.92, 0.09, 92)]
        case .sage: return [Color(oklch: 0.50, 0.13, 158), Color(oklch: 0.71, 0.12, 145), Color(oklch: 0.90, 0.09, 128)]
        case .dusk: return [Color(oklch: 0.44, 0.10, 252), Color(oklch: 0.66, 0.09, 236), Color(oklch: 0.88, 0.06, 214)]
        case .plum: return [Color(oklch: 0.42, 0.10, 318), Color(oklch: 0.64, 0.09, 330), Color(oklch: 0.88, 0.06, 340)]
        case .sepia: return [Color(oklch: 0.44, 0.04, 70), Color(oklch: 0.66, 0.04, 78), Color(oklch: 0.88, 0.03, 86)]
        case .dust: return [WP.neutral600, WP.neutral400, WP.neutral300]
        }
    }

    var opacities: [Double] {
        self == .dust ? [0.34, 0.28, 0.22] : [0.62, 0.5, 0.42]
    }
}


private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

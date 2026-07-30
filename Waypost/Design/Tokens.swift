import SwiftUI

/// The Classical design-system tokens, transcribed from `_ds/classical/styles.css`, plus
/// the values the mobile design layers on top of them.
///
/// Everything here is a literal from the design. Where the design writes a colour in
/// OKLCH — every park identity, every traffic light, every dashboard ramp — this file
/// keeps the OKLCH numbers and converts at runtime, so the colour on the phone is the
/// colour in the design rather than a hand-eyed hex approximation.
enum WP {

    // MARK: Palette

    static let bg = Color(hex: 0xF3F2F2)
    static let surface = Color(hex: 0xEAE9E9)
    static let text = Color(hex: 0x201F1D)
    static let accent = Color(hex: 0xB68235)
    static let accent2 = Color(hex: 0xAC803E)
    /// The page behind the device in the design — used for the deepest scrim.
    static let clay = Color(hex: 0xDCD7CF)

    static let neutral100 = Color(hex: 0xF8F4F4)
    static let neutral200 = Color(hex: 0xEAE7E7)
    static let neutral300 = Color(hex: 0xD7D3D3)
    static let neutral400 = Color(hex: 0xBAB6B6)
    static let neutral500 = Color(hex: 0x9B9797)
    static let neutral600 = Color(hex: 0x7D7979)
    static let neutral700 = Color(hex: 0x605D5D)
    static let neutral800 = Color(hex: 0x444141)
    static let neutral900 = Color(hex: 0x2D2B2B)

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
    /// The live-feed dot: `oklch(0.62 0.14 150)`
    static let live = Color(oklch: 0.62, 0.14, 150)

    // MARK: Type
    //
    // The real faces ship with the app: Cormorant Garamond for headings, Lora for body,
    // JetBrains Mono for airport codes. All three are OFL.

    /// Cormorant sets old-style figures by default — 97° comes out as tiny humped
    /// glyphs and 11 reads as two small capital I's. Every heading here can carry a
    /// number, so lining, tabular figures are switched on for the whole face.
    static func heading(_ size: CGFloat, semibold: Bool = false) -> Font {
        Font(FontFeatures.liningTabular(semibold ? "CormorantGaramond-SemiBold" : "CormorantGaramond-Regular", size))
    }

    /// Interface headings take the semibold cut — the design system's note is that
    /// semibold is the ceiling for headings because they need the weight at small sizes.
    static func headingUI(_ size: CGFloat) -> Font {
        Font(FontFeatures.liningTabular("CormorantGaramond-SemiBold", size))
    }

    static func body(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "Lora-SemiBold" : "Lora-Regular", size: size)
    }

    static func bodyItalic(_ size: CGFloat) -> Font {
        .custom("Lora-Italic", size: size)
    }

    static func mono(_ size: CGFloat, semibold: Bool = true) -> Font {
        .custom(semibold ? "JetBrainsMono-SemiBold" : "JetBrainsMono-Regular", size: size)
    }

    // MARK: Metrics

    /// The design's page gutter on every screen.
    static let gutter: CGFloat = 20
    /// Status-bar clearance the design bakes into each header (`padding-top: 57px`).
    static let headerTop: CGFloat = 14
    /// Breathing room at the end of a scroll. The system tab bar insets content itself,
    /// so this is just the design's trailing margin.
    static let tabBarClearance: CGFloat = 28
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
    func kickerStyle(size: CGFloat = 9.5, tracking: CGFloat = 1.6, color: Color = WP.accent) -> some View {
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

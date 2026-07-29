import SwiftUI

/// The Classical design-system tokens, transcribed from the design project's
/// `_ds/classical-…/styles.css`. Values are copied rather than approximated so the
/// phone app and the web app read as the same product.
///
/// The system is a light, parchment-toned one and commits to that look, exactly as the
/// web app does — there is no dark variant upstream to mirror yet.
enum WP {

    // MARK: Colour

    static let bg = Color(hex: 0xF3F2F2)
    static let surface = Color(hex: 0xEAE9E9)
    static let text = Color(hex: 0x201F1D)
    static let accent = Color(hex: 0xB68235)
    static let accent2 = Color(hex: 0xAC803E)

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
    /// The app bar: `color-mix(in srgb, var(--color-neutral-900) 94%, black)`
    static let ink = Color(hex: 0x2A2829)
    /// The live-data dot: `oklch(0.62 0.14 150)`
    static let live = Color(hex: 0x3B8F52)
    /// Destructive affordances (the Clear chip) — `oklch(0.55 0.21 27)`
    static let danger = Color(hex: 0xC0392B)

    // MARK: Type
    //
    // The system pairs Cormorant Garamond (headings) with Lora (body). Neither ships
    // with iOS, and shipping webfont binaries into an app bundle is a licensing
    // question rather than a design one — so the app uses the platform serif (New York)
    // in both roles, which keeps the same voice with none of the download. Swapping in
    // the real faces is a drop-in change here and nowhere else.

    static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // MARK: Space (the 4.6px scale)

    enum Space {
        static let s1: CGFloat = 4.6
        static let s2: CGFloat = 9.2
        static let s3: CGFloat = 13.8
        static let s4: CGFloat = 18.4
        static let s6: CGFloat = 27.6
        static let s8: CGFloat = 36.8
    }

    /// The mobile layout's page gutter.
    static let gutter: CGFloat = 18
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Reusable pieces of the system

/// `.tag` — a pill. The variants match the CSS classes one for one.
struct Tag: View {
    enum Style { case neutral, accent, outline, live }
    var text: String
    var style: Style = .neutral
    var showsLiveDot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showsLiveDot { LiveDot() }
            Text(text)
        }
        .font(WP.body(11))
        .tracking(0.2)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(background)
        .foregroundStyle(foreground)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(style == .outline ? WP.accent : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 999))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var background: Color {
        switch style {
        case .neutral: return WP.neutral100
        case .accent: return WP.accent100
        case .outline: return .clear
        case .live: return WP.accent100
        }
    }

    private var foreground: Color {
        switch style {
        case .neutral: return WP.neutral800
        case .accent, .live: return WP.accent800
        case .outline: return WP.accent
        }
    }
}

/// The pulsing dot that marks a panel fed by a live source.
struct LiveDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(WP.live)
            .frame(width: 7, height: 7)
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// `.card` — a hairline-bordered plate.
struct CardBox<Content: View>: View {
    var borderColor: Color = WP.divider
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WP.Space.s2) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WP.Space.s3)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(borderColor, lineWidth: 1))
    }
}

/// `.card-kicker` — the small accent label above a card title.
struct Kicker: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(WP.body(10))
            .tracking(1.0)
            .foregroundStyle(WP.accent)
    }
}

/// The uppercase section label used down the trip screen.
struct SectionLabel: View {
    var text: String
    var badge: String?
    var live: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text.uppercased())
                .font(WP.body(11))
                .tracking(1.3)
                .foregroundStyle(WP.text.opacity(0.7))
            if let badge {
                Tag(text: badge, style: .neutral, showsLiveDot: live)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A full-width segmented control in the mobile app's pill style. The system
/// `Picker(.segmented)` cannot carry the serif type or the pill radius.
struct WPSegmented<T: Hashable>: View {
    var options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { opt in
                let active = opt.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(WP.body(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(active ? WP.bg : .clear)
                        .foregroundStyle(active ? WP.accent : WP.text)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(active ? WP.accent : .clear, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 999))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(WP.neutral100)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }
}

/// A hairline rule matching `.hr`.
struct Hairline: View {
    var body: some View { Rectangle().fill(WP.divider).frame(height: 1) }
}

extension View {
    /// Tabular figures, matching `font-feature-settings:'tnum'` on every number in the UI.
    func tnum() -> some View { self.monospacedDigit() }
}

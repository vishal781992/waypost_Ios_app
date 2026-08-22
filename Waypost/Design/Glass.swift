import SwiftUI

// MARK: - Liquid glass

/// The glass surfaces the design uses. Each case carries the tint, the border and the
/// inner shine the CSS spells out, so a surface reads the same here as it does there.
///
/// On iOS 26 these render through the system Liquid Glass effect — real refraction and
/// specular response, which no stack of blurs can imitate. Below 26 the same surface is
/// assembled by hand: a material for the blur, the design's tint on top, a hairline
/// border and the two inset highlights that give glass its lit edge.
enum GlassStyle {
    /// Screen headers — `rgba(243,242,242,0.6)`, blur 22, saturate 185%.
    case header
    /// The floating tab bar — `rgba(250,249,248,0.62)`, blur 24, saturate 190%.
    case tabBar
    /// Search fields and chips — `rgba(255,255,255,0.5)`, blur 16.
    case pill
    /// A caption plate sitting on a photograph — `rgba(255,255,255,0.17)`, blur 17.
    case onPhoto
    /// Bottom sheets — `rgba(243,242,242,0.9)`, blur 26.
    case sheet
    /// Every button and every selected tab: ink glass carrying white type. Dark glass
    /// still refracts what is behind it, so a control reads as a solid thing you press
    /// rather than as a hole cut in the page.
    case control
    /// A reading on the page — the weather tiles. The same ink as `control`, let down far
    /// enough that the coloured fill *inside* the glass still reads: at the control's 0.88
    /// a fill is a smear behind a wall rather than something the material is refracting.
    case tile

    var tint: Color {
        switch self {
        case .header: return Color(hex: 0xF3F2F2, opacity: 0.60)
        case .tabBar: return Color(hex: 0xFAF9F8, opacity: 0.62)
        case .pill: return Color.white.opacity(0.50)
        case .onPhoto: return Color.white.opacity(0.17)
        case .sheet: return Color(hex: 0xF3F2F2, opacity: 0.90)
        case .control: return Color(hex: 0x181410, opacity: 0.88)
        case .tile: return Color(hex: 0x181410, opacity: 0.68)
        }
    }

    var border: Color {
        switch self {
        case .onPhoto: return Color.white.opacity(0.42)
        case .sheet: return Color.white.opacity(0.70)
        case .control: return Color.white.opacity(0.20)
        case .tile: return Color.white.opacity(0.22)
        default: return Color.black.opacity(0.07)
        }
    }

    /// The two inset highlights: a bright top-left edge and a softer bottom-right one.
    var shine: (top: Color, bottom: Color) {
        switch self {
        case .onPhoto: return (Color.white.opacity(0.55), Color.white.opacity(0.25))
        case .tabBar: return (Color.white.opacity(0.72), Color.white.opacity(0.42))
        // Dark glass takes a quieter highlight; the bright edge the light surfaces wear
        // would read as a rim of chrome around every button.
        case .control: return (Color.white.opacity(0.34), Color.white.opacity(0.10))
        // Brighter than `control`: a tile is a pane you look *through*, and the lit edge
        // is most of what says so once the tint is this thin.
        case .tile: return (Color.white.opacity(0.52), Color.white.opacity(0.16))
        default: return (Color.white.opacity(0.80), Color.white.opacity(0.40))
        }
    }

    var material: Material {
        switch self {
        case .onPhoto: return .ultraThinMaterial
        case .control, .tile: return .ultraThinMaterial
        case .sheet: return .thickMaterial
        default: return .thinMaterial
        }
    }
}

extension GlassStyle {
    /// True where iOS supplies the real Liquid Glass material, and the drawn depth can
    /// stand back and let it do the lighting.
    ///
    /// The two paths are not the same job. On 26 the system renders genuine refraction and
    /// a specular response that tracks the device — painting a second highlight over that
    /// gives every button two crowns, one of which moves and one of which does not. Below
    /// 26 there is nothing underneath at all, and the drawn depth is the only thing making
    /// a button read as a solid rather than as a tinted hole in the page.
    static var systemMaterial: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

/// The lit edge of a glass surface: a hairline border plus the inset highlights. Drawn on
/// both the iOS 26 path and the fallback, because the system effect does not know about
/// the design's specific edge treatment.
private struct GlassEdge: View {
    var style: GlassStyle
    var radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.stroke(style.border, lineWidth: 0.5)
            shape
                .stroke(
                    LinearGradient(
                        colors: [style.shine.top, .clear, style.shine.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
                .blendMode(.plusLighter)
                .opacity(0.9)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Depth

/// Which way the light says a control is going.
///
/// Every control in the app used to sit at the same height. A search field and the button
/// beside it wore the same material and cast the same shadow, so nothing but the label said
/// which one you press and which one you type into. Depth is what separates them: a control
/// you press stands off the page, and a field you fill sinks into it.
///
/// The light source is above and unmoved. What changes is the surface — so a raised control
/// is lit along its top edge and shaded along its bottom, and a recessed one is exactly the
/// other way round. That inversion is the whole of it.
enum Depth {
    /// Stands off the page: lit along the top edge, shaded along the bottom.
    case raised
    /// Sinks into it: shaded along the top edge, lit along the bottom.
    case recessed
}

/// Three of the four depth layers in one pass.
///
/// A vertical gradient — white at one end, black at the other — lightens the crown, shades
/// the floor, and bends the body between them. Drawing it as one gradient rather than three
/// stacked layers is what keeps this to a single view per control; the fourth layer is the
/// drop shadow underneath, which each control sets itself with `lift` because it depends on
/// whether the control is glass or a solid fill.
///
/// The middle of the gradient is deliberately clear from about 40% to 75% of the height.
/// A label sits centred in that band, so the tint never falls across type — which is what
/// lets this be an overlay on the glass controls, where the material is applied to the
/// content itself and there is no background layer to slip underneath.
private struct PressedDepth: ViewModifier {
    var shape: RoundedRectangle
    var depth: Depth
    /// Scales the whole gradient. Dark glass wants about half: at full strength its lit
    /// edge reads as a rim of chrome around every button.
    var strength: Double

    func body(content: Content) -> some View {
        content.overlay {
            shape.fill(gradient).allowsHitTesting(false)
        }
    }

    private var gradient: LinearGradient {
        let stops: [Gradient.Stop]
        switch depth {
        case .raised:
            stops = [
                .init(color: .white.opacity(0.58 * strength), location: 0),
                .init(color: .white.opacity(0.15 * strength), location: 0.10),
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.05 * strength), location: 0.78),
                .init(color: .black.opacity(0.13 * strength), location: 1)
            ]
        case .recessed:
            stops = [
                .init(color: .black.opacity(0.15 * strength), location: 0),
                .init(color: .black.opacity(0.05 * strength), location: 0.13),
                .init(color: .clear, location: 0.48),
                .init(color: .white.opacity(0.20 * strength), location: 0.86),
                .init(color: .white.opacity(0.52 * strength), location: 1)
            ]
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// Lights a control as raised or recessed. See `Depth`.
    func pressedDepth(_ depth: Depth, radius: CGFloat = 999, strength: Double = 1) -> some View {
        modifier(PressedDepth(
            shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
            depth: depth,
            strength: strength
        ))
    }

    /// The shadow a raised control casts: a tight contact shadow under a soft ambient one.
    ///
    /// One shadow at 8 points reads as a glow around the control rather than as a thing
    /// resting above a page. It is the near shadow — 1.5 points, barely offset — that says
    /// the control has an edge and the page is right behind it.
    func lift(_ on: Bool = true) -> some View {
        shadow(color: on ? Color(hex: 0x181008, opacity: 0.17) : .clear, radius: 8, y: 6)
            .shadow(color: on ? Color(hex: 0x181008, opacity: 0.13) : .clear, radius: 1.5, y: 1)
    }
}

extension View {
    /// A control: ink glass, white type, and the press shadow that lifts it off the page.
    ///
    /// Every button and every selected tab in the app wears this — the home screen is the
    /// one exception, and it keeps the light glass it was designed with.
    func glassControl(radius: CGFloat = 999, shadow: Bool = true) -> some View {
        foregroundStyle(.white)
            .liquidGlass(.control, radius: radius, interactive: true)
            .pressedDepth(.raised, radius: radius,
                          strength: GlassStyle.systemMaterial ? 0.22 : 0.5)
            .lift(shadow)
    }

    /// A control in the brand's lime: the same shape and the same press shadow as
    /// `glassControl`, filled rather than glazed.
    ///
    /// Opaque, for the reason the orange discs are opaque — glass takes its colour partly
    /// from whatever sits behind it, and these controls sit over a photograph on one
    /// screen and the plain page on the next. A brand colour that changes with the
    /// wallpaper is not a brand colour.
    ///
    /// Type is `WP.text`, never white: white on lime is 1.4:1 and unreadable at any size.
    func limeControl(radius: CGFloat = 999, shadow: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return foregroundStyle(WP.text)
            .background {
                shape.fill(WP.lime)
                    .pressedDepth(.raised, radius: radius)
                    .overlay { shape.stroke(Color.black.opacity(0.14), lineWidth: 0.5) }
            }
            .clipShape(shape)
            .contentShape(shape)
            .lift(shadow)
    }

    /// A control in the mark's orange: the same shape and press shadow as `limeControl`,
    /// filled with the colour off the app's own icon. Black type, at 9.9:1.
    func markControl(radius: CGFloat = 999, shadow: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return foregroundStyle(.black)
            .background(WP.mark, in: shape)
            .overlay { shape.stroke(Color.black.opacity(0.12), lineWidth: 0.5) }
            .clipShape(shape)
            .contentShape(shape)
            .shadow(color: shadow ? Color(hex: 0x181008, opacity: 0.22) : .clear, radius: 8, y: 5)
    }

    /// Puts the view on a liquid-glass surface.
    func liquidGlass(_ style: GlassStyle = .pill, radius: CGFloat = 999, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(style: style, radius: radius, interactive: interactive))
    }
}

private struct LiquidGlass: ViewModifier {
    var style: GlassStyle
    var radius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // A full-bleed surface has no rounded edge to catch light, so the lit border
        // reads as a stray rule under the status bar rather than as glass. Headers draw
        // their own hairline at the bottom, which is the only edge that means anything.
        let wantsEdge = radius > 0

        Group {
            if style == .onPhoto {
                content
                    .background(style.tint, in: shape)
                    .overlay { if wantsEdge { GlassEdge(style: style, radius: radius) } }
            } else if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        interactive
                            ? .regular.tint(style.tint).interactive()
                            : .regular.tint(style.tint),
                        in: shape
                    )
                    .overlay { if wantsEdge { GlassEdge(style: style, radius: radius) } }
            } else {
                content
                    .background(style.material, in: shape)
                    .background(style.tint, in: shape)
                    .overlay { if wantsEdge { GlassEdge(style: style, radius: radius) } }
            }
        }
        .modifier(ControlHitArea(shape: shape, active: interactive))
    }
}

extension View {
    /// Makes a whole search pill focus the field inside it.
    ///
    /// A `TextField` is tappable only where its text is, and the pill drawn around it is
    /// not part of the field — so tapping the empty three-quarters of a search bar did
    /// nothing. It is the same fault as the buttons had, in the one control where an empty
    /// target is the *normal* state: an empty search field is mostly empty.
    ///
    /// `simultaneousGesture` rather than `onTapGesture`, so a tap that lands on the text
    /// still reaches the field itself and puts the caret where it was aimed.
    ///
    /// That gesture is not enough on its own, and this is the second time the same fault
    /// has been fixed here. A gesture on the field's *container* only ever fires if the
    /// container is hit-testable, and a container is hit-testable because something drew a
    /// background into it. `glassEffect` draws no such thing — which is the whole of the
    /// note on `ControlHitArea`, where every button in the app went dead outside its own
    /// label on iOS 26. The search pill has the same hole, and `contentShape` did not close
    /// it: on the path where the surface is the system material there is no region for the
    /// shape to describe, so the tap lands on nothing and the gesture never runs.
    ///
    /// So the tap target stops being a property of the container and becomes a view. A
    /// `Color.clear` fills the pill and carries the gesture itself — always hit-testable,
    /// no matter what drew the surface, and competing with nothing.
    ///
    /// It goes in the `background`, deliberately, not an overlay. These fields are not all
    /// bare: the trip builder's origin field carries a clear button and the profile's
    /// carries *Done*, and an overlay would sit above them and eat the taps meant for them.
    /// Behind the content, the field and its buttons keep every tap that is theirs, and
    /// this catches only what would otherwise have hit nothing.
    func searchFieldSurface(radius: CGFloat = 999, focus: FocusState<Bool>.Binding) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let focused = focus.wrappedValue
        // The body is real glass — `.glassEffect` on 26, the material below it — rather
        // than the flat `neutral200` three of these four fields used to wear. The recess
        // is then laid over the top: iOS 26 has no sunken variant of its material, so the
        // direction of the light is still ours to draw, but what it lights is the system's.
        return liquidGlass(.pill, radius: radius)
            .pressedDepth(.recessed, radius: radius)
        // The focus ring is the accent, and it is the only thing on the field that moves.
        // A recessed field has no shadow to brighten and no lift to take away, so without
        // it nothing at all marked the field somebody was actually typing into.
        .overlay {
            shape.stroke(focused ? WP.accent400 : Color.black.opacity(0.12),
                         lineWidth: focused ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        // Moving these fields onto the system material took away the accidental
        // hit-testability the flat `neutral200` capsule gave three of them, which is why
        // the tap target above is a view of its own rather than a shape on the container.
        .background {
            Color.clear
                .contentShape(shape)
                .onTapGesture { focus.wrappedValue = true }
        }
        .contentShape(shape)
        .animation(Motion.panel, value: focused)
        .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = true })
    }
}

/// A control has to answer a tap anywhere on its surface, not only where its label sits.
///
/// The two `.background(…)` branches above give the glass a hit-testable shape as a side
/// effect; `glassEffect` does not. So from iOS 26 every button in the app — which is every
/// view wearing `glassControl` — was tappable only on its own text, and the padding that
/// makes it look like a button was dead. Applied only to `interactive` glass: a header or
/// a panel is a surface, and giving one a hit area would have it swallow taps and scrolls
/// meant for what sits on top of it.
private struct ControlHitArea: ViewModifier {
    var shape: RoundedRectangle
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            content.contentShape(shape)
        } else {
            content
        }
    }
}

/// The tab bar and other clusters of glass want to be one piece of glass, not several —
/// `GlassEffectContainer` is what merges them on iOS 26.
struct GlassCluster<Content: View>: View {
    var spacing: CGFloat = 2
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Colour fields

/// A park's identity, rendered as the design renders it: three blurred organic blobs in
/// the park's own OKLCH triple, a diagonal specular sweep, and a scrim so white type
/// stays legible over the top.
struct BlobField: View {
    var colors: [Color]
    var scrim: Bool = true
    /// A hairline of light along the top edge, as on the design's hero cards.
    var topLight: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                (colors.first ?? WP.accent600)

                ZStack {
                    blob(colors.first ?? WP.accent600, x: 0.16 * w, y: 0.18 * h, w: 0.66 * w, h: 0.92 * h)
                    blob(colors.count > 2 ? colors[2] : WP.accent300, x: 0.88 * w, y: 0.12 * h, w: 0.56 * w, h: 0.86 * h)
                    blob(colors.count > 1 ? colors[1] : WP.accent400, x: 0.52 * w, y: 0.96 * h, w: 0.78 * w, h: 0.86 * h)
                }
                .blur(radius: 24)
                .opacity(0.95)

                // specular sweep — `linear-gradient(115deg, …)`
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.34), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.34),
                        .init(color: .clear, location: 0.52),
                        .init(color: .white.opacity(0.14), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                if scrim {
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x181008, opacity: 0.58), location: 0),
                            .init(color: Color(hex: 0x181008, opacity: 0.22), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .bottom, endPoint: .top
                    )
                }

                if topLight {
                    VStack {
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func blob(_ color: Color, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Ellipse().fill(color).frame(width: w, height: h).position(x: x, y: y)
    }
}

/// The corner ramp behind a dashboard tile — masked so it only lights the bottom-right.
struct RampCorner: View {
    var ramp: Ramp

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(Array(ramp.colors.indices), id: \.self) { index in
                    Ellipse()
                        .fill(ramp.colors[index])
                        .opacity(ramp.opacities[min(index, ramp.opacities.count - 1)])
                        .frame(width: (0.62 - CGFloat(index) * 0.11) * w,
                               height: (1.12 - CGFloat(index) * 0.23) * h)
                        .position(x: (0.92 - CGFloat(index) * 0.18) * w,
                                  y: (1.02 - CGFloat(index) * 0.1) * h)
                }
            }
            .blur(radius: 19)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.45), location: 0.40),
                        .init(color: .clear, location: 0.64),
                    ],
                    startPoint: .bottomTrailing, endPoint: .topLeading
                )
            )
        }
        .allowsHitTesting(false)
    }
}

/// The brass-and-dusk glow the design puts behind its primary buttons.
struct ButtonGlow: View {
    var strong: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(WP.accent500)
                    .frame(width: 0.44 * w, height: 1.68 * h)
                    .position(x: 0.24 * w, y: 0.42 * h)
                Ellipse().fill(Color(oklch: 0.55, 0.10, 250))
                    .frame(width: 0.42 * w, height: 1.58 * h)
                    .position(x: 0.82 * w, y: 0.66 * h)
            }
            .blur(radius: 20)
            .opacity(strong ? 0.85 : 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shapes

/// The stamp's scalloped edge — the design's `starClip(spikes, inner)`.
struct StampShape: Shape {
    var spikes: Int = 26
    /// Inner radius as a percentage of the outer, matching the CSS.
    var inner: CGFloat = 44

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = spikes * 2
        let cx = rect.midX, cy = rect.midY
        let outer = min(rect.width, rect.height) / 2
        let innerR = outer * (inner / 50)
        for i in 0..<count {
            let r = i % 2 == 0 ? outer : innerR
            let a = (.pi * 2 * CGFloat(i)) / CGFloat(count) - .pi / 2
            let p = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Components

/// `.card-kicker` and the design's section kickers.
struct Kicker: View {
    var text: String
    var color: Color = WP.accent
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(WP.body(size))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// A section heading with a rule running to the right and an optional trailing note —
/// the pattern used all down the Today screen.
struct RuledHeading<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title.uppercased())
                .font(WP.body(12))
                .tracking(1.5)
                .foregroundStyle(WP.accent700)
            Rectangle().fill(WP.divider).frame(height: 1)
            trailing
        }
    }
}

extension RuledHeading where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// The design's inset segmented control: a neutral trough, the active option lifted onto
/// the page colour with a hairline and a soft shadow.
struct SegmentedTrough<T: Hashable>: View {
    var options: [(value: T, label: String)]
    @Binding var selection: T
    /// What choosing a given option should feel like.
    ///
    /// Opt-in, and nil for six of the app's seven segmented controls. A haptic on every
    /// segmented tap is noise — it says only that the tap landed, which the pill sliding
    /// across already said. It earns its place where the two options *differ* in a way
    /// worth feeling, which so far is one control: the vehicle.
    var haptic: ((T) -> Void)? = nil

    /// Where the pill lives while it is between segments.
    @Namespace private var trough
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pillID = "segmented.pill"

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    // Only on a change. Re-tapping the segment already showing is not a
                    // choice, and answering it would make the control feel jumpy.
                    if option.value != selection { haptic?(option.value) }
                    withAnimation(reduceMotion ? Motion.segmentReduced : Motion.segment) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(WP.body(13))
                        // Animated rather than swapped, so the word arrives at full ink as
                        // the pill reaches it instead of flicking dark before it gets there.
                        .foregroundStyle(active ? WP.text : WP.text.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .background { if active { pill } }
                        // Every segment, not only the unselected ones. The pill used to
                        // bring a hit-testable background with it; it is drawn behind the
                        // label now, so the target is stated here for all of them.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule().fill(WP.neutral200)
                .pressedDepth(.recessed, strength: 0.85)
                .overlay { Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.5) }
        }
    }

    /// One pill, moved — not one pill per segment, appearing and disappearing in place.
    ///
    /// It was the latter, which is why the selection jumped: each segment drew its own
    /// background when it became active, so there was nothing for SwiftUI to carry from
    /// the old position to the new one. `matchedGeometryEffect` gives the two appearances
    /// the same identity, and the frame between them is interpolated — which is the whole
    /// of the slide.
    ///
    /// Under Reduce Motion it goes back to appearing where it belongs. Sliding a pill the
    /// width of the screen is exactly the movement that setting exists to stop, and making
    /// the slide merely *fast* would be worse than not sliding at all.
    @ViewBuilder
    private var pill: some View {
        let face = Capsule()
            .fill(WP.lime)
            .pressedDepth(.raised)
            .overlay { Capsule().stroke(Color.black.opacity(0.14), lineWidth: 0.5) }
            // Shorter and tighter than a free-standing button's: the pill is lifting three
            // points out of its own trough, not off the page.
            .shadow(color: Color(hex: 0x181008, opacity: 0.20), radius: 3, y: 2)

        if reduceMotion {
            face.transition(.opacity)
        } else {
            face.matchedGeometryEffect(id: Self.pillID, in: trough)
        }
    }
}

/// A horizontally scrolling rail of segment pills — the park screen's five sections.
struct SegmentRail<T: Hashable>: View {
    var options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let active = option.value == selection
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                    } label: {
                        Text(option.label)
                            .font(WP.body(12.5))
                            .padding(.horizontal, 15)
                            .frame(minHeight: 34)
                            .modifier(SelectedControl(active: active))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, WP.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A rail of sections where only the one being read says its name.
///
/// Six labels do not fit across a phone: the old rail scrolled, so two of them sat
/// off-screen with nothing to say they existed, and "AI Overview" stood next to
/// "Overview" — two labels a glance cannot separate. A glyph each and a word for the
/// current one fits all six with room to spare, and the sparkle carries the "AI" that the
/// two near-identical words could not.
///
/// `compact` is the pinned form: the page header names the section, so the rail drops its
/// pill and shows six discs of equal weight.
struct SegmentDiscRail<T: Hashable>: View {
    var options: [(value: T, label: String, short: String, icon: String)]
    @Binding var selection: T
    /// The page-header form: every section a disc of equal weight, spread across the
    /// width, because the header itself names the one being read.
    var compact: Bool = false
    /// Drawn on ink glass rather than on the page. `WP.text` at 16% is a hairline on
    /// off-white and nothing at all on near-black, so the unselected discs need the
    /// other end of the scale — and their glyphs need to be the light, not the dark.
    var onInk: Bool = false

    private var glyph: Color { onInk ? WP.onInk : WP.text }
    private var ring: Color { onInk ? Color.white.opacity(0.3) : WP.text.opacity(0.16) }

    /// The selected fill is one shape that moves, not six that appear and disappear —
    /// the same `matchedGeometryEffect` the app's own tab bar uses for its pill, so the
    /// two bars behave alike now that this one is welded to the foot of the screen.
    @Namespace private var pill

    /// 44 points, the smallest thing a finger should be asked to hit — and what every
    /// other round control in this app already is.
    private var disc: CGFloat { compact ? 42 : 44 }

    var body: some View {
        // Both forms fill the width, by different means. Compact gives every disc an equal
        // share of it, because they are all the same size. In-flow one of them is a pill
        // with a word in it and the rest are discs, so equal shares would centre each item
        // in a column of its own and read as ragged; equal *gaps* is what looks uniform.
        // Six points was a fixed gap, which left the row short of the right margin by
        // however much the selected word happened not to be.
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                // Two points rather than six: each disc now carries three points of
                // transparent padding a side, which is hit area rather than air. The gap
                // you see between two discs is unchanged; the dead ground between them
                // is gone.
                if !compact, index > 0 { Spacer(minLength: 2) }
                let active = option.value == selection
                Button { selection = option.value } label: {
                    if active, !compact {
                        HStack(spacing: 7) {
                            Image(systemName: option.icon)
                                .font(.system(size: 15, weight: .semibold))
                            Text(option.short).font(WP.body(14)).lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(height: disc)
                        .background {
                            Capsule()
                                .fill(WP.mark)
                                .matchedGeometryEffect(id: "rail-selection", in: pill)
                        }
                        .overlay { Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5) }
                    } else {
                        Image(systemName: option.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(active ? .black : glyph)
                            .frame(width: disc, height: disc)
                            .background {
                                if active {
                                    Circle().fill(WP.mark)
                                        .matchedGeometryEffect(id: "rail-selection", in: pill)
                                        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                                } else {
                                    Circle().stroke(ring, lineWidth: onInk ? 1 : 0.5)
                                }
                            }
                    }
                }
                .buttonStyle(PressStyle(scale: 0.92))
                // The disc was tappable on the glyph and nowhere else.
                //
                // A `Button` gets its hit area from what its label actually draws, and
                // from iOS 26 a `glassEffect` surface underneath contributes none — the
                // same fault `ControlHitArea` fixes for every other control in the app,
                // which this rail predates. So the ring was decoration, the middle of the
                // disc was a hole, and a tap that missed the 17pt glyph did nothing. An
                // explicit content shape over the padded frame makes the whole disc, and
                // half the gap either side of it, the button.
                .padding(.horizontal, compact ? 0 : 3)
                .padding(.vertical, 2)
                .frame(maxWidth: compact ? .infinity : nil)
                .contentShape(Rectangle())
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        // The word inside the selected pill arrives and leaves on its own — the fill is
        // travelling, and a label that stretched with it would read as the text being
        // dragged along the bar.
        .animation(Motion.panel, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The design's primary action: ink plate, brass-and-dusk glow bleeding through a frosted
/// pane. Used for Compose, Share, Understood.
struct GlowButton: View {
    var title: String
    var filled: Bool = true
    var strongGlow: Bool = false
    var minHeight: CGFloat = 48
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WP.headingUI(filled ? 17 : 15))
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .limeControl()
        }
        .buttonStyle(PressStyle())
    }
}

/// `style-active="transform:scale(0.96)"` — every tappable surface in the design responds.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// A thin progress track — pack downloads, the passport bar, the composing step.
struct ProgressTrack: View {
    var fraction: Double
    var tint: Color = WP.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WP.neutral200)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    .animation(.easeOut(duration: 0.26), value: fraction)
            }
            .pressedDepth(.recessed, strength: 0.8)
        }
        .frame(height: height)
    }
}

/// The iOS switch, in the design's accent.
struct WPSwitch: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? WP.accent : WP.neutral300)
            .frame(width: 40, height: 24)
            .pressedDepth(.recessed, strength: 0.9)
            .overlay { Capsule().stroke(Color.black.opacity(0.16), lineWidth: 0.5) }
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .pressedDepth(.raised, strength: 0.7)
                    .shadow(color: Color(hex: 0x181008, opacity: 0.30), radius: 2, y: 1.5)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.2), value: isOn)
    }
}

/// The hairline the design draws between rows.
struct Hairline: View {
    var body: some View { Rectangle().fill(WP.divider).frame(height: 1) }
}

/// A row that fills to the trailing edge and carries a hairline underneath.
struct DividedRow<Content: View>: View {
    var vertical: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, vertical)
                // Layout is not hit-testing. `frame` and `padding` make the row look full
                // width, but a `Button` wrapping it answered only where the glyphs actually
                // are — the vertical padding, the gap before a trailing chevron and the
                // whole `Spacer` were dead. Tapping such a row two or three times before it
                // works is not the app being slow; it is the second tap landing on a letter.
                .contentShape(Rectangle())
            Hairline()
        }
    }
}

/// The pill the design floats above the tab bar when something happens.
struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(WP.body(12.5))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(WP.ink, in: Capsule())
            .foregroundStyle(WP.onInk)
            .shadow(color: WP.neutral900.opacity(0.22), radius: 16, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}


/// A segment or chip in its two states: ink glass when it is the one you chose, plain
/// type when it is not. Kept in one place so every tab in the app agrees on what
/// "selected" looks like.
/// A filter chip: the mark's orange when it is the one being filtered by.
struct SelectedChip: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            content.markControl(shadow: false)
        } else {
            content
                .foregroundStyle(WP.text.opacity(0.62))
                .background {
                    Capsule().fill(Color.white.opacity(0.55))
                        .pressedDepth(.raised, strength: 0.42)
                        .overlay { Capsule().stroke(Color.black.opacity(0.09), lineWidth: 0.5) }
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
    }
}

struct SelectedControl: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            // A shorter, tighter shadow than a free-standing button's: the segment is
            // lifting three points out of its own trough, not off the page.
            content.limeControl(shadow: false)
                .shadow(color: Color(hex: 0x181008, opacity: 0.20), radius: 3, y: 2)
        } else {
            // The active branch gets a hit-testable background from `glassControl`. Without
            // one here an *unselected* segment was tappable only on its letters — and an
            // unselected segment is the only kind anyone ever taps.
            content
                .foregroundStyle(WP.text.opacity(0.62))
                .contentShape(Capsule())
        }
    }
}


/// The round glass control the home screen wears: 52 points of light glass with a lit
/// crown and a soft shadow under it.
///
/// It exists as one component because it appears in two places — the `+` on the home
/// screen and the `×` that closes the search it opens — and a pair of controls that sit
/// at opposite ends of the same gesture should be the same size and the same material.
/// A word where a `GlassDisc` would be, in the same orange.
///
/// The Today header carried a "+" that opened a park search. A plus means *make a thing* —
/// it means exactly that on the Trips header — and what it actually opened was a catalogue
/// to read. A labelled control can say so.
struct MarkPill: View {
    var title: String
    var height: CGFloat = 48
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WP.headingUI(16))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(height: height)
                // Opaque, for the same reason the discs are: glass takes its colour from
                // whatever sits behind it, and the Today header sits over a different park
                // photograph every day. The crown and the edge keep the glass reading.
                .background(WP.mark, in: Capsule())
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: height * 0.42)
                        .padding(.horizontal, height * 0.24)
                        .padding(.top, 3)
                        .allowsHitTesting(false)
                }
                .overlay { Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.5) }
                .clipShape(Capsule())
                .shadow(color: Color(hex: 0x181008, opacity: 0.16), radius: 8, y: 5)
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }
}

/// Back, floating on ink glass over a full-bleed hero — the only chrome above the fold.
///
/// **This is the one back control.** The park screen and the trip screen both open on a
/// full-bleed hero with this floating over it, and when each screen owned its own copy they
/// drifted immediately: one sat six points under the status bar and the other a whole status
/// bar lower, because one of them added the inset by hand to a view that was already inside
/// the safe area.
///
/// So the placement lives here too, not at the call site. A screen adds this to a
/// `ZStack(alignment: .topLeading)` and adds nothing else — no padding, no inset. The
/// `ZStack` must sit inside the safe area even where the scroll view under it does not.
struct FloatingBack: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                Text(label).font(WP.body(18))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 17)
            .frame(minHeight: 44)
            .glassControl()
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .padding(.leading, WP.gutter)
        .padding(.top, 6)
    }
}

struct GlassDisc: View {
    var icon: String
    var size: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.365, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                // The mark's orange, laid solid rather than tinted through the glass: glass
                // takes its colour partly from whatever is behind it, and this control sits
                // over a photograph on one screen and a plain page on the next. A brand
                // colour that changes with the wallpaper is not a brand colour.
                .background(Circle().fill(WP.mark))
                .overlay(alignment: .top) {
                    // The lit crown the design puts on its round glass controls. Softer
                    // than it was on the glass, which had nothing underneath to bleach.
                    Ellipse()
                        .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.77, height: size * 0.44)
                        .padding(.top, size * 0.058)
                        .allowsHitTesting(false)
                }
                .overlay {
                    // Keeps its edge against a pale header, where the orange alone is not
                    // dark enough to draw its own outline.
                    Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                }
                .clipShape(Circle())
                .shadow(color: Color(hex: 0x181008, opacity: 0.16), radius: 8, y: 5)
        }
        .buttonStyle(PressStyle(scale: 0.94))
    }
}

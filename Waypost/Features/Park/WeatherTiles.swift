import SwiftUI

// MARK: - How a reading is drawn

/// The treatment a tile uses to draw its number.
///
/// The choice follows the *nature* of the reading rather than the metric: a level fills
/// bottom-up, an index fills along its own scale, a speed swings a dial, a span of time
/// draws a band. Two readings of the same nature look alike on purpose — that is what
/// makes five tiles read as one instrument instead of five unrelated charts.
enum TileFill {
    /// A level inside a band — the day's high against the range a hiking day falls in.
    case mercury(Double, Color)
    /// A position on a fixed scale, drawn in the scale's own colours. The gradient is laid
    /// across the *whole* scale and then cut at the value, so the colour at the cut is the
    /// severity: a UV 3 day stays green where a UV 11 day runs to violet.
    case scale(Double, stops: [Gradient.Stop], marks: [Double])
    /// Anything wet.
    case wave(Double, Color)
    /// A speed, with the gust marked on the same track.
    case dial(Double, gust: Double?, Color)
    /// How much of the day's light has been spent. Nil on a day that is not today —
    /// there is no "so far" to draw, so only the trough is laid.
    case band(Double?, Color)
    /// A park with no forecast yet. The tile keeps its shape and says nothing.
    case empty
}

// MARK: - Slab

/// The weather panel: six glass tiles, laid straight on the page and filling it.
///
/// No plate under them. Ink glass is what every other control in this app is made of, so
/// six of them on the page read as part of the same product — and a container around a
/// group that is already a rectangle only draws a second border around the first.
///
/// The temperature takes the largest tile because it is the one number most people came
/// for; sunset takes the width at the foot because its band is the day's own progress.
struct WeatherSlab: View {
    var tiles: [WeatherTileModel]
    @Binding var selected: String?

    private let gap: CGFloat = 10

    /// A `Button`, not an `onTapGesture`. The park screen carries a screen-wide drag for
    /// turning between its sections, and a bare tap gesture on a subview loses to it — the
    /// tiles looked tappable and did nothing. Every other control in this app is a button
    /// for the same reason.
    private func tile(_ id: String, height: CGFloat) -> some View {
        let model = tiles.first { $0.id == id }
        return Button {
            withAnimation(.snappy(duration: 0.26)) {
                selected = selected == id ? nil : id
            }
            Haptics.tap()
        } label: {
            WeatherTile(
                model: model ?? .placeholder(id),
                selected: selected == id,
                dimmed: selected != nil && selected != id
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    var body: some View {
        GeometryReader { geo in
            // Three bands, split by ratio rather than by fixed points, so the panel fills
            // the page on an SE and on a Pro Max without a second layout.
            let free = geo.size.height - gap * 2
            let top = free * 0.47, middle = free * 0.28, foot = free * 0.25

            GlassCluster(spacing: gap) {
                VStack(spacing: gap) {
                    HStack(alignment: .top, spacing: gap) {
                        tile("temp", height: top)
                        VStack(spacing: gap) {
                            tile("uv", height: (top - gap) / 2)
                            tile("humidity", height: (top - gap) / 2)
                        }
                    }
                    HStack(spacing: gap) {
                        tile("wind", height: middle)
                        tile("rain", height: middle)
                    }
                    // Sunset runs the width at the foot, where its band reads as the day's
                    // own progress rather than as one tile's decoration.
                    tile("sun", height: foot)
                }
            }
        }
    }
}

// MARK: - One tile

struct WeatherTileModel: Identifiable {
    var id: String
    var value: String
    var unit: String = ""
    var label: String
    /// The line that appears when the tile is tapped. Kept to what the services actually
    /// published — a tile that invents a sentence to have something to reveal is worse
    /// than one that reveals nothing.
    var detail: String?
    var foot: String?
    var fill: TileFill

    static func placeholder(_ id: String) -> WeatherTileModel {
        WeatherTileModel(id: id, value: "—", label: "", fill: .empty)
    }
}

struct WeatherTile: View {
    var model: WeatherTileModel
    var selected: Bool
    var dimmed: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    private var isBanded: Bool {
        if case .band = model.fill { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            fill
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(model.value)
                        .font(WP.statValue(28))
                        .tnum()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !model.unit.isEmpty {
                        Text(model.unit).font(WP.body(14, semibold: true)).opacity(0.78)
                    }
                }
                Text(model.label)
                    .font(WP.body(11.5))
                    .opacity(0.84)
                    .padding(.top, 5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if selected, let detail = model.detail {
                    Text(detail)
                        .font(WP.body(10.5))
                        .opacity(0.82)
                        .lineSpacing(1.5)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

                if let foot = model.foot, !selected {
                    Text(foot).font(WP.body(10.5)).opacity(0.72).tnum()
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 14)
            // The daylight band is welded to the bottom edge, so type in that tile clears
            // it rather than sitting in it.
            .padding(.bottom, isBanded ? 33 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(WP.onInk)
        // White type over a field that changes colour with every park, and again with
        // whatever the fill puts behind it. The shadow is what keeps a label legible
        // where a pale fill meets a pale blob.
        .shadow(color: Color(hex: 0x120E0A, opacity: 0.35), radius: 3, y: 1)
        .clipShape(shape)
        // The step back is drawn *inside* the tile, as a veil in the page's own colour.
        // `.opacity` on the tile itself did nothing: the glass container composites the
        // tiles into one sheet and the modifier never reached the material.
        .overlay {
            shape.fill(WP.bg).opacity(dimmed ? 0.55 : 0)
        }
        .liquidGlass(.tile, radius: 22, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.label), \(model.value)\(model.unit)")
        .accessibilityHint(model.detail == nil ? "" : "Double tap for detail")
    }

    @ViewBuilder private var fill: some View {
        switch model.fill {
        case .mercury(let level, let tint):
            MercuryFill(level: level, tint: tint)
        case .scale(let level, let stops, let marks):
            ScaleFill(level: level, stops: stops, marks: marks)
        case .wave(let level, let tint):
            WaveFill(level: level, tint: tint)
        case .dial(let level, let gust, let tint):
            DialGauge(level: level, gust: gust, tint: tint)
        case .band(let level, let tint):
            DaylightBand(level: level, tint: tint)
        case .empty:
            Color.clear
        }
    }
}

// MARK: - Fills

/// A level rising up the tile. Translucent on purpose: an opaque fill inside glass stops
/// the material refracting and the tile goes back to being a card.
private struct MercuryFill: View {
    var level: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [tint.opacity(0.60), tint.opacity(0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: geo.size.height * level.clamped01)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// The scale drawn at full width and then cut at the value.
///
/// `clipped()` is what does the cutting: without it the gradient ignores the outer frame
/// and paints the whole tile, and the reading disappears.
private struct ScaleFill: View {
    var level: Double
    var stops: [Gradient.Stop]
    var marks: [Double]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .opacity(0.74)
                    .frame(width: geo.size.width)
                    .frame(width: geo.size.width * level.clamped01, alignment: .leading)
                    .clipped()

                // The thresholds, so the scale reads without a legend under it.
                ForEach(marks, id: \.self) { mark in
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 1)
                        .offset(x: geo.size.width * mark.clamped01)
                }
            }
        }
    }
}

/// Water, moving. Frozen flat when the phone asks for reduced motion — a panel that
/// animates forever is exactly what that setting exists to stop.
private struct WaveFill: View {
    var level: Double
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Canvas { ctx, size in draw(&ctx, size, phase: 0) }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                Canvas { ctx, size in
                    draw(&ctx, size, phase: timeline.date.timeIntervalSinceReferenceDate * 0.9)
                }
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, phase: Double) {
        // A dry day is dry. At zero the crest of the wave still rode above the bottom edge
        // and left a teal hairline across the tile, which read as "a little rain".
        guard level > 0.01 else { return }
        let top = size.height * (1 - level.clamped01)
        ctx.fill(wave(size, top: top + 4, phase: phase + 1.9, amplitude: 3),
                 with: .color(tint.opacity(0.36)))
        ctx.fill(wave(size, top: top, phase: phase, amplitude: 3.6),
                 with: .color(tint.opacity(0.78)))
    }

    private func wave(_ size: CGSize, top: CGFloat, phase: Double, amplitude: CGFloat) -> Path {
        var path = Path()
        // A loop bounded by a width it does not check is a loop that runs forever if the
        // width is ever infinite, appending to a path until the app is killed. A `Canvas`
        // takes whatever size layout hands it, and an unbounded proposal reaching one is
        // not something this view can rule out from in here — so it is ruled out here.
        guard size.width.isFinite, size.height.isFinite, size.width > 0 else { return path }

        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: top))
        var x: CGFloat = 0
        while x <= size.width {
            path.addLine(to: CGPoint(x: x, y: top + sin(Double(x) / 30 + phase) * amplitude))
            x += 3
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// A three-quarter dial in the bottom corner, with the gust as a tick on the same track —
/// sustained and gust are the same measurement, so they belong on one scale.
private struct DialGauge: View {
    var level: Double
    var gust: Double?
    var tint: Color

    private let sweep: CGFloat = 0.75

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.white.opacity(0.26), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Circle()
                .trim(from: 0, to: sweep * level.clamped01)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            if let gust {
                Circle()
                    .trim(from: max(0, sweep * gust.clamped01 - 0.006),
                          to: min(sweep, sweep * gust.clamped01 + 0.006))
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 6))
            }
        }
        .rotationEffect(.degrees(135))
        .frame(width: 46, height: 46)
        .padding(.trailing, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

/// The daylight already spent, as a band welded to the bottom edge of the tile. The
/// tile's corner radius clips its ends, so it reads as part of the tile rather than a
/// rule laid across it.
private struct DaylightBand: View {
    var level: Double?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.18))
                if let level {
                    Rectangle()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * level.clamped01)
                }
            }
            .frame(height: 15)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Scales

/// The scales the tiles are read against, in one place so the panel and anything that
/// explains it cannot drift apart.
enum WeatherScale {
    /// Not a record range — parks do not publish theirs — but the span a hiking day
    /// actually falls in, so the mercury moves meaningfully between a cold morning and a
    /// dangerous afternoon.
    static let temperature: ClosedRange<Double> = 20...105
    /// The UV index tops out at 11+, and 40 mph is where a gust stops being weather and
    /// starts being a reason to turn round.
    static let uvCeiling: Double = 11
    static let windCeiling: Double = 40

    static func fraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// Green through violet, pinned to the index itself: 0 green, 3 yellow, 6 orange,
    /// 8 red, 11 violet — the wording the forecast services use, in colour.
    static let uvStops: [Gradient.Stop] = [
        .init(color: Color(oklch: 0.60, 0.13, 150), location: 0),
        .init(color: Color(oklch: 0.80, 0.13, 100), location: 3 / 11),
        .init(color: Color(oklch: 0.70, 0.15, 62), location: 6 / 11),
        .init(color: Color(oklch: 0.55, 0.18, 28), location: 8 / 11),
        .init(color: Color(oklch: 0.52, 0.15, 320), location: 1),
    ]
    static let uvMarks: [Double] = [3 / 11, 6 / 11]

    /// Water. The palette had no blue in it — every other colour in this app is earth,
    /// and humidity is the one reading that is not.
    static let water = Color(oklch: 0.55, 0.08, 225)
}

// MARK: - Clock

/// Reading the times the weather services publish — `6:19 am`, `8:37 pm` — back into
/// minutes, so the panel can work out how much of the day's light is left.
enum WeatherClock {
    static func minutes(_ text: String?) -> Int? {
        guard let text else { return nil }
        let lower = text.lowercased()
        let isPM = lower.contains("pm")
        let isAM = lower.contains("am")
        guard let clock = lower.split(whereSeparator: { !"0123456789:".contains($0) }).first else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count == 2, var hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        if isPM, hour != 12 { hour += 12 }
        if isAM, hour == 12 { hour = 0 }
        return hour * 60 + minute
    }

    /// `872` becomes `14h 32m`, and a round hour drops the minutes.
    static func span(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func minutesIntoToday(_ date: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}

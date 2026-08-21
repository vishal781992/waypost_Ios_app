import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// MARK: - Haptics

/// The design leans on haptics — "the phone taps back" when a stamp lands or an item is
/// ticked. This is the one place that fires them.
///
/// `tap` and `success` are the stock generators, which is all most of the app needs: a
/// confirmation does not want a voice of its own. `friction` and `smooth` are Core Haptics
/// patterns, because the two of them have to be told apart by feel alone, and the stock
/// impact styles are five weights of the same knock — not five textures.
@MainActor
enum Haptics {
    /// Why anything last failed to fire. Nil when nothing has.
    ///
    /// Haptics are the one part of the interface that cannot be seen, so a silent failure
    /// here is indistinguishable from a device with haptics switched off — which is exactly
    /// how this went unnoticed. `try?` everywhere is what the rest of the app calls
    /// swallowing a failure, and the rule there is the rule here.
    private(set) static var lastFailure: String?

    static func tap() {
        #if canImport(UIKit)
        Generator.light.prepare()
        Generator.light.impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        Generator.notice.prepare()
        Generator.notice.notificationOccurred(.success)
        #endif
    }

    /// Notes why a pattern did not play. See `lastFailure`.
    static func record(_ error: Error) {
        lastFailure = String(String(describing: error).prefix(160))
    }

    /// Which kind of car, in the hand.
    ///
    /// The two options on that control are a choice between a thing full of moving parts
    /// and a thing with almost none, and the haptics say which is which before the label is
    /// read. It is the one place in the app where a haptic carries meaning rather than
    /// simply confirming that a tap landed.
    static func vehicle(isElectric: Bool) {
        if isElectric { smooth() } else { friction() }
    }

    /// Combustion: rough, mechanical, a thing that turns over.
    ///
    /// Six transients about twenty milliseconds apart, sharp, with the intensity wandering
    /// between them. The wander is what makes it a texture rather than six taps — an
    /// evenly-spaced, evenly-weighted burst reads as a beep, and a ragged one reads as a
    /// rasp. It is deliberately the less pleasant of the two.
    static func friction() {
        #if canImport(CoreHaptics)
        if HapticEngine.shared.supported {
            let weights: [Float] = [0.72, 1.0, 0.58, 0.94, 0.5, 0.82]
            HapticEngine.shared.play(weights.enumerated().map { index, weight in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: weight),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                    ],
                    relativeTime: TimeInterval(index) * 0.021
                )
            })
            return
        }
        #endif
        #if canImport(UIKit)
        // No Core Haptics, or no Taptic Engine behind it. `.rigid` is the hardest of the
        // stock impacts and the nearest the generators get to a mechanical knock.
        Generator.rigid.prepare()
        Generator.rigid.impactOccurred()
        #endif
    }

    /// Electric: one smooth swell, quiet, gone before it has been thought about.
    ///
    /// A single continuous event, low sharpness, shaped by an intensity curve so it rises
    /// and falls away rather than starting and stopping. A continuous event with square
    /// edges buzzes; the curve is what makes it a breath.
    static func smooth() {
        #if canImport(CoreHaptics)
        if HapticEngine.shared.supported {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ],
                relativeTime: 0,
                duration: 0.3
            )
            let swell = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 0),
                    .init(relativeTime: 0.1, value: 1),
                    .init(relativeTime: 0.19, value: 0.72),
                    .init(relativeTime: 0.3, value: 0)
                ],
                relativeTime: 0
            )
            HapticEngine.shared.play([event], curves: [swell])
            return
        }
        #endif
        #if canImport(UIKit)
        Generator.soft.prepare()
        Generator.soft.impactOccurred()
        #endif
    }
}

#if canImport(UIKit)
/// The stock generators, held rather than made fresh each time.
///
/// `UIFeedbackGenerator` is documented as a thing you keep: `prepare()` warms the Taptic
/// Engine and the hardware stays ready for a second or so, and a generator built and fired
/// in the same statement usually misses because nothing warmed it. Held here, prepared at
/// the call, they fire when they are asked to.
@MainActor
private enum Generator {
    static let light = UIImpactFeedbackGenerator(style: .light)
    static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    static let soft = UIImpactFeedbackGenerator(style: .soft)
    static let notice = UINotificationFeedbackGenerator()
}
#endif

#if canImport(CoreHaptics)
/// One Core Haptics engine, held for the life of the app.
///
/// Starting an engine costs tens of milliseconds — longer than the gap between a finger
/// landing and the pattern that is meant to answer it — so it starts once and stays up.
/// The two handlers are not optional politeness: the system stops the engine when the app
/// backgrounds and resets it if the haptic server restarts, and an engine in either state
/// plays nothing while reporting no error at all.
@MainActor
private final class HapticEngine {
    static let shared = HapticEngine()

    /// False wherever there is no Taptic Engine to drive: every iPad, and the Simulator,
    /// which plays no haptics at all. Both fall back to the stock generators, which on the
    /// Simulator also do nothing — these patterns can only be judged on a real phone.
    let supported: Bool

    private var engine: CHHapticEngine?

    /// The player that is playing.
    ///
    /// Core Haptics does not hold onto a player for you. `makePlayer` hands one back, and
    /// if the only reference to it is a local it is released the moment the function
    /// returns — which is long before a 300ms swell has finished, and in practice before a
    /// pattern is heard at all. Holding it is not tidiness; it is the difference between
    /// the pattern playing and nothing happening.
    private var player: CHHapticPatternPlayer?

    private init() {
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supported else { return }
        do {
            let engine = try CHHapticEngine()
            self.engine = engine
            // Haptics only. Left false, the engine opens an audio session it never uses,
            // and can fail to start on a device where something else already owns one.
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.start() }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.start() }
            }
            start()
        } catch {
            Haptics.record(error)
        }
    }

    private func start() {
        do { try engine?.start() } catch { Haptics.record(error) }
    }

    func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard let engine else { return }
        // `isAutoShutdownEnabled` means the engine may have shut itself down since the last
        // pattern. Starting one that is already running is a no-op, so this costs nothing.
        start()
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            // Held for the life of the pattern. A second tap replaces it, which stops the
            // first — the right answer, since the second tap is the one being answered.
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Haptics.record(error)
        }
    }
}
#endif

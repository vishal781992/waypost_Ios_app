import CoreMotion
import SwiftUI
import UIKit

/// How the phone is being held, as two numbers between -1 and 1.
///
/// Device motion needs no permission and no usage string — that is `CMPedometer` and
/// `CMMotionActivityManager`, which this does not touch. The gyroscope and the
/// accelerometer are simply there.
@MainActor
@Observable
final class DeviceTilt {
    static let shared = DeviceTilt()

    /// Turned left or right, and tipped away or towards. Clamped and smoothed; zero when
    /// nothing is watching, or when somebody has asked for less motion.
    private(set) var roll: Double = 0
    private(set) var pitch: Double = 0

    /// How far the phone must turn to reach the ends. About thirty-four degrees, which is
    /// as far as a wrist goes without the screen becoming hard to read.
    private static let span = 0.6

    /// How much of each reading is kept. Raw attitude is jittery enough that a card driven
    /// straight off it shivers while the phone is still.
    private static let smoothing = 0.82

    private let motion = CMMotionManager()
    /// Where the phone was when watching began, so the card is flat in whatever position
    /// it is actually being held rather than flat only when laid on a table.
    private var origin: (roll: Double, pitch: Double)?
    /// One manager, however many cards ask for it.
    private var watchers = 0

    private init() {}

    var isAvailable: Bool {
        motion.isDeviceMotionAvailable && !UIAccessibility.isReduceMotionEnabled
    }

    func begin() {
        watchers += 1
        guard watchers == 1, isAvailable else { return }

        origin = nil
        motion.deviceMotionUpdateInterval = 1.0 / 40
        motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let attitude = motion.attitude
            let base = origin ?? (attitude.roll, attitude.pitch)
            if origin == nil { origin = base }

            let r = Self.clamp((attitude.roll - base.roll) / Self.span)
            let p = Self.clamp((attitude.pitch - base.pitch) / Self.span)
            roll = roll * Self.smoothing + r * (1 - Self.smoothing)
            pitch = pitch * Self.smoothing + p * (1 - Self.smoothing)
        }
    }

    func end() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        motion.stopDeviceMotionUpdates()
        origin = nil
        withAnimation(.easeOut(duration: 0.25)) {
            roll = 0
            pitch = 0
        }
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(-1, value)) }
}

extension View {
    /// Watches the phone's attitude for as long as this view is on screen.
    func readsTilt() -> some View {
        onAppear { DeviceTilt.shared.begin() }
            .onDisappear { DeviceTilt.shared.end() }
    }
}

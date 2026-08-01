import Foundation

/// One door to Nominatim, with a queue behind it.
///
/// Nominatim's usage policy is one request a second from one client, and it enforces it:
/// two connections opened at the same moment get refused rather than answered. The app
/// has two callers — the suggestions under the search field and the search itself — and
/// left alone they fire together on the same keystroke, which is exactly the pattern that
/// gets blocked. Both go through here instead: one at a time, spaced, in the order asked.
actor NominatimGate {
    static let shared = NominatimGate()

    /// A courteous gap. The policy says one per second; this leaves a little room.
    private let spacing: Duration = .milliseconds(1_100)
    private var lastFinished: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        if let lastFinished {
            let elapsed = clock.now - lastFinished
            if elapsed < spacing {
                try? await Task.sleep(for: spacing - elapsed)
            }
        }
        defer { lastFinished = clock.now }
        return try await work()
    }
}

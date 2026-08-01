import SwiftUI

/// Launch-argument affordances for capturing the app.
///
/// Synthetic taps are not available on this simulator, so every screen and every state
/// has to be reachable by launching straight into it. That is what these are for: they
/// change nothing about how the app behaves when it is launched normally, and they are
/// what `docs/SCREENS.md` is built from.
enum Capture {
    /// `-wpScroll bottom` — start a screen at the end rather than the beginning, so the
    /// half below the fold can be photographed.
    static var startsAtBottom: Bool {
        argument("wpScroll") == "bottom"
    }

    static func argument(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-" + flag), i + 1 < args.count { return args[i + 1] }
        return UserDefaults.standard.string(forKey: flag)
    }
}

extension View {
    /// Applied to a screen's scroll view. Off unless the app was launched to capture it.
    @ViewBuilder
    func captureScrollPosition() -> some View {
        if Capture.startsAtBottom {
            self.defaultScrollAnchor(.bottom)
        } else {
            self
        }
    }
}

import SwiftUI

/// The handful of the app's tokens a widget actually paints with.
///
/// Copied rather than imported. A widget extension has its own process and a memory
/// budget measured in tens of megabytes, and `Tokens.swift` arrives with `Glass.swift`
/// and everything those two reach into. Five colours and two fonts is what this draws.
enum Plate {
    static let lime = Color(red: 0.859, green: 0.902, blue: 0.298)      // #DBE64C
    static let text = Color(red: 0.125, green: 0.122, blue: 0.114)      // #201F1D
    static let onInk = Color(red: 0.953, green: 0.949, blue: 0.949)     // #F3F2F2
    static let accent = Color(red: 0.714, green: 0.510, blue: 0.208)    // #B68235
    static let ink = Color(red: 0.165, green: 0.157, blue: 0.161)       // #2A2829

    /// Cormorant Garamond if the extension has it, and the system serif if not.
    ///
    /// A widget bundles its own fonts or does without: it cannot reach into the app's.
    /// Rather than ship the face twice, this asks for it by name and lets `Font.custom`
    /// fall back — which it does, to the system face at the same size, rather than
    /// failing.
    static func display(_ size: CGFloat) -> Font {
        Font.custom("CormorantGaramond-SemiBold", size: size, relativeTo: .title)
    }

    static func body(_ size: CGFloat, semibold: Bool = false) -> Font {
        .system(size: size, weight: semibold ? .semibold : .regular)
    }

    /// The kicker every screen in the app wears: small, tracked, upper case.
    static func kicker(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .medium) }
}

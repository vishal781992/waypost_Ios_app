import SwiftUI

/// The page colour, while it is still being chosen.
///
/// A testing control: type a hex code on the Profile screen and the whole app takes it,
/// live, so a colour can be judged against real photographs and real type rather than
/// against a swatch. It survives a relaunch, and it is one tap to put back.
///
/// `WP.bg` reads this rather than a constant, and because it is read inside view bodies
/// the Observation framework repaints every screen that draws the page the moment it
/// changes — no restart, no reload.
@MainActor
@Observable
final class PageTint {
    static let shared = PageTint()

    /// What the app ships with.
    static let defaultHex = "D1CFA5"

    private static let key = "parkhop-page-tint"

    var hex: String {
        didSet {
            guard hex != oldValue else { return }
            UserDefaults.standard.set(hex, forKey: Self.key)
        }
    }

    private init() {
        hex = UserDefaults.standard.string(forKey: Self.key) ?? Self.defaultHex
    }

    var colour: Color { Self.colour(from: hex) ?? Self.colour(from: Self.defaultHex)! }

    var isDefault: Bool { Self.normalised(hex) == Self.defaultHex }

    func reset() { hex = Self.defaultHex }

    /// Accepts what people actually type: `#d1cfa5`, `D1CFA5`, or the three-digit short
    /// form. Anything else is nil, and the field says so rather than going black.
    static func colour(from raw: String) -> Color? {
        guard let value = normalised(raw) else { return nil }
        var expanded = value
        if expanded.count == 3 {
            expanded = expanded.map { "\($0)\($0)" }.joined()
        }
        guard expanded.count == 6, let number = UInt32(expanded, radix: 16) else { return nil }
        return Color(hex: number)
    }

    private static func normalised(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        let isHex = trimmed.allSatisfy { $0.isHexDigit }
        guard isHex, trimmed.count == 3 || trimmed.count == 6 else { return nil }
        return trimmed
    }
}

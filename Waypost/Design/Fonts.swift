import CoreText
import SwiftUI
import UIKit

/// Registers the bundled faces with CoreText at launch.
///
/// `UIAppFonts` alone is not enough to rely on: if a face fails to register the app
/// silently falls back to the system sans, and the whole editorial voice — which the
/// design system calls the brand — quietly disappears. This registers each file
/// explicitly and records what actually landed, so `WP.heading` can be checked rather
/// than assumed.
enum Fonts {
    static let files = [
        "CormorantGaramond-Regular", "CormorantGaramond-SemiBold", "CormorantGaramond-Italic",
        "Lora-Regular", "Lora-SemiBold", "Lora-Italic",
        "JetBrainsMono-Regular", "JetBrainsMono-SemiBold",
    ]

    private(set) static var registered: Set<String> = []

    static func register() {
        guard registered.isEmpty else { return }
        for name in files {
            if isAvailable(name) {          // already loaded from UIAppFonts
                registered.insert(name)
                continue
            }
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[Waypost] font missing from bundle: \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), isAvailable(name) {
                registered.insert(name)
            } else {
                print("[Waypost] font unavailable, falling back: \(name)")
            }
        }
    }

    static func isAvailable(_ postScriptName: String) -> Bool {
        CTFontCreateWithName(postScriptName as CFString, 12, nil)
            .postScriptName == postScriptName
    }
}

private extension CTFont {
    var postScriptName: String { CTFontCopyPostScriptName(self) as String }
}


/// Figure styling. Cormorant Garamond ships old-style (text) figures; the design's stat
/// rows, countdowns and temperatures all want lining figures on a fixed advance so
/// columns stay in line as the numbers change.
enum FontFeatures {
    private static var cache: [String: UIFont] = [:]

    static func liningTabular(_ postScriptName: String, _ size: CGFloat) -> UIFont {
        let key = "\(postScriptName)-\(size)"
        if let hit = cache[key] { return hit }

        let base = UIFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [
                [UIFontDescriptor.FeatureKey.type: kNumberCaseType,
                 UIFontDescriptor.FeatureKey.selector: kUpperCaseNumbersSelector],
                [UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                 UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector],
            ],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        cache[key] = font
        return font
    }
}

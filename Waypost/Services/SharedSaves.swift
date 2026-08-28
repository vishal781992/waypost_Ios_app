import Foundation
import WidgetKit

/// The saved list, in the one place the widget can also reach it.
///
/// The app keeps everything in one snapshot under `UserDefaults.standard`, and a widget
/// extension is a different process with a different standard: it cannot see a byte of it.
/// An app group is the only shared ground, and an app group is a capability a free
/// personal team cannot sign — the same wall WeatherKit is behind.
///
/// So this is behind `PARKHOP_APP_GROUP`. With the flag off every call is a no-op, the
/// widget draws no save control, and the app is unchanged. With it on, the app mirrors its
/// saved codes here on every write and takes back anything saved from a plate.
enum SharedSaves {
    static let suite = "group.us.parkhop.waypost"
    static let key = "saved-park-codes"
    /// The widget kind, so a save reloads that timeline and nothing else on the phone.
    static let widgetKind = "ParkPlate"

    #if PARKHOP_APP_GROUP
    static let isShared = true
    private static var store: UserDefaults? { UserDefaults(suiteName: suite) }
    #else
    static let isShared = false
    private static var store: UserDefaults? { nil }
    #endif

    /// Mirrors the app's list out.
    ///
    /// Called from `persist`, which runs on nearly every change — so it compares before it
    /// writes. Reloading a timeline costs a rebuild, six photographs and a slice of the
    /// day's refresh budget, and almost none of what `persist` saves is a saved park.
    static func write(_ codes: [String]) {
        guard let store else { return }
        let sorted = codes.sorted()
        guard store.stringArray(forKey: key) != sorted else { return }
        store.set(sorted, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// What the widget has it as. `nil` where there is no shared ground to read.
    static func read() -> [String]? { store?.stringArray(forKey: key) }
}

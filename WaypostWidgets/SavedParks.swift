import AppIntents
import Foundation
import WidgetKit

/// The saved list, as the widget and the app both see it.
///
/// Behind an app group, which is a capability a free personal team cannot sign — the same
/// wall WeatherKit is behind. So the whole thing is behind `PARKHOP_APP_GROUP`, and with
/// the flag off `isShared` is false and the plate draws no save control at all.
///
/// That silence is deliberate. A button that cannot write anywhere the app will read is a
/// button whose only outcome is nothing happening, and this app already has a rule about
/// those: the calendar switch opens Settings rather than failing quietly.
enum SavedParks {
    static let suite = "group.us.parkhop.waypost"

    #if PARKHOP_APP_GROUP
    static let isShared = true
    private static var store: UserDefaults? { UserDefaults(suiteName: suite) }
    #else
    static let isShared = false
    private static var store: UserDefaults? { nil }
    #endif

    /// The key the app mirrors its own saved list into.
    static let key = "saved-park-codes"

    static func codes() -> Set<String> {
        Set(store?.stringArray(forKey: key) ?? [])
    }

    static func contains(_ code: String) -> Bool { codes().contains(code) }

    /// Adds or removes one park, and returns what it did.
    @discardableResult
    static func toggle(_ code: String) -> Bool {
        guard let store else { return false }
        var list = codes()
        let added = list.insert(code).inserted
        if !added { list.remove(code) }
        store.set(Array(list).sorted(), forKey: key)
        return added
    }
}

/// Saving a park from the plate.
///
/// Interactive widgets arrived in iOS 17 and the app targets 17, so this is a real button
/// rather than a link into the app and back out again.
struct ToggleSaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Save a park for later"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Park") var code: String

    init() {}
    init(code: String) { self.code = code }

    func perform() async throws -> some IntentResult {
        SavedParks.toggle(code)
        // The plate redraws with the disc in its other state. Only this widget kind, so a
        // save does not rebuild every timeline on the phone.
        WidgetCenter.shared.reloadTimelines(ofKind: ParkPlateWidget.kind)
        return .result()
    }
}

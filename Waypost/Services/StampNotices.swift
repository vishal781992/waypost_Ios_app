import Foundation
import UserNotifications

/// The two notices the passport sends, and nothing else.
///
/// One when you arrive somewhere stampable, carrying the two things worth doing about it.
/// One when a stamp landed on its own, so the book never gains a page silently.
///
/// Both are local. Nothing about where the phone is leaves it.
@MainActor
enum StampNotices {
    static let category = "parkhop.stamp.arrival"
    static let stampAction = "parkhop.stamp.now"
    static let skipAction = "parkhop.stamp.skip"

    /// What a tap on one of the actions means. Set by the app, which owns the book.
    static var onStamp: ((Stampable) -> Void)?
    static var onSkip: ((String) -> Void)?
    /// A tap on the banner itself. Opening the book, never stamping: a stamp cannot be
    /// taken back, and a tap on a notification means "show me", not "do it".
    static var onOpen: (() -> Void)?

    private static let centre = UNUserNotificationCenter.current()
    private static let delegate = Delegate()

    /// Register the actions. Cheap, and has to happen before the first notice is posted or
    /// it arrives as a plain banner with nothing on it.
    static func prepare() {
        centre.delegate = delegate
        let stamp = UNNotificationAction(identifier: stampAction, title: "Stamp it",
                                         options: [.authenticationRequired])
        let skip = UNNotificationAction(identifier: skipAction, title: "Not this one",
                                        options: [])
        centre.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [stamp, skip],
                                   intentIdentifiers: [], options: [])
        ])
    }

    /// Ask, once. Returns what the system said, so the screen can stop offering something
    /// it cannot deliver.
    static func ask() async -> Bool {
        (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAllowed() async -> Bool {
        await centre.notificationSettings().authorizationStatus == .authorized
    }

    // MARK: Posting

    /// You have arrived somewhere with a page waiting.
    static func arrived(at place: Stampable, automatic: Bool) async {
        guard await isAllowed() else { return }

        let content = UNMutableNotificationContent()
        content.title = "You’re at \(place.name)"
        content.body = automatic
            ? "Stamp the page while you’re here. Or don’t — it stamps itself in 15 minutes."
            : "Stamp the page while you’re here."
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = box(place)
        // Replaces itself rather than stacking: driving in and out of the same boundary at
        // the edge of a park should not leave six identical banners.
        content.threadIdentifier = place.key

        await post(id: "arrive." + place.key, content)
    }

    /// It stamped itself, and here is the proof.
    static func stamped(_ place: Stampable, on when: Date) async {
        withdrawArrival(for: place.key)
        guard await isAllowed() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(place.name) is in the book"
        content.body = "You stayed, so it stamped itself. Collected "
            + when.formatted(date: .omitted, time: .shortened) + "."
        content.sound = .default
        content.threadIdentifier = place.key

        await post(id: "stamped." + place.key, content)
    }

    /// The arrival notice has been answered, one way or another.
    static func withdrawArrival(for key: String) {
        centre.removeDeliveredNotifications(withIdentifiers: ["arrive." + key])
        centre.removePendingNotificationRequests(withIdentifiers: ["arrive." + key])
    }

    private static func post(id: String, _ content: UNNotificationContent) async {
        // No trigger: it is about now, and a trigger would be a claim about a future the
        // app cannot check when it arrives.
        try? await centre.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: Carrying the place through the system

    private static func box(_ place: Stampable) -> [String: Any] {
        ["key": place.key, "name": place.name, "designation": place.designation,
         "place": place.place, "lat": place.lat, "lon": place.lon,
         "kind": place.kind.rawValue]
    }

    fileprivate static func unbox(_ info: [AnyHashable: Any]) -> Stampable? {
        guard let name = info["name"] as? String,
              let lat = info["lat"] as? Double,
              let lon = info["lon"] as? Double else { return nil }
        return Stampable(name: name,
                         designation: info["designation"] as? String ?? "",
                         place: info["place"] as? String ?? "",
                         lat: lat, lon: lon,
                         kind: Stampable.Kind(rawValue: info["kind"] as? String ?? "") ?? .unit,
                         acres: nil)
    }

    /// Answering the banner without opening the app.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ centre: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions {
            // Shown even with the app in front: the whole point is that it arrives the
            // moment you cross, and somebody looking at the map is exactly who wants it.
            [.banner, .sound]
        }

        func userNotificationCenter(_ centre: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let info = response.notification.request.content.userInfo
            let action = response.actionIdentifier
            await MainActor.run {
                guard let place = StampNotices.unbox(info) else { return }
                switch action {
                case StampNotices.stampAction:
                    StampNotices.onStamp?(place)
                case StampNotices.skipAction:
                    StampNotices.onSkip?(place.key)
                case UNNotificationDefaultActionIdentifier:
                    StampNotices.onOpen?()
                default:
                    break
                }
            }
        }
    }
}

import CoreLocation
import Foundation

/// Where the user is, so the shelf can open on parks near them.
///
/// Precise location is asked for once, when in use. If it is declined, unavailable or
/// slow, the IP lookup gives a loose city — and if that fails too the app falls back to
/// the origin city. A refusal never blocks the app.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    struct Fix {
        var lat: Double
        var lon: Double
        /// False when the fix came from an IP lookup rather than the device.
        var precise: Bool
        var city: String?
        var region: String?
    }

    /// One manager for the whole app. Four services each held their own instance, so a
    /// single unanswered callback stranded several screens at once and each one prompted
    /// separately.
    static let shared = LocationService()

    private let manager = CLLocationManager()
    /// Every caller waiting on the same fix. A single slot meant a second caller
    /// overwrote the first, whose continuation was then never resumed at all.
    private var pending: [CheckedContinuation<Fix?, Never>] = []
    private var deadline: Task<Void, Never>?
    /// Set while the system permission alert is on screen — a `requestLocation()` issued
    /// before the user answers is dropped, and no callback ever arrives.
    private var awaitingAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// A device fix if the user allows one, and nothing at all if they do not.
    ///
    /// This used to fall through to an IP lookup when Core Location said no, which sends
    /// the user's address to a third party immediately after they declined to share where
    /// they are. A refusal is an answer. The IP path is still here, behind
    /// `allowsNetworkFallback`, for a caller that has asked separately and been told yes.
    func currentFix(allowsNetworkFallback: Bool = false) async -> Fix? {
        let status = manager.authorizationStatus
        if let device = await deviceFix() { return device }
        // Only when the user never answered — not when they said no.
        guard allowsNetworkFallback, status != .denied, status != .restricted else { return nil }
        return await ipFix()
    }

    private func deviceFix() async -> Fix? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }

        return await withCheckedContinuation { (c: CheckedContinuation<Fix?, Never>) in
            pending.append(c)
            // A request is already in flight; this caller shares its answer rather than
            // starting a second one.
            guard pending.count == 1 else { return }

            // The deadline resumes the continuation itself. This used to be a second task
            // in a `withTaskGroup`, which cannot work: the group waits for *every* child,
            // and `cancelAll()` never resumes a `CheckedContinuation` — so the timeout
            // elapsed, and then the group blocked forever on Core Location anyway.
            deadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.resume(nil)
            }

            if status == .notDetermined {
                awaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func resume(_ fix: Fix?) {
        deadline?.cancel()
        deadline = nil
        awaitingAuthorization = false
        let waiting = pending
        pending = []
        for continuation in waiting { continuation.resume(returning: fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let fix = Fix(lat: l.coordinate.latitude, lon: l.coordinate.longitude, precise: true)
        Task { @MainActor in self.resume(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(nil) }
    }

    /// The fix request has to wait for the permission alert to be answered. Without this
    /// the app asked for a location while the status was still `.notDetermined`, iOS
    /// discarded the request, and no delegate callback ever came — a permanent hang on
    /// the very first launch.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationChanged() }
    }

    private func authorizationChanged() {
        guard awaitingAuthorization else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            return // The alert is still on screen.
        case .denied, .restricted:
            resume(nil)
        default:
            awaitingAuthorization = false
            manager.requestLocation()
        }
    }

    /// IP lookups often answer with a township ("Southwest Arapahoe"), so the caller
    /// snaps the result to the nearest real city before showing it as an origin.
    private func ipFix() async -> Fix? {
        for endpoint in ["https://ipapi.co/json/", "https://ipwho.is/"] {
            guard let url = URL(string: endpoint) else { continue }
            guard let obj = try? await HTTP.any(url) else { continue }
            let lat = (obj["latitude"] as? Double) ?? Double((obj["latitude"] as? String) ?? "")
            let lon = (obj["longitude"] as? Double) ?? Double((obj["longitude"] as? String) ?? "")
            guard let lat, let lon, !(lat == 0 && lon == 0) else { continue }
            return Fix(
                lat: lat, lon: lon, precise: false,
                city: obj["city"] as? String,
                region: (obj["region_code"] as? String) ?? (obj["region"] as? String)
            )
        }
        return nil
    }
}

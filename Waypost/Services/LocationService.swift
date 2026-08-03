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

    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<Fix?, Never>?

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
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }

        return await withTaskGroup(of: Fix?.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (c: CheckedContinuation<Fix?, Never>) in
                    self.pending = c
                    self.manager.requestLocation()
                }
            }
            // The web app gives the browser 8 seconds before falling back; same here.
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func resume(_ fix: Fix?) {
        pending?.resume(returning: fix)
        pending = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let fix = Fix(lat: l.coordinate.latitude, lon: l.coordinate.longitude, precise: true)
        Task { @MainActor in self.resume(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(nil) }
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

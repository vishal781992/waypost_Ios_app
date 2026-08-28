import Appwrite
import Foundation

/// The app's connection to its Appwrite project.
///
/// Named `Backend` rather than `Appwrite`, because a type of that name inside a module that
/// also imports the `Appwrite` module fights itself: every `Appwrite.Client` afterwards is
/// ambiguous between the module and the type. It is also what the profile already calls
/// this — "app backend status" — so the name is the one already in use.
///
/// One client, made once, held here beside the other services rather than as a loose global
/// — the same shape `TripCalendar` and `Connections` take, and for the same reason: a
/// dependency the whole app can reach into from anywhere is a dependency nothing can be
/// reasoned about.
///
/// **Nothing of the traveller's goes through it yet.** The only call this makes is `ping`,
/// which asks the endpoint whether it is there and carries no data at all. That matters
/// because two pieces of copy in this app currently say the phone sends nothing —
/// `ProfileIdentityEditor`'s "Nothing is sent anywhere" and the erase alert's "Nothing here
/// has left this phone" — and both are still true. The first trip, name or account that
/// travels through `account` makes them false, and they have to be rewritten that day.
///
/// **The endpoint and the project id are not secrets.** Appwrite's client configuration is
/// public by design: the project id identifies the project to a client anyone can inspect,
/// and access is decided by the project's own permissions rather than by the id being
/// unknown. Hard-coding them here is what the SDK expects, not a shortcut.
///
/// `account` is unused today and deliberately present: `StubAuthService` was written with
/// `signIn`, `claim` and `signOut` as real shapes so that "wiring a provider behind this
/// does not move anything above it", and Appwrite's `Account` is that provider when
/// somebody decides accounts are wanted.
@MainActor
@Observable
final class Backend {
    static let shared = Backend()

    /// The key `Connections` files this source's health under. One string, used by the
    /// source row and by every call that reports — a second spelling would leave the row
    /// reading *not needed yet* forever, which is the one answer that screen must never
    /// give wrongly.
    static let key = "Appwrite"

    static let endpoint = "https://sfo.cloud.appwrite.io/v1"
    static let projectID = "6a90d20f000cd44bc41b"

    let client: Client
    let account: Account

    /// What the last ping came back with, for the row that asked. Nil until one has run.
    private(set) var lastPing: String?
    private(set) var isPinging = false

    private let failures = FailureLog()

    private init() {
        client = Client()
            .setEndpoint(Self.endpoint)
            .setProject(Self.projectID)
        account = Account(client)
    }

    /// Asks the endpoint whether it is there.
    ///
    /// Reports through `FailureLog` either way, which is what puts the answer on the
    /// Connections screen without this having to know that screen exists — the same route
    /// every other service in the app reports by.
    @discardableResult
    func ping() async -> Bool {
        guard !isPinging else { return false }
        isPinging = true
        defer { isPinging = false }

        do {
            let answer = try await client.ping()
            lastPing = answer
            failures.ok(Self.key)
            return true
        } catch {
            lastPing = nil
            failures.note(Self.key, error)
            return false
        }
    }
}

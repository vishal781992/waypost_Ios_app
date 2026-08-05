import Foundation

/// How somebody gets into the app.
///
/// Four ways, one of which is deliberately not an account at all. The network is stubbed;
/// the shapes are real, so wiring a provider behind this does not move anything above it.
enum AuthMethod: String, CaseIterable {
    case apple, google, emailLink, guest
}

/// Who is using the app, if anyone.
enum Identity: Equatable {
    /// No account. Everything is on this phone and stays there.
    case guest
    case signedIn(method: AuthMethod, userID: String, email: String?)

    var isGuest: Bool { self == .guest }
}

@MainActor
protocol AuthService {
    var identity: Identity? { get }
    func signIn(_ method: AuthMethod) async throws -> Identity
    func continueAsGuest() -> Identity
    /// Turns a guest into an account without losing what they collected as one.
    func claim(_ method: AuthMethod) async throws -> Identity
    func signOut()
}

enum AuthError: LocalizedError {
    case unavailable(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return why
        case .cancelled: return "Sign-in was cancelled."
        }
    }
}

/// The stub the app ships with today.
///
/// Guest is the only path that fully works, and that is honest rather than temporary: it
/// needs no server, and everything it stores is already local. The three account paths
/// report why they cannot run instead of pretending to succeed.
@MainActor
@Observable
final class StubAuthService: AuthService {
    static let shared = StubAuthService()

    private(set) var identity: Identity?

    private static let key = "parkhop-identity"

    private init() {
        if UserDefaults.standard.string(forKey: Self.key) == "guest" { identity = .guest }
    }

    func signIn(_ method: AuthMethod) async throws -> Identity {
        switch method {
        case .guest:
            return continueAsGuest()
        case .apple:
            // Sign in with Apple is an entitlement, and the entitlement needs a paid
            // developer account — the same reason WeatherKit is switched off in project.yml.
            // The button stays so the screen is the screen that will ship; it says why it
            // cannot run rather than failing silently at authorization.
            throw AuthError.unavailable("Sign in with Apple needs a paid Apple Developer account. Not available in this build.")
        case .google, .emailLink:
            throw AuthError.unavailable("Not wired up yet — use “Look around as a guest” for now.")
        }
    }

    /// A real state, not a placeholder. Nothing is written anywhere but this phone.
    func continueAsGuest() -> Identity {
        UserDefaults.standard.set("guest", forKey: Self.key)
        identity = .guest
        return .guest
    }

    /// Guest and signed-in read and write the same store, so this never has to migrate
    /// anything — which is the point of them sharing a schema.
    func claim(_ method: AuthMethod) async throws -> Identity {
        try await signIn(method)
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        identity = nil
    }
}

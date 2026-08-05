import SwiftUI

/// The two onboarding screens, over one photograph.
///
/// The hero lives here rather than in either screen so that moving between them changes the
/// content and not the background. A `NavigationLink` push would slide the photograph with
/// the text, which is the one thing the design asks it not to do.
struct OnboardingFlow: View {
    enum Step { case welcome, auth }

    var onFinish: (Identity) -> Void

    @State private var step: Step = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var curve: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.42) }

    var body: some View {
        ZStack {
            OnboardingHero(screen: step == .welcome ? .welcome : .auth)

            Group {
                switch step {
                case .welcome:
                    WelcomeView { advance() }
                        .transition(contentTransition)
                case .auth:
                    AuthChoiceView(onBack: retreat, onFinish: onFinish)
                        .transition(contentTransition)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }

    /// Out lifts and fades; in fades a beat later. Reduce Motion drops the translation and
    /// keeps the cross-fade.
    private var contentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(curve.delay(0.09)),
            removal: .opacity.combined(with: .offset(y: -14))
        )
    }

    private func advance() { withAnimation(curve) { step = .auth } }
    private func retreat() { withAnimation(curve) { step = .welcome } }
}

// MARK: - Screen one

struct WelcomeView: View {
    var onStart: () -> Void

    @State private var legal: LegalDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text("63 parks · 84 monuments · est. 1872".uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.9)
                .foregroundStyle(PH.paperWarm.opacity(0.55))

            Text("Welcome\nto ParkHop.")
                .font(.phDisplay(52))
                .lineSpacing(-2)
                .tracking(-0.5)
                .foregroundStyle(PH.paperWarm)
                .padding(.top, 11)
                .fixedSize(horizontal: false, vertical: true)

            Text("Plan the drive, the permits and the weather — then lose signal and keep going.")
                .font(.system(size: 15.5))
                .lineSpacing(5)
                .foregroundStyle(PH.paperWarm.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            GlassPill(emphasis: .primary, height: 54, action: onStart) {
                Text("Get started")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                    .foregroundStyle(PH.paperBright)
            }
            .padding(.top, 26)

            OnboardingLegal(opacity: 0.50, linkOpacity: 0.72,
                            onTerms: { legal = .terms },
                            onPrivacy: { legal = .privacy })
                .padding(.top, 16)
        }
        .padding(.horizontal, 27)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $legal) { LegalSheet(document: $0) }
    }
}

// MARK: - Screen two

struct AuthChoiceView: View {
    var onBack: () -> Void
    var onFinish: (Identity) -> Void

    @State private var legal: LegalDocument?
    @State private var failure: String?

    private let auth = StubAuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            quote

            VStack(spacing: 9) {
                pill(.apple, "Continue with Apple", emphasis: .primary)
                pill(.google, "Continue with Google")
                pill(.emailLink, "Continue with email")
            }
            .padding(.top, 20)

            divider.padding(.top, 18)

            guest.padding(.top, 14)

            if let failure {
                Text(failure)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PH.paperWarm.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }

            OnboardingLegal(opacity: 0.42, linkOpacity: 0.62,
                            onTerms: { legal = .terms },
                            onPrivacy: { legal = .privacy })
                .padding(.top, 16)
        }
        .padding(.horizontal, 27)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $legal) { LegalSheet(document: $0) }
    }

    /// Read as one thing by VoiceOver — the words and who said them are not two facts.
    private var quote: some View {
        HStack(alignment: .top, spacing: 15) {
            Rectangle()
                .fill(PH.accent.opacity(0.55))
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 11) {
                Text("“That is all the National Parks are about. Use, but do no harm.”")
                    .font(.phDisplayItalic(29))
                    .lineSpacing(5)
                    .foregroundStyle(PH.paperWarm)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Wallace Stegner".uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(PH.paperWarm.opacity(0.50))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("That is all the National Parks are about. Use, but do no harm. Wallace Stegner.")
    }

    private func pill(_ method: AuthMethod, _ title: String,
                      emphasis: GlassEmphasis = .secondary) -> some View {
        GlassPill(emphasis: emphasis) {
            Task { await attempt(method) }
        } label: {
            HStack(spacing: 9) {
                glyph(for: method)
                Text(title)
                    .font(.system(size: 16.5, weight: emphasis == .primary ? .semibold : .medium))
                    .tracking(-0.16)
                    .foregroundStyle(emphasis == .primary ? PH.paperBright : Color(hex: 0xFBF6EE))
            }
        }
    }

    @ViewBuilder
    private func glyph(for method: AuthMethod) -> some View {
        switch method {
        case .apple:
            Image(systemName: "applelogo").font(.system(size: 16)).foregroundStyle(PH.paperBright)
        case .google:
            // Google's mark may not be recoloured, so it is an asset rather than a tinted
            // symbol. Until it is in the catalogue, nothing is drawn rather than a wrong
            // monochrome stand-in.
            if let mark = UIImage(named: "GoogleMark") {
                Image(uiImage: mark).resizable().frame(width: 17, height: 17)
            }
        case .emailLink:
            Image(systemName: "envelope").font(.system(size: 15, weight: .light))
                .foregroundStyle(Color(hex: 0xFBF6EE))
        case .guest:
            EmptyView()
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(PH.paperWarm.opacity(0.20)).frame(height: 1)
            Text("or".uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.7)
                .foregroundStyle(PH.paperWarm.opacity(0.42))
            Rectangle().fill(PH.paperWarm.opacity(0.20)).frame(height: 1)
        }
    }

    /// Deliberately not a pill: guest is a choice with a cost, and the caption states the
    /// cost. It is part of the button's accessibility hint so it is announced, not only seen.
    private var guest: some View {
        VStack(spacing: 5) {
            Button {
                onFinish(auth.continueAsGuest())
            } label: {
                HStack(spacing: 6) {
                    Text("Look around as a guest")
                        .font(.system(size: 16))
                        .underline(true, color: PH.paperWarm.opacity(0.40))
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(PH.paperWarm.opacity(0.90))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Nothing is saved or synced. Trips, stamps and offline packs stay on this phone only.")

            Text("Nothing is saved or synced — trips, stamps and offline packs stay on this phone only.")
                .font(.system(size: 11.5))
                .foregroundStyle(PH.paperWarm.opacity(0.44))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func attempt(_ method: AuthMethod) async {
        do {
            onFinish(try await auth.signIn(method))
        } catch {
            withAnimation(.snappy(duration: 0.2)) {
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - Legal

enum LegalDocument: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms" : "Privacy Policy" }
}

struct LegalSheet: View {
    var document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document == .terms
                     ? "The terms this app ships under have not been written yet. This sheet is where they will read."
                     : "ParkHop stores what you plan on this iPhone. Location is used to measure distances and is not sent anywhere except to the routing and weather services that need a coordinate to answer.")
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .padding()
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Previews

#Preview("Welcome · iPhone 15") {
    OnboardingFlow { _ in }
}

#Preview("Auth · large type") {
    OnboardingFlow { _ in }
        .environment(\.dynamicTypeSize, .xLarge)
}

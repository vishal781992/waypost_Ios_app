import SwiftUI

@main
struct WaypostApp: App {
    @State private var app = AppState()
    /// Who is using the app, read off the service rather than copied out of it.
    ///
    /// It was a `@State` snapshot taken once at launch, which was fine while the only way
    /// in was through the opening screens. Logging out happens on the profile, three
    /// screens away, and a copy taken at launch cannot hear about it — so the service is
    /// the one place that knows, and this observes it. Nil until somebody has chosen how to
    /// come in, including choosing not to have an account at all.
    @State private var auth = StubAuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.identity == nil {
                    // The onboarding screens are photographic and always dark; the app they
                    // open into is neither, which is why the scheme is set per branch rather
                    // than once around both.
                    //
                    // The callback carries the chosen identity, which the service has
                    // already recorded — nothing to assign here.
                    OnboardingFlow { _ in }
                    .transition(.opacity)
                } else {
                    RootShell()
                        .environment(app)
                        // The Classical palette is a light one and commits to it, as on the
                        // web — but the home screen is a photograph behind the status bar and
                        // needs the dark scheme for those glyphs alone. `RootShell` decides,
                        // per tab; a `.preferredColorScheme(.light)` written here would sit
                        // outside it and win, which is exactly what it used to do.
                        .tint(WP.accent)
                        .transition(.opacity)
                }
            }
            // The crossfade the onboarding callback used to run by hand. Written here so it
            // covers both directions — coming in, and logging back out again.
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.42), value: auth.identity == nil)
        }
    }
}

/// The app shell: five destinations under a floating glass tab bar, a push stack that
/// slides in over them, sheets over that, and the toast above everything.
struct RootShell: View {
    @Environment(AppState.self) private var app

    /// Shared by every card that can be opened and every screen it opens into, so the
    /// zoom transition knows which pair belongs together.
    @Namespace private var zoom

    /// Whether the hand-built bar is held out of the way. Owned here, driven by whichever
    /// root screen is being read.
    @State private var chrome = TabBarChrome()

    var body: some View {
        @Bindable var app = app

        // These are read here, in the body, on purpose — the same reason the path is, and
        // the comment below explains why. A hand-built `Binding` whose `get` reads state
        // registers no Observation dependency, because the closure runs after the body has
        // finished. `app.sheet`, `app.builder` and `app.tab` were all read only inside
        // such closures, so a button that set one of them changed the value and nothing
        // redrew: the sheet opened later, when some *other* observed property happened to
        // re-evaluate the shell. That is the second tap.
        let currentTab = app.tab
        let currentSheet = app.sheet
        let openBuilder = app.builder

        /// Selection is routed through `AppState` so the dashboard tiles and the passport
        /// nudge can still change tabs, and so the last one is remembered across launches.
        let selection = Binding<AppTab>(get: { currentTab }, set: { app.go($0) })

        // Still a real TabView — it keeps the selection, the per-tab navigation stacks and
        // the zoom transitions. Only the bar itself is ours, because the system's spans the
        // screen and offers no way to bring its items closer together.
        //
        // The bar is a sibling of the `TabView` rather than an overlay on it. As an overlay
        // it drew in the right place and answered nothing: the tab bar controller beneath
        // takes the touches in that strip whether or not its own bar is showing.
        ZStack(alignment: .bottom) {
            TabView(selection: selection) {
                ForEach(AppTab.allCases) { tab in
                    // The path is read here, in the body, on purpose. A hand-built `Binding`
                    // whose `get` closure reads the path never registers a dependency —
                    // Observation tracks what a body *reads*, and the closure runs later —
                    // so pushing and popping mutated the array and nothing redrew. Reading
                    // it here registers the dependency; `$app.paths` carries the writes back.
                    let screens = app.path(for: tab)
                    tabStack(tab, path: Binding(
                        get: { screens },
                        set: { app.setPath($0, for: tab) }
                    ))
                        .tag(tab)
                }
            }
            .modifier(NativeTabBarBehaviour())

            // Hidden under a push, the same as the system bar was. The pushed screen has
            // its own header and its own way back, and the bar over it was never part of
            // that page.
            if app.path(for: currentTab).isEmpty {
                CompactTabBar(selection: selection, isMinimized: chrome.isMinimized,
                              profileEmoji: app.profileEmoji)
                    // Down to the safe area's own line and no further. Below it is the
                    // strip iOS reserves for the home gesture, which takes the first
                    // touch — the fault the park screen's rail had until it was lifted
                    // back out of it.
                    .padding(.bottom, 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.zoomNamespace, zoom)
        .environment(chrome)
        // A tab you have just come back to should not still be holding its bar down from
        // the last time you read it.
        .onChange(of: currentTab) { chrome.reset() }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(text: toast)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        // The status bar the home screen needs, decided here rather than inside the
        // `TabView`. Home is a photograph under the clock and the battery, and those take
        // their colour from the window's scheme — dark glyphs over a cave mouth are simply
        // gone. Written at this level because a preference set inside a `TabView` page does
        // not reliably reach the window: it held at launch and was lost the first time a
        // reader came back from another tab.
        //
        // Only at the root of Nearby. A park pushed out of it is a paper screen again.
        .preferredColorScheme(currentTab == .today && app.path(for: .today).isEmpty ? .dark : .light)
        .sheet(item: Binding(get: { currentSheet }, set: { app.sheet = $0 })) { sheet in
            // The sheets are paper whatever is behind them, so they say so rather than
            // inheriting whichever scheme the tab underneath happens to be wearing.
            DetailSheet(sheet: sheet)
                .preferredColorScheme(.light)
                .environment(\.planningTrip, app.sheetTrip)
        }
        .sheet(isPresented: Binding(get: { openBuilder != nil },
                                    set: { if !$0 { app.builder = nil } })) {
            if let openBuilder {
                NewTripSheet(builder: openBuilder).preferredColorScheme(.light)
            }
        }
    }

    /// One tab, with its own navigation stack. Split out because the whole TabView body
    /// was more than the type-checker would take in one expression.
    private func tabStack(_ tab: AppTab, path: Binding<[PushedScreen]>) -> some View {
        NavigationStack(path: path) {
            destination(tab)
                // `.navigationBarHidden(true)` hides the bar *and* switches off the
                // interactive pop gesture with it, so on a screen with a custom header
                // there was no way back but the button. The toolbar API hides only the
                // bar.
                .toolbar(.hidden, for: .navigationBar)
                // The system bar is off everywhere; `CompactTabBar` stands in for it.
                .toolbar(.hidden, for: .tabBar)
                .navigationDestination(for: PushedScreen.self) { screen in
                    // Every pushed screen gets its own paper, here rather than in each
                    // screen. Discover never painted one — it read the page colour off the
                    // tab root showing through behind it, which worked only because the
                    // window was light everywhere. Now that Nearby puts the window into the
                    // dark scheme for its status bar, that show-through is black, and
                    // Discover pushed in over a black page before its own content landed.
                    ZStack {
                        WP.bg.ignoresSafeArea()
                        pushed(screen)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .zoomDestination(screen.id, in: zoom)
                    .toolbar(.hidden, for: .tabBar)
                }
        }
    }

    /// One destination. The push stack is the system's now, so the interactive back-swipe
    /// and the zoom come with it.
    @ViewBuilder
    private func destination(_ tab: AppTab) -> some View {
        switch tab {
        // Home lays its own ground: a photograph, full-bleed to all four edges. The page
        // colour under it would only ever be the half-second of paper before the first
        // picture arrives, and the carousel's own colour field is the better answer.
        case .today:
            HomeCarouselView()
        case .trips, .saved, .me:
            ZStack {
                WP.bg.ignoresSafeArea()

                switch tab {
                case .trips: TripsScreen()
                case .saved: SavedScreen()
                case .me: ProfileScreen()
                case .today: EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func pushed(_ screen: PushedScreen) -> some View {
        switch screen {
        case .park(let code, let segment, let date, let trip):
            if let park = app.park(code) {
                ParkScreen(park: park, initialSegment: segment, date: date)
                    // Only a park opened from a trip can add to that trip's list. From the
                    // home screen or from Discover this is nil and no add control is drawn,
                    // because there is no list for a place to go on.
                    .environment(\.planningTrip, trip)
                    // The day the trip reaches this park, so what is added here files
                    // itself under that day rather than into the undated pile.
                    .environment(\.planningDay, date)
            }
        case .trip(let id):
            if let trip = app.trip(id) {
                TripDetailScreen(trip: trip)
            }
        case .explore:
            DiscoverScreen()
        case .atlas:
            AtlasScreen()
        case .preferences:
            PreferencesScreen()
        case .packs:
            OfflinePacksScreen()
        case .connections:
            ConnectionsScreen()
        }
    }
}

// MARK: - Chrome

/// A screen header: the glass plate every destination hangs its title from.
struct ScreenHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WP.gutter)
        .padding(.top, WP.headerTop)
        .padding(.bottom, 11)
        .background {
            Color.clear
                .liquidGlass(.header, radius: 0)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 0.5)
        }
    }
}

/// The header of a pushed screen: a back button, a centred title, glass behind both.
struct PushHeader: View {
    var backLabel: String
    var title: String
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 15pt back, 16pt title: both read as system chrome borrowed from another
            // app rather than as part of a screen whose masthead is 44pt serif.
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                    Text(backLabel).font(WP.body(19))
                }
                .foregroundStyle(WP.accent700)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                // 44 points, as every control on the screen should be.
                .frame(minHeight: 44, alignment: .center)
            }
            .buttonStyle(PressStyle(scale: 0.94))

            Spacer(minLength: 0)
            Text(title)
                .font(WP.display(24))
                .lineLimit(1)
                // A trip's name is as long as somebody made it; shrinking reads better
                // than "The Colorado Platea…".
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)

            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, WP.headerTop)
        .padding(.bottom, 9)
        .background {
            Color.clear
                .liquidGlass(.header, radius: 0)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 0.5)
        }
    }
}

/// The app's tint. The system tab bar is hidden, so what is left here is the accent every
/// other control inherits.
struct NativeTabBarBehaviour: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(WP.neutral900)
    }
}

/// The tab glyphs, drawn from the design's SVG paths rather than swapped for SF Symbols —
/// the compass rose and the milepost are part of the brand.
///
/// These used to be flattened into template images, because a system tab item takes an
/// `Image` and nothing else. `CompactTabBar` draws views, so the shapes go in as they are.
struct TabIcon: View {
    var tab: AppTab
    /// The emoji to wear in place of the person, on the Profile tab.
    ///
    /// Passed rather than read from the environment, because this is a drawing of four
    /// glyphs and nothing else — a view that reaches into app state to decide what it is
    /// cannot be put anywhere app state is not.
    ///
    /// `nil` means nobody has picked one, and the drawn person stands in.
    var worn: String? = nil

    /// Whether this is the tab being looked at.
    ///
    /// The three drawn glyphs need no such flag: they take their colour from the bar and
    /// go from `neutral600` to `neutral900` on their own. An emoji cannot be tinted, so it
    /// is the one glyph that has to be told, and it says the same thing a different way —
    /// grey and held back when the tab is not the one you are on.
    ///
    /// Without that it would be the only colour in a bar of grey marks at all times, and
    /// the tab nobody is on would be the loudest thing on the screen.
    var lit: Bool = true

    var body: some View {
        switch tab {
        case .today:
            NavigationDart()
        case .trips:
            SuitcaseShape()
        case .saved:
            BookmarkShape()
        case .me:
            if let worn {
                // Twenty-three points rather than the twenty-nine the frame allows: an
                // emoji is drawn with its own margin, so a glyph set to the box overshoots
                // the three that are drawn to it.
                Text(worn)
                    .font(.system(size: 23))
                    .grayscale(lit ? 0 : 1)
                    .opacity(lit ? 1 : 0.55)
            } else {
                VStack(spacing: 1.4) {
                    Circle().frame(width: 7.8, height: 7.8)
                    PersonBody()
                }
                .offset(y: 0.6)
            }
        }
    }
}

/// Nearby's mark: the dart every map draws where you are standing.
///
/// It replaced a disc with eight even rays around it. Whatever the comment beside that one
/// said, eight even rays is a *sun* — a compass rose has pointed arms of alternating length
/// — and a sun says the day. It suited a tab called Today and says nothing about a screen
/// organised by how far things are from here.
///
/// Drawn to the 29-point box the caller frames it in, the way `BookmarkShape` is. The
/// corners are rounded by stroking the same outline underneath the fill rather than by
/// arcing four vertices at four different angles by hand; the stroke inherits the tab's
/// colour, so both halves change together on selection.
private struct NavigationDart: View {
    /// Inset from the box by half the stroke, so the rounding grows into the frame rather
    /// than out of it.
    private var outline: Path {
        Path { p in
            p.move(to: CGPoint(x: 23.2, y: 5.8))
            p.addLine(to: CGPoint(x: 6.0, y: 13.4))
            p.addLine(to: CGPoint(x: 12.9, y: 16.1))
            p.addLine(to: CGPoint(x: 15.6, y: 23.0))
            p.closeSubpath()
        }
    }

    var body: some View {
        ZStack {
            outline
            outline.stroke(style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Trips' mark: a hard case with a handle.
///
/// This replaced the milepost — a post, two arrows and a base — which was the app's
/// namesake mark and the least legible thing in the bar: read as a signpost, an arrow or a
/// road sign before it was read as trips. The trade was made deliberately, and the milepost
/// is in the history at this commit if it is ever wanted back.
///
/// The handle is a 2.1-point line, which is the weight the milepost's own post carried, so
/// the set keeps one line thickness between all four glyphs.
private struct SuitcaseShape: View {
    private var handle: Path {
        Path { p in
            p.move(to: CGPoint(x: 10.6, y: 9.4))
            p.addLine(to: CGPoint(x: 10.6, y: 7.9))
            p.addQuadCurve(to: CGPoint(x: 12.6, y: 5.9), control: CGPoint(x: 10.6, y: 5.9))
            p.addLine(to: CGPoint(x: 16.4, y: 5.9))
            p.addQuadCurve(to: CGPoint(x: 18.4, y: 7.9), control: CGPoint(x: 18.4, y: 5.9))
            p.addLine(to: CGPoint(x: 18.4, y: 9.4))
        }
    }

    var body: some View {
        ZStack {
            handle.stroke(style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
            // Centred by the stack and then dropped, so the case hangs under its handle:
            // 14.5 + 2.5 puts it between 9.4 and 24.6 in the 29-point box.
            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                .frame(width: 20.2, height: 15.2)
                .offset(y: 2.5)
        }
    }
}

private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX * 0.9, y: rect.midY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX * 1.1, y: rect.midY * 1.1))
        p.closeSubpath()
        return p
    }
}

private struct BookmarkShape: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 6.6, y: 3.2))
            p.addLine(to: CGPoint(x: 17.4, y: 3.2))
            p.addLine(to: CGPoint(x: 18.5, y: 4.3))
            p.addLine(to: CGPoint(x: 18.5, y: 21.2))
            p.addLine(to: CGPoint(x: 12, y: 18.1))
            p.addLine(to: CGPoint(x: 5.5, y: 21.2))
            p.addLine(to: CGPoint(x: 5.5, y: 4.3))
            p.closeSubpath()
        }
        .frame(width: 24, height: 24)
    }
}

private struct PersonBody: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                   control1: CGPoint(x: rect.width * 0.2, y: 0),
                   control2: CGPoint(x: rect.width * 0.8, y: 0))
        p.closeSubpath()
        return p
    }
}

extension Shape {
    /// The tab glyphs are solid; this keeps their call sites short.
    func solid() -> some View { fill(Color.primary) }
}

/// A binding-friendly sheet presentation for the `ActiveSheet` enum.
private extension View {
    func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(isPresented: Binding(get: { item.wrappedValue != nil },
                                  set: { if !$0 { item.wrappedValue = nil } })) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}

/// The version badge the Profile screen shows, read from the bundle so it can never drift.
///
/// Four parts, `vX.Y.Z.a`: `X` a major release, `Y` and `Z` iterations on it, and `a` the
/// smallest change worth telling a tester apart. The first three are `MARKETING_VERSION`
/// in `project.yml`; the last is `CURRENT_PROJECT_VERSION`, so both are bumped in the one
/// place the build already reads them from and neither can drift from what shipped.
enum AppVersion {
    private static func value(_ key: String, fallback: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? fallback
    }

    /// "v2.24.0"
    static var short: String { "v" + value("CFBundleShortVersionString", fallback: "0.0.0") }

    /// "v2.24.0.2" — what a tester quotes in a bug report.
    static var full: String { short + "." + value("CFBundleVersion", fallback: "0") }
}

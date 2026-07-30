import SwiftUI

@main
struct WaypostApp: App {
    @State private var app = AppState()

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environment(app)
                // The Classical palette is a light one and commits to it, as on the web.
                .preferredColorScheme(.light)
                .tint(WP.accent)
        }
    }
}

/// The app shell: five destinations under a floating glass tab bar, a push stack that
/// slides in over them, sheets over that, and the toast above everything.
struct RootShell: View {
    @Environment(AppState.self) private var app

    /// Selection is routed through `AppState` so the dashboard tiles and the passport
    /// nudge can still change tabs, and so the last one is remembered across launches.
    private var selection: Binding<AppTab> {
        Binding(get: { app.tab }, set: { app.go($0) })
    }

    var body: some View {
        // A real TabView, so the tab bar is the system's: Liquid Glass with its own
        // scroll-edge response, the selection morphing between items, and the bar
        // shrinking out of the way as you read down a screen. Hand-drawing that bar got
        // the look but none of the behaviour.
        TabView(selection: selection) {
            ForEach(AppTab.allCases) { tab in
                destination(tab)
                    .tag(tab)
                    .tabItem {
                        Label {
                            Text(tab.label)
                        } icon: {
                            TabIconImage.image(for: tab)
                        }
                    }
            }
        }
        .modifier(NativeTabBarBehaviour())
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(text: toast)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: Binding(get: { app.sheet }, set: { app.sheet = $0 })) { sheet in
            DetailSheet(sheet: sheet)
        }
        .sheet(isPresented: Binding(get: { app.builder != nil }, set: { if !$0 { app.builder = nil } })) {
            if let builder = app.builder {
                NewTripSheet(builder: builder)
            }
        }
    }

    /// One destination, with its own push stack laid over it — a park opened from Today
    /// keeps Today underneath, and the tab bar stays put, as the design has it.
    @ViewBuilder
    private func destination(_ tab: AppTab) -> some View {
        ZStack {
            WP.bg.ignoresSafeArea()

            switch tab {
            case .today: TodayScreen()
            case .trips: TripsScreen()
            case .discover: DiscoverScreen()
            case .saved: SavedScreen()
            case .me: ProfileScreen()
            }

            if app.tab == tab {
                ForEach(Array(app.stack.enumerated()), id: \.element.id) { index, screen in
                    pushed(screen)
                        .zIndex(Double(10 + index))
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }

    @ViewBuilder
    private func pushed(_ screen: PushedScreen) -> some View {
        switch screen {
        case .park(let code, let segment):
            if let park = app.library.park(code) {
                ParkScreen(park: park, initialSegment: segment)
            }
        case .trip(let id):
            if let trip = app.trip(id) {
                TripDetailScreen(trip: trip)
            }
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
        .liquidGlass(.header, radius: 0)
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
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text(backLabel).font(WP.body(15))
                }
                .foregroundStyle(WP.accent700)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .buttonStyle(PressStyle(scale: 0.94))

            Spacer(minLength: 0)
            Text(title)
                .font(WP.headingUI(16))
                .lineLimit(1)
            Spacer(minLength: 0)

            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, WP.headerTop)
        .padding(.bottom, 9)
        .liquidGlass(.header, radius: 0)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 0.5)
        }
    }
}

/// The behaviours the system tab bar gains on iOS 26: the bar minimises as you read
/// down a screen and expands again when you scroll back up, and the whole thing is
/// Liquid Glass with its own scroll-edge response.
///
/// The item titles stay in the system face. The new bar styles them itself and ignores
/// `UITabBarItem.appearance()`, and fighting it would mean giving up the native bar —
/// which is the thing worth having. The glyphs are still the design's own.
struct NativeTabBarBehaviour: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tint(WP.neutral900)
        } else {
            content.tint(WP.neutral900)
        }
    }
}

/// The design's own glyphs, rendered once into template images so the system tab bar can
/// carry them. Tab items take an `Image`; drawing the shapes inline would have meant
/// giving up the native bar, and the compass rose and milepost are part of the brand.
@MainActor
enum TabIconImage {
    private static var cache: [AppTab: Image] = [:]

    static func image(for tab: AppTab) -> Image {
        if let hit = cache[tab] { return hit }
        let renderer = ImageRenderer(
            content: TabIcon(tab: tab)
                .frame(width: 26, height: 26)
                .foregroundStyle(.black)
        )
        renderer.scale = 3
        guard let rendered = renderer.uiImage?.withRenderingMode(.alwaysTemplate) else {
            return Image(systemName: "circle")
        }
        let image = Image(uiImage: rendered)
        cache[tab] = image
        return image
    }
}

/// The tab glyphs, drawn from the design's SVG paths rather than swapped for SF Symbols —
/// the compass rose and the milepost are part of the brand.
struct TabIcon: View {
    var tab: AppTab

    var body: some View {
        switch tab {
        case .today:
            ZStack {
                Circle().frame(width: 10, height: 10)
                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .frame(width: 2.1, height: 4.6)
                        .offset(y: -9.4)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
            }
        case .trips:
            ZStack {
                RoundedRectangle(cornerRadius: 1).frame(width: 2.1, height: 17.4)
                MilepostArrow().frame(width: 8, height: 5).offset(x: 4.6, y: -4.5)
                MilepostArrow().frame(width: 8, height: 5).scaleEffect(x: -1).offset(x: -4.6, y: 3)
                RoundedRectangle(cornerRadius: 1).frame(width: 6, height: 2).offset(y: 8.6)
            }
        case .discover:
            ZStack {
                Circle().frame(width: 14.8, height: 14.8).offset(x: -1.2, y: -1.2)
                Capsule().frame(width: 6.4, height: 2.6)
                    .rotationEffect(.degrees(45)).offset(x: 7.5, y: 7.5)
                NeedleShape()
                    .fill(WP.bg)
                    .frame(width: 8, height: 8)
                    .offset(x: -1.2, y: -1.2)
            }
        case .saved:
            BookmarkShape()
        case .me:
            VStack(spacing: 1.4) {
                Circle().frame(width: 7.8, height: 7.8)
                PersonBody()
            }
            .offset(y: 0.6)
        }
    }
}

private struct MilepostArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.72, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
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
enum AppVersion {
    static var short: String {
        "v" + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0")
    }
}

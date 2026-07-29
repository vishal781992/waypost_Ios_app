import SwiftUI

@main
struct WaypostApp: App {
    @State private var store = TripStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.start() }
        }
    }
}

struct RootView: View {
    @Environment(TripStore.self) private var store

    var body: some View {
        ZStack {
            WP.bg.ignoresSafeArea()
            switch store.view {
            case .plan: PlanView()
            case .trip: TripView()
            }
        }
        .tint(WP.accent)
        .preferredColorScheme(.light)   // the Classical palette is a light one, as on the web
        .animation(.easeInOut(duration: 0.22), value: store.view)
    }
}

/// The version shown in the nav badge. Read from the bundle rather than typed into the
/// markup — the web repo needs `sync-version.sh` for exactly this reason.
enum AppVersion {
    static var short: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (v ?? "0.0.0")
    }
}

/// The app bar: the dark plate both screens hang from.
struct AppBar<Trailing: View, Leading: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 9) {
            HStack { leading; Spacer(minLength: 0) }
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Text(title)
                    .font(WP.heading(24, weight: .regular))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(WP.body(10))
                        .italic()
                        .opacity(0.5)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack { Spacer(minLength: 0); trailing }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(WP.ink)
        .foregroundStyle(WP.bg)
    }
}

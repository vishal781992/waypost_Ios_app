import SwiftUI

/// Home — one photograph, edge to edge, and the park it is of.
///
/// The bordered recommendation card on a paper ground is gone. There is no card and no
/// paper here: a National Park photograph fills the display, holds for eight seconds while
/// it drifts, and cross-fades into the next. The park showing is named at the bottom in
/// display type and tapping the name opens it. One long scrim is the only thing holding
/// the type up.
///
/// Everything the old screen carried below the hero — the driving day, the stamps within
/// reach — is still here, on the paper sheet the photograph slides under when you read on.
struct HomeCarouselView: View {
    @Environment(AppState.self) private var app
    @Environment(\.zoomNamespace) private var zoom
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var engine = CarouselEngine()
    /// Live only while the finger is down, so the drag reads as the photographs moving
    /// rather than as a page that snaps when you let go.
    @State private var dragWidth: CGFloat = 0

    var body: some View {
        // The plate has to reach the bottom of the *display*, not the bottom of the safe
        // area — otherwise the paper sheet below it shows as a 34pt crescent under the tab
        // bar on every launch, which reads as a bug rather than as something to scroll to.
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom

            ZStack(alignment: .top) {
                photographs
                bottomScrim
                topScrim

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        plate(bottomInset: bottomInset)
                            .frame(height: proxy.size.height + bottomInset)
                        sheet
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(!hasSheetContent)
                .tracksTabBarMinimize()
            }
        }
        .background(Color(hex: 0x0A0603))
        // The status bar this screen needs is set by `RootShell`, not here. A
        // `preferredColorScheme` written at this level is inside a `TabView` page, and the
        // preference does not reliably survive back out to the window: it held at launch
        // and was lost the first time the reader came back from another tab, which put
        // dark glyphs over a cave mouth.
        .task {
            app.refreshRecommendation()
            ParkPhotos.shared.prefetchNationalParks()
            engine.fill(from: app.recommender.fix)
            engine.setRunning(true)
        }
        // The rotation is drawn before the phone has said where it is — a fix takes as long
        // as it takes and the screen does not wait for it. When one lands, the distances
        // are filled in rather than the parks being redrawn under the reader.
        .onChange(of: app.recommender.fix.map { "\($0.lat),\($0.lon)" } ?? "") { _, _ in
            engine.refreshDistances(from: app.recommender.fix)
        }
        .onDisappear { engine.setRunning(false) }
        // Photographs animating behind a backgrounded app are photographs of somebody's
        // battery, and at display size they are decoded ones too.
        .onChange(of: scenePhase) { _, phase in
            engine.setRunning(phase == .active)
        }
        .onChange(of: engine.index) { _, _ in
            guard let slide = engine.current else { return }
            // Politely: this fires on its own every few seconds and must never cut across
            // whatever VoiceOver is reading.
            UIAccessibility.post(notification: .announcement, argument: slide.park.name)
        }
    }

    // MARK: Layer 1 — the photographs

    /// The window mounted at once, opacity-driven. A single `Image` swapped in place
    /// cannot cross-fade with itself, and `TabView(.page)` would slide rather than fade
    /// and bring its own dots.
    private var photographs: some View {
        ZStack {
            // The mounted window, not the playlist. Sixty-three layers would all be laid
            // out on every frame; three is what a cross-fade plus a prefetch actually
            // needs — the one going out, the one showing, the one coming next.
            ForEach(engine.mounted) { slide in
                CarouselPhoto(
                    park: slide.park,
                    image: engine.images[slide.park.code],
                    isActive: slide.id == engine.current?.id
                )
            }
        }
        .offset(x: dragWidth * 0.12)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { dragWidth = $0.translation.width }
                .onEnded { value in
                    dragWidth = 0
                    guard abs(value.translation.width) > 44 else { return }
                    engine.advance(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .animation(.snappy(duration: 0.24), value: dragWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engine.current.map { "\($0.park.name). \($0.meta)" } ?? "")
        .accessibilityHint(engine.current.map { "Opens \($0.park.name)" } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if let slide = engine.current { app.openPark(slide.park.code) } }
    }

    // MARK: Layers 2 and 3 — the scrims

    /// Deep, and fixed. It carries the name, the rail and the tab bar over photography
    /// nobody has seen yet, so it is built for the worst picture rather than the average.
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x0A0603, opacity: 0.97), location: 0),
                .init(color: Color(hex: 0x0B0704, opacity: 0.94), location: 0.20),
                .init(color: Color(hex: 0x0D0805, opacity: 0.82), location: 0.32),
                .init(color: Color(hex: 0x100A06, opacity: 0.50), location: 0.48),
                .init(color: Color(hex: 0x140C08, opacity: 0.12), location: 0.66),
                .init(color: Color(hex: 0x140C08, opacity: 0), location: 0.79),
            ],
            startPoint: .bottom, endPoint: .top
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Short, so the status bar reads over anything — plus the one adaptive thing on the
    /// screen. See `CarouselEngine.headerScrimBoost`: the ground under the wordmark
    /// deepens for a bright photograph, and the type itself never changes.
    private var topScrim: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x0C0805, opacity: 0.50), location: 0),
                    .init(color: Color(hex: 0x0C0805, opacity: 0.10), location: 0.16),
                    .init(color: Color(hex: 0x0C0805, opacity: 0), location: 0.28),
                ],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x0C0805, opacity: 0.46), location: 0),
                    .init(color: Color(hex: 0x0C0805, opacity: 0.20), location: 0.10),
                    .init(color: Color(hex: 0x0C0805, opacity: 0), location: 0.22),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(engine.headerScrimBoost)
            .animation(.easeInOut(duration: CarouselEngine.crossfade), value: engine.headerScrimBoost)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Layers 4–6 — the plate

    private func plate(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            header

            CarouselDots(count: engine.slides.count, index: engine.index) { engine.go(to: $0) }
                .padding(.top, 6)

            Spacer(minLength: 20)

            contentColumn
        }
        // The design anchors the column 106pt above the bottom edge. The bar it clears is
        // this app's own, so the number is written as what it is: the bar, its clearance,
        // and whatever the phone reserves under it.
        .padding(.bottom, bottomInset + WP.tabBarHeight + 14)
    }

    /// The wordmark and the one control that was already here. The design asked for a "+"
    /// that starts a trip; this app reaches Discover from this corner and has done since
    /// the fifth tab came out, so the disc stays what it is.
    private var header: some View {
        HStack(spacing: 10) {
            Text("ParkHop")
                .font(WP.displayBold(38))
                .tracking(-0.57)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color(hex: 0xFAF5EC))
                .shadow(color: Color(hex: 0x0A0603, opacity: 0.5), radius: 8, y: 2)

            Spacer(minLength: 0)

            GlassDisc(icon: "magnifyingglass", size: 50) { app.push(.explore) }
                .accessibilityLabel("Explore")
                .accessibilityHint("Every national and state park, to search or browse")
                .zoomSource("explore", in: zoom, clip: .pill(height: 50))
        }
        .frame(minHeight: 52)
        .padding(.horizontal, WP.gutter)
        .padding(.top, WP.headerTop)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let slide = engine.current {
                Button {
                    app.openPark(slide.park.code)
                } label: {
                    Text(slide.park.name)
                        .font(WP.display(52))
                        // Line height 0.96. Cormorant's own leading at 52pt is nearer 1.2,
                        // and a two-word park name set loose reads as two headings.
                        .lineSpacing(-11)
                        .tracking(-0.52)
                        .foregroundStyle(Color(hex: 0xFAF5EC))
                        .shadow(color: Color(hex: 0x0A0603, opacity: 0.40), radius: 10, y: 2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))

                metaRow(slide)
                    .padding(.top, 9)
            }

            // Measured from an anchor that holds still. This used to take the park the
            // carousel happened to be showing, so with no location fix the whole rail
            // re-sorted itself every eight seconds — "parks near you" naming a different
            // three states each time a photograph changed. The phone's fix when there is
            // one; the recommendation, or the first park drawn, when there is not.
            NearbyRail(park: railAnchor)
                .padding(.top, 22)
        }
        .padding(.horizontal, WP.gutter)
        // Deliberately not the photograph's 2.5s. Two photographs dissolving through each
        // other is the effect; two park names doing it is one word printed over another,
        // and at two and a half seconds it stayed that way long enough to read as a fault.
        .animation(.easeInOut(duration: 0.5), value: engine.index)
    }

    private func metaRow(_ slide: CarouselEngine.Slide) -> some View {
        HStack(spacing: 9) {
            Text(slide.meta)
                .font(WP.body(14))
                .foregroundStyle(Color(hex: 0xF7F0E5, opacity: 0.78))

            Rectangle()
                .fill(Color(hex: 0xF7F0E5, opacity: 0.34))
                .frame(width: 1, height: 11)

            Button {
                app.openPark(slide.park.code)
            } label: {
                HStack(spacing: 3) {
                    Text("Open").font(WP.body(14))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0xC9974A))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.97))

            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    /// What the rail measures from — deliberately not the park on screen.
    private var railAnchor: CuratedPark? {
        app.featuredPark ?? engine.slides.first?.park
    }

    // MARK: Below the fold

    /// Whether there is anything under the photograph at all.
    ///
    /// Both of these are conditional — a driving day exists only mid-trip, and the stamp
    /// list only in a park that has some. With neither, the sheet was still drawn: a bare
    /// paper rectangle with 26pt of padding and nothing in it, which appeared as a white
    /// slab sliding up from the bottom of the home screen and read as a rendering fault.
    /// No content, no sheet, and the carousel is simply the whole screen.
    private var hasSheetContent: Bool {
        app.todayLeg != nil || !(app.todayPark?.stamps ?? []).isEmpty
    }

    /// The paper sheet, and everything the redesign had no room for above it. It slides
    /// up over the photograph rather than pushing it away, which is what keeps the
    /// carousel whole at rest.
    @ViewBuilder
    private var sheet: some View {
        if hasSheetContent {
            VStack(alignment: .leading, spacing: 22) {
                if let leg = app.todayLeg {
                    DrivingDayCard(leg: leg)
                }
                StampsNearby()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WP.gutter)
            .padding(.top, 26)
            .padding(.bottom, WP.rootScrollBottom)
            .background {
                WP.bg
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28,
                                                      style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

// MARK: - One photograph in the stack

/// A single carousel layer: the park's colour field, its photograph over it once one
/// arrives, and the slow drift.
///
/// The colour field is not a placeholder — it is what the park looks like before the
/// picture lands and what it goes on looking like if none does. There is no spinner and
/// no grey box, because the screen is never allowed to look empty.
private struct CarouselPhoto: View {
    var park: CuratedPark
    var image: UIImage?
    var isActive: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BlobField(colors: park.c.map { Color(css: $0) }, scrim: false, topLight: false)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // No drift. The photograph is still, and the only thing that ever moves on this
        // screen is one photograph dissolving into the next — nothing creeps under the
        // name while you are reading it.
        .clipped()
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: CarouselEngine.crossfade), value: isActive)
        // A jump down the playlist mounts a layer that was not there a frame ago, and an
        // opacity that was never false cannot animate to true. The transition covers that
        // one case; a normal advance moves between layers already mounted.
        .transition(.opacity)
        .task(id: park.code) { ParkPhotos.shared.load(park) }
    }
}

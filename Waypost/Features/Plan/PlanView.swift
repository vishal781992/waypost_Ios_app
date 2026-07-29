import SwiftUI

/// The Itinerary Desk: pick the parks, the first day and where you set out from.
struct PlanView: View {
    @Environment(TripStore.self) private var store
    @State private var tripFoldOpen = false
    @State private var showingCalendar = false
    @State private var resetArmed = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            AppBar(title: "Waypost", subtitle: "a field planner") {
                EmptyView()
            } trailing: {
                Text(AppVersion.short)
                    .font(WP.body(10))
                    .tnum()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.accent400, lineWidth: 1))
                    .foregroundStyle(WP.accent400)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    tripFold
                    sourceAndSearch
                    if let note = store.sourceNote {
                        Text(note)
                            .font(WP.body(12.5))
                            .italic()
                            .opacity(0.68)
                            .padding(.top, 11)
                    }
                    if !store.order.isEmpty { pickRail.padding(.top, 14) }
                    if let note = store.searchNote {
                        Text(note)
                            .font(WP.body(14))
                            .italic()
                            .opacity(0.62)
                            .padding(.top, 18)
                    }
                    catalog.padding(.top, 10)
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, WP.gutter)
            }
            .scrollDismissesKeyboard(.interactively)

            buildBar
        }
        .background(WP.bg)
        .sheet(isPresented: $showingCalendar) {
            StartDateSheet(date: store.start) { store.setStart($0) }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("The Itinerary Desk".uppercased())
                    .font(WP.body(10.5))
                    .tracking(1.7)
                    .foregroundStyle(Color(hex: 0x2F5C43))
                Text("Plan the parks properly.")
                    .font(WP.heading(34, weight: .regular))
                    .padding(.top, 9)
                Text("Name the parks, the date and where you set out from. Waypost composes the rest — road or air, the day's weather, campsites, permits, and every closure worth knowing.")
                    .font(WP.body(14.5))
                    .lineSpacing(4)
                    .opacity(0.82)
                    .padding(.top, 12)
            }
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The wash bleeds to the screen edge; the text keeps the page gutter.
        .background(HeroWash().padding(.horizontal, -WP.gutter))
    }

    // MARK: The trip fold

    private var tripFold: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { tripFoldOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The trip".uppercased())
                            .font(WP.body(10))
                            .tracking(1.4)
                            .foregroundStyle(WP.accent)
                        Text("\(WPDate.medium(store.start)) · \(store.originCity.name)")
                            .font(WP.body(14.5))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WP.accent700)
                        .rotationEffect(.degrees(tripFoldOpen ? 180 : 0))
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if tripFoldOpen {
                VStack(alignment: .leading, spacing: 16) {
                    field("First day") {
                        Button { showingCalendar = true } label: {
                            HStack {
                                Text(WPDate.medium(store.start)).font(WP.body(15))
                                Spacer()
                                Image(systemName: "calendar").foregroundStyle(WP.accent700)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.divider, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    field("Origin city") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Any U.S. city…", text: Binding(
                                get: { store.originQuery },
                                set: { store.originQueryChanged($0) }
                            ))
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .font(WP.body(15))
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.divider, lineWidth: 1))

                            if !store.originSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(store.originSuggestions) { suggestion in
                                        Button {
                                            store.pickSuggestion(suggestion)
                                        } label: {
                                            Text(suggestion.name)
                                                .font(WP.body(14))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .frame(height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .background(WP.surface)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(WP.divider, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }

                    field("Between stops") {
                        WPSegmented(options: [(TravelMode.drive, "Drive"), (.fly, "Fly when faster")],
                                    selection: $store.mode)
                    }

                    field("Vehicle") {
                        WPSegmented(options: [(Vehicle.gas, "Gas"), (.ev, "Electric")],
                                    selection: $store.vehicle)
                    }

                    Text("\(store.dateSummary) \(store.originNote)")
                        .font(WP.body(12.5))
                        .italic()
                        .opacity(0.62)

                    Hairline()

                    field("Live data") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("https://…/ proxy base", text: Binding(
                                get: { store.proxy.base },
                                set: { store.proxy.base = $0 }
                            ))
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .font(WP.body(15))
                                .padding(.horizontal, 16)
                                .frame(height: 46)
                                .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.divider, lineWidth: 1))

                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                if store.proxy.isConnected { LiveDot() }
                                Text(store.proxy.status)
                                    .font(WP.body(12))
                                    .italic()
                                    .opacity(0.66)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            Hairline()
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(WP.body(11))
                .tracking(1.3)
                .opacity(0.6)
            content()
        }
    }

    // MARK: Source and search

    private var sourceAndSearch: some View {
        @Bindable var store = store

        return VStack(spacing: 11) {
            WPSegmented(
                options: [(ParkSource.nps, "National parks"), (.state, "State parks")],
                selection: Binding(get: { store.parkSource }, set: { store.setParkSource($0) })
            )
            TextField(store.parkSource == .state ? "State park or state…" : "Park name or state…",
                      text: Binding(get: { store.query }, set: { store.queryChanged($0) }))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .font(WP.body(15))
                .padding(.horizontal, 16)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.divider, lineWidth: 1))
        }
        .padding(.top, 18)
    }

    // MARK: Picks

    private var pickRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Route".uppercased())
                    .font(WP.body(10))
                    .tracking(1.4)
                    .opacity(0.5)

                ForEach(Array(store.order.enumerated()), id: \.element) { index, code in
                    let park = store.park(code)
                    HStack(spacing: 7) {
                        Text("\(index + 1)").tnum().opacity(0.75)
                        Text(park?.name ?? code)
                        Button {
                            store.togglePark(code)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.09), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .font(WP.body(13))
                    .padding(.leading, 13)
                    .padding(.trailing, 7)
                    .padding(.vertical, 6)
                    .background(index == 0 ? WP.accent100 : WP.neutral100)
                    .foregroundStyle(index == 0 ? WP.accent800 : WP.neutral800)
                    .clipShape(RoundedRectangle(cornerRadius: 999))
                }

                Button { store.clearPicks() } label: {
                    Text("Clear")
                        .font(WP.body(12.5))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(WP.danger)
                        .background(WP.danger.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 999).stroke(WP.danger.opacity(0.35), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 999))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, WP.gutter)
        }
        .padding(.horizontal, -WP.gutter)
    }

    // MARK: Catalog

    private var catalog: some View {
        LazyVStack(spacing: 0) {
            ForEach(store.catalog) { park in
                ParkRow(
                    park: park,
                    orderNumber: store.order.firstIndex(of: park.code).map { $0 + 1 },
                    days: store.days(for: park.code),
                    onToggle: { store.togglePark(park.code) },
                    onAdjustDays: { store.adjustDays(park.code, by: $0) }
                )
            }
        }
    }

    // MARK: Build bar

    private var buildBar: some View {
        VStack(spacing: 7) {
            Text(store.buildHint)
                .font(WP.body(12.5))
                .italic()
                .opacity(0.6)

            HStack(spacing: 9) {
                Button {
                    searchFocused = false
                    store.buildTrip()
                } label: {
                    VStack(spacing: 1) {
                        Text("Compose the itinerary")
                            .font(WP.heading(21, weight: .regular))
                        Text(store.order.isEmpty ? "awaiting parks" : "\(store.order.count) park\(store.order.count > 1 ? "s" : "") · \(store.totalDays) days")
                            .font(WP.body(12))
                            .italic()
                            .foregroundStyle(WP.accent400)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(store.order.isEmpty ? WP.neutral500 : WP.ink)
                    .foregroundStyle(WP.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 999))
                }
                .buttonStyle(.plain)
                .disabled(store.order.isEmpty)

                Button {
                    // Tap once to arm, again to confirm — a cleared trip cannot be undone.
                    if resetArmed {
                        store.reset()
                        resetArmed = false
                    } else {
                        resetArmed = true
                        Task {
                            try? await Task.sleep(for: .seconds(3.2))
                            resetArmed = false
                        }
                    }
                } label: {
                    Group {
                        if resetArmed {
                            Text("Clear\nit?")
                                .font(WP.body(10))
                                .tracking(0.7)
                                .multilineTextAlignment(.center)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .regular))
                        }
                    }
                    .frame(width: 58, height: 58)
                    .background(WP.ink)
                    .foregroundStyle(WP.bg)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            ZStack {
                CTAWash()
                WP.bg.opacity(0.55)
            }
            .overlay(alignment: .top) { Hairline() }
            // The plate runs under the home indicator so the bar and the indicator read
            // as one edge, as `env(safe-area-inset-bottom)` does on the web. Only the
            // background bleeds — the buttons stay above the indicator.
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// One row on the shelf: state kicker, designation badge, name, tagline, and — once
/// picked — the days stepper.
struct ParkRow: View {
    var park: Park
    var orderNumber: Int?
    var days: Int
    var onToggle: () -> Void
    var onAdjustDays: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(USStates.kicker(park.state).uppercased())
                                .font(WP.body(10))
                                .tracking(1.2)
                                .foregroundStyle(WP.accent)
                            if let badge = park.badge {
                                Tag(text: badge, style: park.isNationalPark ? .accent : .neutral)
                            }
                            Spacer(minLength: 0)
                            if let distance = park.distMi {
                                Text("\(distance) mi").font(WP.body(10)).tnum().opacity(0.45)
                            }
                        }
                        Text(park.name)
                            .font(WP.heading(20, weight: .regular))
                            .multilineTextAlignment(.leading)
                        if !park.tagline.isEmpty {
                            Text(park.tagline)
                                .font(WP.body(12.5))
                                .opacity(0.68)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let orderNumber {
                        Tag(text: "№ \(orderNumber)", style: .accent)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 15))
                            .foregroundStyle(WP.accent700)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(WP.divider, lineWidth: 1))
                    }
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if orderNumber != nil {
                HStack(spacing: 12) {
                    Text("Days in park").font(WP.body(12.5)).opacity(0.62)
                    Spacer()
                    stepButton("minus") { onAdjustDays(-1) }
                    Text("\(days)")
                        .font(WP.heading(22, weight: .regular))
                        .tnum()
                        .frame(minWidth: 22)
                    stepButton("plus") { onAdjustDays(1) }
                }
                .padding(.bottom, 12)
            }
            Hairline()
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(WP.divider, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WP.text)
    }
}

/// The date picker, as a sheet rather than the web app's popover — a sheet is what a
/// phone does, and it keeps the calendar out of the scrolling form.
struct StartDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    var onPick: (Date) -> Void

    var body: some View {
        NavigationStack {
            DatePicker("First day", selection: $date, in: WPDate.today()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("First day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onPick(date); dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A soft wash of blurred organic shapes — the backdrop behind the hero and the call to
/// action. The blobs stay inside the frame so the blur dissolves at every edge; the mask
/// then fades the whole thing into the page rather than ending on a straight line.
struct ColourWash: View {
    struct Blob {
        var color: Color
        /// Position and size as fractions of the frame.
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    var blobs: [Blob]
    var opacity: Double
    var fade: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    Ellipse()
                        .fill(blob.color)
                        .frame(width: blob.width * w, height: blob.height * h)
                        .position(x: blob.x * w, y: blob.y * h)
                }
            }
            .blur(radius: 34)
            .opacity(opacity)
            .mask(
                LinearGradient(colors: fade.map { Color.black.opacity($0) },
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .allowsHitTesting(false)
    }
}

/// The green field wash behind the hero.
struct HeroWash: View {
    var body: some View {
        ColourWash(
            blobs: [
                .init(color: Color(hex: 0x3F7A57), x: 0.20, y: 0.26, width: 0.62, height: 0.72),
                .init(color: Color(hex: 0x7FB07A), x: 0.76, y: 0.20, width: 0.58, height: 0.66),
                .init(color: Color(hex: 0xBFD39A), x: 0.50, y: 0.52, width: 0.52, height: 0.58),
            ],
            opacity: 0.55,
            fade: [0.55, 0.35, 0.0]
        )
    }
}

/// The cooler dusk wash behind the bottom call to action.
struct CTAWash: View {
    var body: some View {
        ColourWash(
            blobs: [
                .init(color: Color(hex: 0x4A6480), x: 0.18, y: 0.78, width: 0.58, height: 1.5),
                .init(color: Color(hex: 0x8AA3BC), x: 0.52, y: 0.86, width: 0.52, height: 1.3),
                .init(color: Color(hex: 0xE3B06A), x: 0.88, y: 0.82, width: 0.5, height: 1.1),
            ],
            opacity: 0.32,
            fade: [0.0, 0.5, 0.8]
        )
    }
}

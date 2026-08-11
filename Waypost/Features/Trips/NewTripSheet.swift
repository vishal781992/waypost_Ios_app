import SwiftUI
import CoreLocation

/// The three-step new-trip flow: which parks, when and from where, then review — and a
/// composing screen that says what it is working out.
struct NewTripSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var builder: TripBuilder

    /// The origin field's own text. It is not the builder's, because clearing it must not
    /// clear the city already chosen.
    @State private var originQuery = ""
    @State private var cities = CitySearch()
    @State private var locatingOrigin = false
    @State private var showDatePicker = false
    @FocusState private var parkFieldFocused: Bool
    @FocusState private var originFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if builder.composing {
                composing
            } else {
                Group {
                    switch builder.step {
                    case 1: stepParks
                    case 2: stepWhen
                    default: stepReview
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
        }
        // Softened while the calendar is open. The date sheet frosts its own panel, but the
        // form above it stayed perfectly sharp — a field label and a stepper sitting in full
        // focus directly above the month you are trying to read. Blurring the page behind
        // leaves one thing on screen to look at.
        //
        // Before `.background`, so the blur has an opaque page to soften against rather than
        // bleeding transparent at the edges.
        .blur(radius: showDatePicker ? 4 : 0)
        .animation(.easeOut(duration: 0.28), value: showDatePicker)
        .background(WP.bg)
        .presentationDetents([.large])
        .presentationCornerRadius(WP.sheetCorner)
        .presentationDragIndicator(.visible)
        .onChange(of: app.directory.hits) { _, _ in app.refreshBuilderResults() }
        .onChange(of: app.directory.phase) { _, _ in app.refreshBuilderResults() }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if builder.step > 1 {
                        withAnimation(.snappy(duration: 0.22)) { builder.step -= 1 }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(builder.step > 1 ? "Back" : "Cancel")
                        .font(WP.body(19))
                        .foregroundStyle(WP.accent700)
                        .frame(minHeight: 44, alignment: .center)
                }
                .buttonStyle(PressStyle(scale: 0.94))

                Spacer(minLength: 0)
                Text(builder.stepLabel.uppercased())
                    .font(WP.body(10)).tracking(1.4).opacity(0.55)
                Spacer(minLength: 0)

                // The same disc the home screen and the search sheet use, at the size
                // every other round control in the app is.
                GlassDisc(icon: "xmark", size: 44) { dismiss() }
                    .accessibilityLabel("Cancel")
                    // Out of the page gutter and into the corner's own centre. Negative,
                    // because the gutter is applied to the header as a whole and this one
                    // control has to sit closer to the edge than the text does.
                    .padding(.trailing, WP.sheetCloseInset(for: 44) - WP.gutter)
            }

            Text(builder.heading).font(WP.display(32)).padding(.top, 9)
            Text(builder.subtitle).font(WP.body(12.5)).lineSpacing(2).opacity(0.7).padding(.top, 5)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, WP.sheetCloseInset(for: 44))
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if builder.step == 1 {
                Text(builder.pickNote).font(WP.bodyItalic(11.5)).opacity(0.6)
            }
            // 48 rather than 52, and sitting lower: the footer was giving up about a row
            // and a half of results to padding that the home indicator's own clearance was
            // already providing underneath it. Still well clear of the 44pt minimum.
            GlowButton(title: builder.nextLabel, minHeight: 48) {
                advance()
            }
            .opacity(builder.isNextDisabled ? 0.45 : 1)
            .disabled(builder.isNextDisabled)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 9)
        // Negative, to sit down inside the home indicator's safe area rather than stacking
        // padding on top of it. The indicator still has its own clearance underneath, and
        // what this reclaims goes to the list.
        .padding(.bottom, -12)
        .background(WP.bg.opacity(0.92).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    private func advance() {
        if builder.step < 3 {
            withAnimation(.snappy(duration: 0.22)) { builder.step += 1 }
            return
        }
        compose()
    }

    /// What answered, and whether anything is still coming — the same line Discover
    /// carries, so a search that is merely slow does not read as a search that failed.
    private var searchNote: String {
        let count = builder.results.count
        switch app.directory.phase {
        case .searching:
            return "\(count) so far · still looking"
        case .unanswered(let why):
            return why
        case .idle, .ready:
            let sources = app.directory.answered.map(\.rawValue).sorted().joined(separator: " · ")
            return sources.isEmpty
                ? "\(count) \(count == 1 ? "park" : "parks")"
                : "\(count) \(count == 1 ? "park" : "parks") · \(sources)"
        }
    }

    // MARK: Step 1 — parks

    private var stepParks: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("A state, a city, or a park…", text: $builder.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(WP.body(16))
                    .padding(.horizontal, 15)
                    .frame(minHeight: 46)
                    .background(WP.neutral200, in: Capsule())
                    .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
                    .focused($parkFieldFocused)
                    .searchFieldSurface(focus: $parkFieldFocused)

                if !builder.picks.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(Array(builder.picks.enumerated()), id: \.element) { index, code in
                                pickChip(code: code, index: index)
                            }
                        }
                        .padding(.horizontal, WP.gutter)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -WP.gutter)
                    .padding(.top, 11)
                }
            }
            .padding(.horizontal, WP.gutter)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if !builder.query.isEmpty {
                        HStack(spacing: 6) {
                            Text(searchNote)
                                .font(WP.bodyItalic(11.5)).opacity(0.6)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, WP.gutter)
                        .padding(.bottom, 6)
                    }

                    ForEach(builder.results) { park in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { builder.toggle(park.code) }
                            Haptics.tap()
                        } label: {
                            DividedRow(vertical: 12) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(park.stateName.uppercased())
                                                .font(WP.body(10)).tracking(1.4)
                                                .foregroundStyle(WP.accent)
                                            Text(park.designationLabel.uppercased())
                                                .font(WP.body(10)).tracking(1.4).opacity(0.4)
                                        }
                                        Text(park.name).font(WP.rowTitle(18))
                                        Text(park.tag).font(WP.body(12)).opacity(0.62).lineSpacing(1)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    if let index = builder.picks.firstIndex(of: park.code) {
                                        Text("\(index + 1)")
                                            .font(WP.headingUI(14))
                                            .foregroundStyle(.white)
                                            .frame(width: 44, height: 44)
                                            .background(WP.accent, in: Circle())
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14))
                                            .foregroundStyle(WP.accent700)
                                            .frame(width: 44, height: 44)
                                            .overlay(Circle().stroke(WP.divider, lineWidth: 1))
                                    }
                                }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .padding(.horizontal, WP.gutter)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// A picked park: its place in the order, its name, and a way to drop it.
    ///
    /// The nights in each park were also set here, on a stepper inside the chip — the same
    /// question the next step asks in full, on a labelled row with room to read it. Asking
    /// twice meant the two could disagree, and the chip's copy was the one nobody saw
    /// again. Step one picks the parks; step two says how long in each.
    private func pickChip(code: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(WP.headingUI(13))
            Text(app.park(code)?.name ?? code).font(WP.body(12.5)).lineLimit(1)
            Button {
                withAnimation(.snappy(duration: 0.2)) { builder.toggle(code) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.7)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(WP.accent100, in: Capsule())
        .foregroundStyle(WP.accent800)
    }

    // MARK: Step 2 — where the trip starts

    /// Any city in the country, not the six in `curated.json`. Two characters bring the
    /// matches down; with the field empty the shipped six stay as one-tap shortcuts, and a
    /// city already chosen by search sits above them so it can be seen and re-picked.
    @ViewBuilder
    private var originField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Setting out from")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold)).opacity(0.45)
                TextField("Type a city, or use your location", text: $originQuery)
                    .font(WP.body(15))
                    .foregroundStyle(WP.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($originFocused)
                if cities.isResolving {
                    ProgressView().controlSize(.small)
                } else if !originQuery.isEmpty {
                    Button {
                        originQuery = ""
                        cities.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).opacity(0.4)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the city")
                }
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .background(WP.neutral200, in: Capsule())
            .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
            .searchFieldSurface(focus: $originFocused)
            .onChange(of: originQuery) { _, new in cities.update(new) }

            Grouped {
                if !cities.matches.isEmpty {
                    ForEach(Array(cities.matches.enumerated()), id: \.element.id) { index, match in
                        originRow(title: match.city,
                                  trailing: match.state,
                                  isChosen: builder.pickedOrigin?.name == "\(match.city), \(match.state)") {
                            Task {
                                if let origin = await cities.resolve(match) {
                                    builder.pickedOrigin = origin
                                    originQuery = ""
                                    cities.clear()
                                    Haptics.tap()
                                } else {
                                    app.show("That city could not be placed on the map")
                                }
                            }
                        }
                        if index < cities.matches.count - 1 { Hairline() }
                    }
                } else {
                    // Your own location, first — the six shipped cities were nobody's home.
                    Button {
                        useCurrentLocation()
                    } label: {
                        HStack(spacing: 10) {
                            if locatingOrigin {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WP.accent)
                            }
                            Text("Use current location").font(WP.body(14))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.995))
                    .disabled(locatingOrigin)

                    // A chosen city sits under it, so the selection stays visible.
                    if let picked = builder.pickedOrigin {
                        Hairline()
                        originRow(title: picked.name, trailing: "", isChosen: true) {}
                    }
                }
            }

            if originQuery.count == 1 {
                Text("One more character and the cities appear.")
                    .font(WP.bodyItalic(11.5)).opacity(0.55)
            } else if originQuery.count >= 2 && cities.matches.isEmpty {
                Text("No US city by that name yet — keep typing.")
                    .font(WP.bodyItalic(11.5)).opacity(0.55)
            }
        }
    }

    /// Sets the origin to where the phone is, named by the city it sits in.
    private func useCurrentLocation() {
        locatingOrigin = true
        Task {
            defer { locatingOrigin = false }
            guard let fix = await LocationService.shared.currentFix() else {
                app.show("Location is off — turn it on, or type a city")
                return
            }
            // A device fix carries no place name, so the coordinates are turned into a city
            // the way the rest of the origins read — "Dallas, TX" rather than "Where you
            // are". The routing uses the coordinates either way; this is what the row says.
            var name = [fix.city, fix.region].compactMap { $0 }.joined(separator: ", ")
            if name.isEmpty { name = await Self.cityName(lat: fix.lat, lon: fix.lon) }
            builder.pickedOrigin = TripOrigin(name: name, lat: fix.lat, lon: fix.lon)
            originQuery = ""
            cities.clear()
            Haptics.tap()
        }
    }

    private static func cityName(lat: Double, lon: Double) async -> String {
        let placemarks = try? await CLGeocoder()
            .reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
        guard let place = placemarks?.first else { return "Where you are" }
        let city = place.locality ?? place.subAdministrativeArea
        let joined = [city, place.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        return joined.isEmpty ? "Where you are" : joined
    }

    private func originRow(title: String, trailing: String, isChosen: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(WP.body(14)).lineLimit(1)
                Spacer(minLength: 0)
                if !trailing.isEmpty {
                    Text(trailing).font(WP.mono(11)).tracking(1.8)
                        .foregroundStyle(WP.accent800).opacity(0.7)
                }
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WP.accent)
                } else {
                    Color.clear.frame(width: 15, height: 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.995))
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    // MARK: Step 2 — when and from where

    private var stepWhen: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("First day")
                    // The whole bar opens the calendar, not just a small date capsule — a
                    // `.compact` DatePicker only makes its own label tappable. A light bar
                    // with dark text rather than dark glass, so the date reads at all.
                    Button { showDatePicker = true } label: {
                        HStack {
                            Text(builder.startLabel).font(WP.body(15)).foregroundStyle(WP.text)
                            Spacer(minLength: 0)
                            Image(systemName: "calendar").foregroundStyle(WP.accent700)
                        }
                        .padding(.horizontal, 15)
                        .frame(minHeight: 46)
                        .background(WP.neutral200, in: Capsule())
                        .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                    .sheet(isPresented: $showDatePicker) {
                        // A sheet, not a popover: the graphical calendar needs the full
                        // width, which an iPhone popover does not give it. It closes as soon
                        // as a day is chosen.
                        VStack(spacing: 0) {
                            DatePicker("First day",
                                       selection: $builder.startDate,
                                       in: Calendar.current.startOfDay(for: Date())...,
                                       displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                                .tint(WP.accent)
                                .padding(.horizontal, WP.gutter)
                                .onChange(of: builder.startDate) { _, _ in showDatePicker = false }
                        }
                        .padding(.top, 8)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                        // Frosted, not the default thin backing. This sheet opens on top of
                        // another sheet, and the form underneath was showing through hard
                        // enough to read — stray field labels and capsule edges cutting
                        // between the calendar's own rows. Thick material puts the page
                        // behind it out of focus properly, so the only thing in focus is
                        // the month being chosen.
                        .presentationBackground(.thickMaterial)
                        .presentationCornerRadius(WP.sheetCorner)
                    }
                }

                daysField

                originField

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Between stops")
                    SegmentedTrough(
                        options: [(false, "Drive"), (true, "Fly when faster")],
                        selection: $builder.flyWhenFaster
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Vehicle")
                    SegmentedTrough(
                        options: [(false, "Gasoline"), (true, "Electric")],
                        selection: $builder.vehicleIsElectric
                    )
                    Text("Electric adds fast-charge stops to every leg and to the day plans.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55)
                }
            }
            .padding(.horizontal, WP.gutter)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// How many days to spend in each picked park, on the same screen as the date.
    ///
    /// The stepper already exists on step 1's chips, but "Plan a trip here" seeds one park
    /// and jumps straight here, so that control was never seen for the common single-park
    /// case. Same builder API (`days(for:)` / `adjustDays`), so the count flows into
    /// `totalDays`, the "N days in the parks" progress line, and the review's "Days afield".
    private var daysField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(builder.picks.count == 1 ? "Days in the park" : "Days in each park")
            VStack(spacing: 8) {
                ForEach(builder.picks, id: \.self) { code in
                    HStack(spacing: 10) {
                        Text(app.park(code)?.name ?? code)
                            .font(WP.body(15)).foregroundStyle(WP.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { builder.adjustDays(code, by: -1) }
                        } label: {
                            Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(Color.black.opacity(0.07), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(WP.accent700)
                        .disabled(builder.days(for: code) <= 1)
                        Text("\(builder.days(for: code))")
                            .font(WP.headingUI(15)).foregroundStyle(WP.text)
                            .frame(minWidth: 16)
                            .contentTransition(.numericText())
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { builder.adjustDays(code, by: 1) }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(Color.black.opacity(0.07), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(WP.accent700)
                        .disabled(builder.days(for: code) >= 9)
                    }
                    .padding(.horizontal, 15)
                    .frame(minHeight: 46)
                    .background(WP.neutral200, in: Capsule())
                    .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(WP.body(11)).tracking(1.3).opacity(0.6)
    }

    // MARK: Step 3 — review

    private var stepReview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Hairline()
                ForEach(builder.reviewRows, id: \.label) { row in
                    DividedRow(vertical: 11) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.label.uppercased())
                                .font(WP.body(11)).tracking(1.3).opacity(0.55)
                                .frame(width: 110, alignment: .leading)
                            Text(row.value).font(WP.body(13.5)).lineSpacing(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                Text("ParkHop will size an offline pack for each park and watch the permit windows for these dates.")
                    .font(WP.bodyItalic(12)).opacity(0.6).lineSpacing(3).padding(.top, 14)
            }
            .padding(.horizontal, WP.gutter)
            .padding(.top, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Composing

    private var composing: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Kicker(text: "Composing")
            Text("Working out the order of things.")
                .font(WP.heading(25)).padding(.top, 8).padding(.bottom, 18)

            ProgressTrack(fraction: builder.composeProgress)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(TripBuilder.composeSteps.enumerated()), id: \.element) { index, step in
                    let reached = builder.composeProgress >= Double(index) / Double(TripBuilder.composeSteps.count)
                    HStack(spacing: 10) {
                        Circle()
                            .fill(reached ? WP.accent : WP.neutral300)
                            .frame(width: 8, height: 8)
                        Text(step).font(WP.body(13))
                    }
                    .opacity(reached ? 1 : 0.4)
                    .animation(.easeOut(duration: 0.3), value: reached)
                }
            }
            .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.bottom, 60)
    }

    private func compose() {
        builder.composing = true
        Task {
            for step in 1...TripBuilder.composeSteps.count {
                try? await Task.sleep(for: .milliseconds(340))
                withAnimation(.easeOut(duration: 0.3)) {
                    builder.composeProgress = Double(step) / Double(TripBuilder.composeSteps.count)
                }
            }
            try? await Task.sleep(for: .milliseconds(260))
            Haptics.success()
            app.finishBuilder()
            dismiss()
        }
    }
}

import SwiftUI

/// The three-step new-trip flow: which parks, when and from where, then review — and a
/// composing screen that says what it is working out.
struct NewTripSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var builder: TripBuilder

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
        .background(WP.bg)
        .presentationDetents([.large])
        .presentationCornerRadius(22)
        .presentationDragIndicator(.visible)
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
                        .font(WP.body(14.5))
                        .foregroundStyle(WP.accent700)
                }
                .buttonStyle(PressStyle(scale: 0.94))

                Spacer(minLength: 0)
                Text(builder.stepLabel.uppercased())
                    .font(WP.body(10)).tracking(1.4).opacity(0.55)
                Spacer(minLength: 0)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WP.neutral700)
                        .frame(width: 30, height: 30)
                        .background(WP.neutral200, in: Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
            }

            Text(builder.heading).font(WP.heading(27)).padding(.top, 9)
            Text(builder.subtitle).font(WP.body(12.5)).lineSpacing(2).opacity(0.7).padding(.top, 5)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if builder.step == 1 {
                Text(builder.pickNote).font(WP.bodyItalic(11.5)).opacity(0.6)
            }
            GlowButton(title: builder.nextLabel, minHeight: 52) {
                advance()
            }
            .opacity(builder.isNextDisabled ? 0.45 : 1)
            .disabled(builder.isNextDisabled)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 11)
        .padding(.bottom, 18)
        .background(WP.bg.opacity(0.92))
        .overlay(alignment: .top) { Hairline() }
    }

    private func advance() {
        if builder.step < 3 {
            withAnimation(.snappy(duration: 0.22)) { builder.step += 1 }
            return
        }
        compose()
    }

    // MARK: Step 1 — parks

    private var stepParks: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search parks…", text: $builder.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(WP.body(16))
                    .padding(.horizontal, 15)
                    .frame(minHeight: 40)
                    .background(WP.neutral200, in: Capsule())
                    .overlay(Capsule().stroke(WP.divider, lineWidth: 1))

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
                    ForEach(builder.results) { park in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { builder.toggle(park.code) }
                            Haptics.tap()
                        } label: {
                            DividedRow(vertical: 12) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(park.state.uppercased())
                                                .font(WP.body(10)).tracking(1.4)
                                                .foregroundStyle(WP.accent)
                                            Text(park.region.uppercased())
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
                                            .frame(width: 32, height: 32)
                                            .background(WP.accent, in: Circle())
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14))
                                            .foregroundStyle(WP.accent700)
                                            .frame(width: 32, height: 32)
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

    private func pickChip(code: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(WP.headingUI(13))
            Text(app.library.park(code)?.name ?? code).font(WP.body(12.5)).lineLimit(1)
            Button { builder.adjustDays(code, by: -1) } label: {
                Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            Text("\(builder.days(for: code))").font(WP.headingUI(13)).frame(minWidth: 9)
            Button { builder.adjustDays(code, by: 1) } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
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

    // MARK: Step 2 — when and from where

    private var stepWhen: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("First day")
                    Button { builder.cycleStart() } label: {
                        HStack {
                            Text(builder.startLabel).font(WP.body(15))
                            Spacer(minLength: 0)
                            Image(systemName: "calendar")
                        }
                        .padding(.horizontal, 17)
                        .frame(minHeight: 46)
                        .glassControl(shadow: false)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                    Text("Tap to cycle candidate weeks — the wheel picker lands with the live re-wire.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55)
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Setting out from")
                    Grouped {
                        ForEach(Array(app.library.cities.enumerated()), id: \.element.id) { index, city in
                            Button {
                                builder.origin = city.id
                                Haptics.tap()
                            } label: {
                                HStack(spacing: 10) {
                                    Text(city.name).font(WP.body(14))
                                    Spacer(minLength: 0)
                                    Text(city.air).font(WP.mono(11)).tracking(1.8)
                                        .foregroundStyle(WP.accent800).opacity(0.7)
                                    if builder.origin == city.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(WP.accent)
                                    } else {
                                        Color.clear.frame(width: 15, height: 1)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(scale: 0.995))
                            if index < app.library.cities.count - 1 { Hairline() }
                        }
                    }
                }

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

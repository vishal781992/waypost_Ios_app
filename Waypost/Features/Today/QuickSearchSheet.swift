import SwiftUI

/// The search behind the `+` on the home screen.
///
/// The button used to do one thing — start a trip — which is a lot to ask of somebody who
/// has just opened the app and is wondering what is near Moab. It now opens this: one
/// field that takes a state, a city or a park, the same suggestions and the same live
/// directory the Discover screen uses, and a row for each answer that opens the park.
///
/// Starting a trip is still here, at the bottom, where it is one tap rather than the only
/// tap.
struct QuickSearchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    @State private var query = ""

    /// Pre-filled when the app was launched straight into this sheet to be photographed.
    private var launchedQuery: String? {
        Capture.argument("wpFind").flatMap { $0 == "1" ? nil : $0 }
    }

    private var suggestions: [SearchSuggestions.Suggestion] { app.suggestions.items }
    private var results: [ParkDirectory.Hit] { app.directory.hits }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            TextField("A state, a city, or a park…", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .font(WP.body(16))
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .liquidGlass(.pill, radius: 999)
                .shadow(color: Color(hex: 0x181008, opacity: 0.06), radius: 10, y: 4)
                .focused($focused)
                .submitLabel(.search)
                .padding(.horizontal, WP.gutter)
                .onChange(of: query) { _, new in
                    app.suggestions.update(new)
                    app.directory.search(new)
                }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        nearYou
                    }

                    if !suggestions.isEmpty, results.isEmpty {
                        SuggestionList(items: suggestions) { suggestion in
                            query = suggestion.query
                            focused = false
                        }
                        .padding(.top, 10)
                    }

                    if !results.isEmpty {
                        Text(note)
                            .font(WP.bodyItalic(12)).opacity(0.6)
                            .padding(.top, 14).padding(.bottom, 4)

                        ForEach(results.prefix(24)) { hit in
                            row(hit)
                        }
                    } else if query.count >= 2, case .searching = app.directory.phase {
                        Text("Looking…")
                            .font(WP.bodyItalic(12.5)).opacity(0.55)
                            .padding(.top, 18)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            GlowButton(title: "Plan a trip instead", minHeight: 50) {
                dismiss()
                app.startBuilder()
            }
            .padding(.horizontal, WP.gutter)
            .padding(.bottom, 8)
        }
        .background(WP.bg)
        .onAppear {
            if let launchedQuery, query.isEmpty { query = launchedQuery }
            focused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Kicker(text: "Sixty-two on the phone")
                    Text("Find a park")
                        .font(WP.display(38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 12)
                // The same disc as the `+` that opened this: same size, same glass, the
                // two ends of one gesture.
                GlassDisc(icon: "xmark") { dismiss() }
                    .accessibilityLabel("Close")
            }

            Text("A state, a city, or a name. The national parks answer instantly; everything else comes from Apple Maps and OpenStreetMap.")
                .font(WP.body(13)).opacity(0.6).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.trailing, 24)
        }
        .padding(.horizontal, WP.gutter)
        // Below the drag indicator rather than under it: a sheet that starts at the very
        // top reads as a page that was cut off.
        .padding(.top, 34)
        .padding(.bottom, 18)
    }

    /// What is closest, before a word has been typed.
    ///
    /// The sheet used to open on a blank page under a field, which is a question with no
    /// hint at the answer. These come from the list on the phone, measured from the same
    /// fix the home screen uses, so they need no network and appear with the sheet.
    @ViewBuilder
    private var nearYou: some View {
        let fix = app.recommender.fix
        let parks = fix.map { NationalParks.near(lat: $0.lat, lon: $0.lon, limit: 6) } ?? []

        if !parks.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(WP.accent700)
                Text((app.recommender.placeName.map { "Nearest to \($0)" } ?? "Nearest to you").uppercased())
                    .font(WP.body(10)).tracking(1.4).opacity(0.55)
                Rectangle().fill(WP.divider).frame(height: 1)
            }
            .padding(.top, 22)
            .padding(.bottom, 6)

            ForEach(parks, id: \.park.code) { entry in
                let park = CuratedPark(bundled: entry.park)
                Button {
                    dismiss()
                    app.openPark(park.code)
                } label: {
                    DividedRow(vertical: 12) {
                        HStack(spacing: 12) {
                            ParkImage(park: park, showsScrim: false, topLight: false)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(park.name).font(WP.rowTitle(16))
                                Text([park.state, park.designationLabel]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(WP.body(11.5)).opacity(0.6)
                            }
                            Spacer(minLength: 0)
                            Text("\(entry.miles) mi").font(WP.body(11.5)).opacity(0.55).tnum()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WP.accent700)
                        }
                    }
                }
                .buttonStyle(PressStyle(scale: 0.995))
            }
        }
    }

    private var note: String {
        let sources = app.directory.answered.map(\.rawValue).sorted().joined(separator: " · ")
        let count = min(results.count, 24)
        return "\(count) \(count == 1 ? "park" : "parks")" + (sources.isEmpty ? "" : " · \(sources)")
    }

    private func row(_ hit: ParkDirectory.Hit) -> some View {
        Button {
            dismiss()
            app.openPark(hit.park.code)
        } label: {
            DividedRow(vertical: 12) {
                HStack(spacing: 12) {
                    // No blur here. Seven points of it reads as texture behind a name on
                    // a 200-point tile and as a smear of colour on a 44-point one — at
                    // this size the photograph has to be the photograph.
                    ParkImage(park: hit.park, showsScrim: false, topLight: false)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.park.name)
                            .font(WP.rowTitle(16))
                            .multilineTextAlignment(.leading)
                        Text([hit.park.state, hit.park.designationLabel]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(WP.body(11.5)).opacity(0.6)
                    }
                    Spacer(minLength: 0)
                    if let miles = hit.miles {
                        Text("\(miles) mi").font(WP.body(11.5)).opacity(0.55).tnum()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WP.accent700)
                }
            }
        }
        .buttonStyle(PressStyle(scale: 0.995))
    }
}

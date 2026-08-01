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
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .liquidGlass(.pill, radius: 999)
                .focused($focused)
                .submitLabel(.search)
                .padding(.horizontal, WP.gutter)
                .onChange(of: query) { _, new in
                    app.suggestions.update(new)
                    app.directory.search(new)
                }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Find a park").font(WP.display(28))
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .glassControl(shadow: false)
                }
                .buttonStyle(PressStyle(scale: 0.92))
            }
            Text("By state, by city, or by name — sixty-two national parks are on the phone, the rest comes from Apple Maps and OpenStreetMap.")
                .font(WP.body(12.5)).opacity(0.62).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 18)
        .padding(.bottom, 12)
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

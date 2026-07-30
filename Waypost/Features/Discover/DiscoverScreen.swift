import SwiftUI

/// Discover — the catalogue, one park at a time, each carrying its own colour.
struct DiscoverScreen: View {
    @Environment(AppState.self) private var app

    private let chips: [(id: String, label: String)] = [
        ("all", "Everything"), ("Desert", "Desert"), ("Alpine", "Alpine"),
        ("Coast", "Coast"), ("Geothermal", "Geothermal"), ("quiet", "Quieter"),
    ]

    private var results: [CuratedPark] {
        var list = app.library.orderedParks
        if app.discoverChip == "quiet" {
            list = list.filter { $0.crowd.contains("Quiet") || $0.crowd.contains("Moderate") }
        } else if app.discoverChip != "all" {
            list = list.filter { $0.region == app.discoverChip }
        }
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { ($0.name + " " + $0.state + " " + $0.tag).lowercased().contains(q) }
        }
        return list
    }

    private var note: String {
        let count = results.count
        let q = app.discoverQuery.trimmingCharacters(in: .whitespaces)
        let tail: String
        if !q.isEmpty { tail = "matching “\(q)”" }
        else if app.discoverChip == "all" { tail = "all of them, alphabetical by nothing in particular" }
        else { tail = app.discoverChip.lowercased() + " country" }
        return "\(count) \(count == 1 ? "park" : "parks") · \(tail)"
    }

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                Text("Sixty-three parks, one at a time").kickerStyle()
                Text("Discover").font(WP.heading(31)).padding(.top, 4).padding(.bottom, 10)

                TextField("Park or state…", text: $app.discoverQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(WP.body(16))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .liquidGlass(.pill, radius: 999)

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(chips, id: \.id) { chip in
                            let active = app.discoverChip == chip.id
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { app.discoverChip = chip.id }
                            } label: {
                                Text(chip.label)
                                    .font(WP.body(12.5))
                                    .padding(.horizontal, 15)
                                    .frame(minHeight: 34)
                                    .foregroundStyle(active ? WP.bg : WP.text)
                                    .background {
                                        if active {
                                            Capsule().fill(WP.ink)
                                        } else {
                                            Capsule().fill(.clear).liquidGlass(.pill, radius: 999)
                                        }
                                    }
                            }
                            .buttonStyle(PressStyle(scale: 0.96))
                        }
                    }
                    .padding(.horizontal, WP.gutter)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, -WP.gutter)
                .padding(.top, 10)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    // What is actually within reach today, before the catalogue.
                    NearbyCard()

                    Text(note).font(WP.bodyItalic(12)).opacity(0.6)

                    ForEach(results) { park in
                        DiscoverCard(park: park)
                    }

                    if results.isEmpty {
                        Text("Nothing by that name. The full catalogue is 63 parks and 470 units — this pass carries eight.")
                            .font(WP.bodyItalic(14))
                            .opacity(0.6)
                            .padding(.top, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 14)
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct DiscoverCard: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark

    private var isSaved: Bool { app.saved.contains(park.code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.openPark(park.code)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    BlobField(colors: park.c.map { Color(css: $0) })

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(park.state) · \(park.region)".uppercased())
                            .font(WP.body(9)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.88))
                        Text(park.name)
                            .font(WP.parkDisplay(28))
                            .foregroundStyle(.white)
                            .shadow(color: Color(hex: 0x181008, opacity: 0.26), radius: 9, y: 1)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(.onPhoto, radius: 16)
                    .padding(9)
                }
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x1E1208, opacity: 0.18), radius: 15, y: 12)
            }
            .buttonStyle(PressStyle(scale: 0.995))

            Text(park.tag)
                .font(WP.body(13))
                .lineSpacing(2)
                .opacity(0.82)
                .multilineTextAlignment(.leading)
                .padding(.top, 9)

            HStack(spacing: 10) {
                Text("\(park.fee) · \(park.wx.hi)° in August")
                    .font(WP.body(11.5)).opacity(0.6).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    app.toggleSaved(park.code)
                } label: {
                    Text(isSaved ? "Saved" : "Save")
                        .font(WP.headingUI(13))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .foregroundStyle(isSaved ? WP.accent800 : WP.text)
                        .background {
                            if isSaved { Capsule().fill(WP.accent100) }
                            else { Capsule().fill(.clear).liquidGlass(.pill, radius: 999) }
                        }
                }
                .buttonStyle(PressStyle(scale: 0.96))
            }
            .padding(.top, 9)
        }
    }
}

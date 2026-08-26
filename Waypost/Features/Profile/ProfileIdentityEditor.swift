import SwiftUI

/// Who this phone belongs to, as far as the app is concerned.
///
/// There is no account — nothing to fetch a name from and nothing to download a picture
/// from — so both are typed here and kept here, beside the trips and the stamps. That is
/// not a stopgap: a profile that reports what the phone actually holds is the same honesty
/// the rest of the app keeps, and a name nobody entered would be the invented value this
/// app refuses everywhere else.
struct ProfileIdentityEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @FocusState private var nameFocused: Bool

    /// Strictly emoji, by construction rather than by validation.
    ///
    /// iOS has no emoji-only keyboard an app may ask for. The emoji key belongs to whoever
    /// is typing, and a field that accepted every character and then threw most of them
    /// away would be a field that argues with them. A grid cannot be typed into wrongly:
    /// every square in it is an emoji, so "strictly emoji" is a property of the control
    /// rather than a rule it enforces afterwards.
    ///
    /// Chosen for this app rather than gathered at random: mountains, roads, weather,
    /// animals and the gear you carry. Sixty of them is a screen, not a catalogue.
    private static let emoji: [String] = [
        "🏔️", "⛰️", "🌋", "🗻", "🏕️", "⛺️", "🌲", "🌳", "🌵", "🍁",
        "🌾", "🏜️", "🏞️", "🌄", "🌅", "🌊", "🏝️", "🪵", "🪨", "🧭",
        "🗺️", "🥾", "🎒", "🔦", "🔥", "⛽️", "🚐", "🚙", "🛻", "🏍️",
        "🚵", "🧗", "🛶", "⛵️", "🏄", "🎣", "📷", "🕶️", "🌡️", "❄️",
        "☔️", "🌈", "🌙", "⭐️", "🌞", "🦌", "🦬", "🐻", "🦅", "🦉",
        "🐺", "🦊", "🐿️", "🐾", "🐢", "🦩", "🐠", "🌸", "🍄", "🪺",
    ]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your name".uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.5)
                        .padding(.bottom, 8)

                    TextField("Not set", text: $typed)
                        .font(WP.body(16))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                        .padding(.horizontal, 15)
                        .frame(minHeight: 48)
                        .searchFieldSurface(focus: $nameFocused)

                    Text("Kept on this phone with everything else. Nothing is sent anywhere.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        Text("Your emoji".uppercased())
                            .font(WP.body(10)).tracking(1.4).opacity(0.5)
                        Rectangle().fill(WP.divider).frame(height: 1)
                        if app.profileEmoji != nil {
                            Button("Clear") {
                                app.profileEmoji = nil
                                app.persist()
                                Haptics.tap()
                            }
                            .font(WP.headingUI(12.5))
                            .foregroundStyle(WP.accent700)
                        }
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 10)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Self.emoji, id: \.self) { glyph in
                            square(glyph)
                        }
                    }

                    Text("Without one, the circle carries the initials of the last two parks you stood in.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(2)
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(WP.bg)
        .onAppear { typed = app.profileName ?? "" }
        .onDisappear { commitName() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ParkHop · a field planner").kickerStyle()
                Text("You").font(WP.displayBold(38)).tracking(-0.4).padding(.top, 2)
            }
            Spacer(minLength: 0)
            GlassDisc(icon: "xmark", size: 44) {
                commitName()
                dismiss()
            }
            .accessibilityLabel("Done")
            .padding(.top, 2)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    /// One emoji, at a size a thumb can hit and an eye can read.
    private func square(_ glyph: String) -> some View {
        let picked = app.profileEmoji == glyph
        return Button {
            app.profileEmoji = glyph
            app.persist()
            Haptics.tap()
        } label: {
            Text(glyph)
                .font(.system(size: 26))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(picked ? WP.accent100 : WP.neutral100.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(picked ? WP.accent : WP.divider, lineWidth: picked ? 1.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(picked ? "\(glyph), chosen" : glyph)
    }

    /// Trimmed, capped, and emptied back to nothing rather than kept as spaces.
    private func commitName() {
        let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = clean.isEmpty ? nil : String(clean.prefix(40))
        guard kept != app.profileName else { return }
        app.profileName = kept
        app.persist()
    }
}

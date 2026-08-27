import SwiftUI

/// Who this phone belongs to, as far as the app is concerned.
///
/// There is no account — nothing to fetch a name from and nothing to download a picture
/// from — so both are typed here and kept here, beside the trips and the stamps. That is
/// not a stopgap: a profile that reports what the phone actually holds is the same honesty
/// the rest of the app keeps, and a name nobody entered would be the invented value this
/// app refuses everywhere else.
///
/// **Nothing is written until Save.** The first version applied every tap the moment it
/// happened, which is defensible and reads as broken: a grid that lights a square and a
/// screen that offers no way to agree leaves somebody wondering whether anything was kept.
/// So the name and the emoji are held here as drafts, the close control discards them, and
/// the one lime button at the foot is what commits.
struct ProfileIdentityEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var picked: String?
    @State private var loaded = false
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

    /// Five across rather than six. At six the squares came out barely fifty points wide
    /// and the emoji inside them read as decoration on a form; at five each one is a
    /// sixty-point tile with a glyph big enough to actually choose between.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    }

    private var changed: Bool {
        let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? nil : clean) != app.profileName || picked != app.profileEmoji
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    preview

                    Text("Your name".uppercased())
                        .font(WP.body(10)).tracking(1.4).opacity(0.5)
                        .padding(.top, 26).padding(.bottom, 8)

                    TextField("Not set", text: $typed)
                        .font(WP.body(16))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
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
                        if picked != nil {
                            Button("Clear") {
                                picked = nil
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
                .padding(.top, 4)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background(WP.bg)
        // Welded to the floor, the way every other screen in the app carries its one action.
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .task {
            // Once. A `.onAppear` that ran again after the keyboard resigned would throw
            // away whatever had just been typed.
            guard !loaded else { return }
            typed = app.profileName ?? ""
            picked = app.profileEmoji
            loaded = true
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ParkHop · a field planner").kickerStyle()
                Text("You").font(WP.displayBold(38)).tracking(-0.4).padding(.top, 2)
            }
            Spacer(minLength: 0)
            GlassDisc(icon: "xmark", size: 44) { dismiss() }
                .accessibilityLabel("Close without saving")
                .padding(.top, 2)
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    /// The circle as it will look, so the choice is judged at the size it is worn rather
    /// than at the size of a square in a grid.
    private var preview: some View {
        HStack(spacing: 14) {
            Group {
                if let picked {
                    Text(picked).font(.system(size: 40))
                } else {
                    Text(monogram).font(WP.heading(30)).foregroundStyle(WP.accent800)
                }
            }
            .frame(width: 86, height: 86)
            .background(WP.accent100, in: Circle())
            .overlay { Circle().stroke(WP.accent.opacity(0.28), lineWidth: 1) }

            VStack(alignment: .leading, spacing: 3) {
                Text(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "No name yet"
                     : typed)
                    .font(WP.display(26))
                    .opacity(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .lineLimit(2)
                Text("How the profile will read")
                    .font(WP.bodyItalic(11.5)).opacity(0.55)
            }
            Spacer(minLength: 0)
        }
    }

    private var monogram: String {
        let initials = app.visitRail.prefix(2).compactMap { $0.park.name.first }
        return initials.isEmpty ? "◆" : String(initials).uppercased()
    }

    /// One emoji, at a size a thumb can hit and an eye can read.
    private func square(_ glyph: String) -> some View {
        let chosen = picked == glyph
        return Button {
            picked = glyph
            Haptics.tap()
        } label: {
            Text(glyph)
                .font(.system(size: 34))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(chosen ? WP.accent100 : WP.neutral100.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(chosen ? WP.accent : WP.divider, lineWidth: chosen ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(chosen ? "\(glyph), chosen" : glyph)
    }

    /// The app's own committing control, in the app's own strip: `GlowButton` in lime at
    /// fifty-two points, on the page colour under a hairline — the shape My list and the
    /// trip's Days tab both end in.
    private var footer: some View {
        GlowButton(title: changed ? "Save" : "Done", minHeight: 52) {
            Haptics.tap()
            save()
            dismiss()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WP.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(WP.bg.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    /// Trimmed, capped, and emptied back to nothing rather than kept as spaces.
    private func save() {
        let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        app.profileName = clean.isEmpty ? nil : String(clean.prefix(40))
        app.profileEmoji = picked
        app.persist()
        app.show("Saved")
    }
}

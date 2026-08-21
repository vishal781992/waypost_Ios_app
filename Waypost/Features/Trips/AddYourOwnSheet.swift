import SwiftUI

/// A link or a note, put on the list by hand.
///
/// The rest of the list is built by pressing add on places the app already found. This is
/// the half it cannot find: the permit page somebody has to read, the reservation email,
/// the trail somebody was told about in a car park. Two modes because they are two things —
/// a link unfurls into a card, a note is just the sentence.
struct AddYourOwnSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var trip: String
    /// The day it lands on. Chosen by which plus was pressed, so it is never picked twice.
    var day: Date?
    var label: String

    private enum Mode: String, CaseIterable { case link, note }
    @State private var mode: Mode = .link
    @State private var text = ""
    @FocusState private var focused: Bool

    /// A link has to be a link. Typing a sentence into the link field and getting a card
    /// titled "Untitled" helps nobody, so the button waits until it parses.
    private var url: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }

    private var canAdd: Bool {
        mode == .link ? url != nil : !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add to \(label)".uppercased())
                .font(WP.body(11)).tracking(1.4).foregroundStyle(WP.accent700)
                .padding(.bottom, 5)

            // The sheet says what it is in the same voice every other screen does. A
            // 9.5pt kicker on its own was the whole heading, which is why it read as a
            // form field rather than as a screen.
            Text(mode == .link ? "Paste a link" : "Write a note")
                .font(WP.display(28))
                .padding(.bottom, 16)

            Picker("", selection: $mode) {
                Text("Link").tag(Mode.link)
                Text("Note").tag(Mode.note)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 16)

            Group {
                if mode == .link {
                    TextField("recreation.gov/…", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    TextField("What should you remember?", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .font(WP.body(17))
            .focused($focused)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(WP.onInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WP.divider, lineWidth: 1))

            Text(mode == .link
                 ? "The page's title and picture are fetched once and kept, so the card still reads with no signal."
                 : "A line to yourself — a booking reference, a shuttle that sells out, whatever the app cannot know.")
                .font(WP.bodyItalic(12.5)).opacity(0.55).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Spacer(minLength: 16)

            // Full width, and the height every other control on a sheet is. The pair sat
            // at 46 points in the middle of a half-height sheet with most of it empty
            // below them.
            Button {
                add()
            } label: {
                Text("Add")
                    .font(WP.body(17, semibold: true))
                    .foregroundStyle(WP.text)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(canAdd ? WP.book : WP.neutral200, in: Capsule())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .disabled(!canAdd)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(WP.body(16))
                    .foregroundStyle(WP.text.opacity(0.7))
                    .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        }
        .padding(.horizontal, WP.gutter)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WP.bg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func add() {
        let item: PlanItem
        if mode == .link, let url {
            // Asked for straight away rather than when the card first draws, so by the
            // time the sheet has closed the card usually has its title already.
            LinkPreviews.shared.load(url)
            item = PlanItem(id: UUID().uuidString, day: day, kind: .link(url), added: Date())
        } else {
            let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return }
            item = PlanItem(id: UUID().uuidString, day: day, kind: .note(note), added: Date())
        }
        app.addToPlan(trip, item: item)
        dismiss()
    }
}

// MARK: - A link, unfurled

/// Somebody's link as the page it points at.
///
/// Title, site and picture come from `LinkPreviews`, which is Apple's own unfurl and keeps
/// what it finds. A link that will not answer keeps its address and says so — a blank card
/// with a spinner on it forever is worse than an honest one.
struct LinkCard: View {
    var url: URL

    private var preview: LinkPreviews.Preview? { LinkPreviews.shared.preview(for: url) }

    var body: some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 0) {
                if let preview, let image = LinkPreviews.shared.image(for: preview) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 104)
                        .clipped()
                }

                HStack(spacing: 9) {
                    if preview?.image == nil {
                        Image(systemName: "link")
                            .font(.system(size: 13))
                            .foregroundStyle(WP.accent700)
                            .frame(width: 30, height: 30)
                            .background(WP.neutral200, in: RoundedRectangle(cornerRadius: 7))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview?.title ?? shortAddress)
                            .font(WP.rowTitle(14))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(WP.body(11)).opacity(0.6)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WP.onInk)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(WP.divider, lineWidth: 1))
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .padding(.vertical, 3)
        .task(id: url) { LinkPreviews.shared.load(url) }
    }

    /// `alltrails.com/…/sky-pond` — enough of the address to recognise it by.
    private var shortAddress: String {
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        guard let last = url.pathComponents.last, last != "/" else { return host }
        return "\(host)/…/\(last)"
    }

    private var subtitle: String {
        if let preview { return preview.host }
        if LinkPreviews.shared.didFail(url) { return "Could not reach this page" }
        return "Reading the page…"
    }
}

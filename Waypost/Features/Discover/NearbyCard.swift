import SwiftUI

/// "Near you" — the measured shortlist, and a brief written on the phone about it.
///
/// The ranked parks and their numbers are the answer. The paragraph is a reading of those
/// numbers, written by Apple's on-device model, and it is labelled as such wherever it
/// appears. If the model cannot run, the card says why and the list carries on.
struct NearbyCard: View {
    @Environment(AppState.self) private var app
    @State private var briefing = NearbyBriefing()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch briefing.state {
            case .idle:
                prompt
            case .locating:
                status("Measuring from where you are…")
            case .thinking:
                shortlist()
                status("Writing the brief on this iPhone…")
            case .ready(let brief):
                headline(brief)
                    .transition(Motion.panelTransition)
                shortlist(brief)
                footnote("Written on this iPhone by Apple Intelligence, from the figures beside each park. It is not allowed to state a figure of its own — every number here is measured by ParkHop — and nothing leaves the phone.")
            case .unavailable(let reason):
                shortlist()
                footnote(reason)
            case .failed(let reason):
                if !briefing.candidates.isEmpty { shortlist() }
                footnote(reason)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .animation(Motion.panel, value: briefing.candidates.count)
        .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WP.divider, lineWidth: 1))
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            // The same sparkle the park screen's AI Overview wears, so the two AI-written
            // things in the app are marked the same way. Only when the model can actually
            // run: where it cannot, this card ranks parks by measured distance and nothing
            // on it is written, so a sparkle would be claiming something untrue.
            if briefing.modelAvailability == nil {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WP.accent700)
                    .accessibilityLabel("Written on this iPhone")
            }
            Kicker(text: briefing.placeName.map { "Near \($0)" } ?? "Near you")
            Spacer(minLength: 0)
            if case .ready = briefing.state {
                Button {
                    Task { await briefing.run() }
                } label: {
                    Text("Again").font(WP.headingUI(12.5)).foregroundStyle(WP.accent700)
                }
                .buttonStyle(PressStyle(scale: 0.94))
            }
        }
        .padding(.bottom, 6)
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What could I reach today?")
                .font(WP.heading(21))
            Text(briefing.modelAvailability == nil
                 ? "ParkHop measures the parks around you and writes you a short brief on the phone — no network, no account."
                 : "ParkHop measures the parks around you and ranks them by real distance.")
                .font(WP.body(12.5)).lineSpacing(2).opacity(0.72)
                .fixedSize(horizontal: false, vertical: true)

            // The button says what it does; the sparkle says who writes it. A reader who
            // presses "Brief me" should already know a model is about to compose the
            // answer rather than the app looking it up.
            GlowButton(title: briefing.modelAvailability == nil ? "✦  Brief me" : "Rank them",
                       minHeight: 44) {
                Task { await briefing.run() }
            }
            .accessibilityLabel(briefing.modelAvailability == nil
                                ? "Brief me, written on this iPhone"
                                : "Rank the parks near me")
        }
    }

    private func status(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).tint(WP.accent)
            Text(text).font(WP.bodyItalic(12.5)).opacity(0.7)
        }
        .padding(.top, 10)
    }

    /// The one sentence about the shortlist as a whole. The per-park lines used to follow
    /// it here as a bullet list, in ranking order — but so did the parks themselves, a
    /// little further down, so reading "why" for a given park meant counting bullets and
    /// counting rows and hoping they matched. Each line now sits under its own park.
    private func headline(_ brief: NearbyBrief) -> some View {
        Text(brief.headline)
            .font(WP.heading(20))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }

    /// The measured answer — always shown, whatever the model does. When a brief has a line
    /// about one of these parks, it reads underneath that park rather than in a list
    /// further up, so "why this one" sits with the park it is about.
    private func shortlist(_ brief: NearbyBrief? = nil) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(briefing.candidates.enumerated()), id: \.element.id) { index, candidate in
                // `validate` writes each note's park as the candidate's own name, so this
                // matches exactly. A park the model wrote nothing usable about simply has
                // no line, and the row still reads.
                let why = brief?.notes.first { $0.park == candidate.park.name }?.why

                Button {
                    app.openPark(candidate.park.code)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ParkImage(park: candidate.park, blur: 7, saturation: 1.15,
                                  showsScrim: false, topLight: false)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.park.name).font(WP.rowTitle(17))
                            Text(candidate.factLine)
                                .font(WP.body(11.5)).opacity(0.62).tnum()
                                .lineLimit(1)
                            if let why {
                                Text(why)
                                    .font(WP.body(12.5)).lineSpacing(2).opacity(0.85)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                    .padding(.top, 3)
                                    // Staggered, so the brief reads as it is written
                                    // rather than appearing all at once.
                                    .transition(
                                        .opacity.combined(with: .offset(y: 6))
                                            .animation(Motion.panel.delay(Double(index) * 0.07))
                                    )
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WP.accent700)
                            // Kept on the park's own line as the row grows taller.
                            .padding(.top, 5)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .overlay(alignment: .bottom) { Hairline() }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(WP.bodyItalic(11.5))
            .lineSpacing(3)
            .opacity(0.55)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 11)
    }
}

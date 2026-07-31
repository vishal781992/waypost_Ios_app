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
                shortlist
                status("Writing the brief on this iPhone…")
            case .ready(let brief):
                briefBody(brief)
                    .transition(Motion.panelTransition)
                shortlist
                footnote("Written on this iPhone by Apple Intelligence, from the figures above. It is not allowed to state a figure of its own — every number here is measured by Waypost — and nothing leaves the phone.")
            case .unavailable(let reason):
                shortlist
                footnote(reason)
            case .failed(let reason):
                if !briefing.candidates.isEmpty { shortlist }
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
                 ? "Waypost measures the parks around you and writes you a short brief on the phone — no network, no account."
                 : "Waypost measures the parks around you and ranks them by real distance.")
                .font(WP.body(12.5)).lineSpacing(2).opacity(0.72)
                .fixedSize(horizontal: false, vertical: true)

            GlowButton(title: "Brief me", minHeight: 44) {
                Task { await briefing.run() }
            }
        }
    }

    private func status(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).tint(WP.accent)
            Text(text).font(WP.bodyItalic(12.5)).opacity(0.7)
        }
        .padding(.top, 10)
    }

    private func briefBody(_ brief: NearbyBrief) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(brief.headline)
                .font(WP.heading(20))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(brief.notes.enumerated()), id: \.element.park) { index, note in
                HStack(alignment: .top, spacing: 9) {
                    Text("·").foregroundStyle(WP.accent)
                    Text(note.why)
                        .font(WP.body(12.5)).lineSpacing(2).opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Staggered, so the brief reads as it is written rather than appearing.
                .transition(
                    .opacity.combined(with: .offset(y: 6))
                        .animation(Motion.panel.delay(Double(index) * 0.07))
                )
            }
        }
        .padding(.bottom, 12)
    }

    /// The measured answer — always shown, whatever the model does.
    private var shortlist: some View {
        VStack(spacing: 0) {
            ForEach(briefing.candidates) { candidate in
                Button {
                    app.openPark(candidate.park.code)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            BlobField(colors: candidate.park.c.map { Color(css: $0) },
                                      scrim: false, topLight: false)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.park.name).font(WP.rowTitle(17))
                            Text(candidate.factLine)
                                .font(WP.body(11.5)).opacity(0.62).tnum()
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WP.accent700)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .overlay(alignment: .bottom) { Hairline() }
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

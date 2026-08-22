import SwiftUI

/// The AI Overview tab: what to know before planning a trip to this park.
///
/// Three things — what the park is warning about, whether a reservation is needed, and why
/// the place was set aside — written on the phone by Apple's model where it can run, and
/// composed from the same facts where it cannot. The prose never states a number of its own.
struct AIBriefSection: View {
    var park: CuratedPark
    var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch ParkBrief.shared.state(for: park) {
            case .idle, .gathering:
                // Three points come back, always, with these glyphs and these labels —
                // they are the overview's own structure, not the model's, so they are
                // drawn from the first frame and only the prose is left grey. What was
                // here before was a single spinner line, and the tab grew by the better
                // part of a screen the moment the model finished.
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Reading the fees, the forecast and the crowds…")
                        .font(WP.bodyItalic(12.5)).opacity(0.7)
                }
                awaitedPoints
            case .failed(let why):
                Text(why).font(WP.bodyItalic(12.5)).opacity(0.6)
            case .ready(let brief):
                points(brief)
                SourceLine(source(brief))
            }
        }
        .task(id: park.code) {
            // The overview reads NPS facts, so it waits for them to be asked for first.
            ParkFacts.shared.load(park)
            ParkBrief.shared.load(park, date: date)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WP.accent700)
            Text("Before you plan".uppercased())
                .font(WP.body(14)).tracking(1.5).opacity(0.55)
        }
    }

    @ViewBuilder
    private func points(_ brief: ParkBrief.Brief) -> some View {
        // Warnings first: it is the only line here that can change whether the trip should
        // happen at all. Fees and busyness used to sit in this list — the fee is printed at
        // the top of this same screen and the hours beside it, so the overview was
        // restating what the reader had just scrolled past.
        VStack(alignment: .leading, spacing: 14) {
            point("exclamationmark.triangle", "Warnings", brief.warnings)
            point("calendar.badge.clock", "Reservations", brief.reservations)
            point("book.closed", "Why it matters", brief.significance)

            // Busyness, but counted rather than guessed. Only the parks the park service
            // publishes figures for get this; a state park has no curve and shows none.
            if let profile = Visitation.profile(for: park) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WP.accent700)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("How busy, by month".uppercased())
                            .font(WP.body(12)).tracking(1.3).foregroundStyle(WP.accent800)
                        VisitationChart(profile: profile, month: monthIndex)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The month the reader is planning for — the trip's first day where the sheet was
    /// given one, and this month otherwise.
    private var monthIndex: Int {
        Calendar.current.component(.month, from: date ?? Date()) - 1
    }

    /// The three points, in their own shape, before the model has written them.
    ///
    /// Two lines of prose each: the model is instructed to keep every point short, and
    /// two is what they run to. The chart below them is not drawn — whether this park has
    /// a visitation curve is known from the bundle rather than from any request, so the
    /// loaded state answers that question itself and a placeholder could only get it wrong.
    private var awaitedPoints: some View {
        VStack(alignment: .leading, spacing: 14) {
            awaitedPoint("exclamationmark.triangle", "Warnings")
            awaitedPoint("calendar.badge.clock", "Reservations")
            awaitedPoint("book.closed", "Why it matters")
        }
        .skeletonBreath()
    }

    private func awaitedPoint(_ glyph: String, _ label: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WP.accent700.opacity(0.45))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(WP.body(12)).tracking(1.3)
                    .foregroundStyle(WP.accent800.opacity(0.45))
                SkeletonBar(height: 11).padding(.top, 4)
                SkeletonBar(width: 190, height: 11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ glyph: String, _ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WP.accent700)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(WP.body(12)).tracking(1.3).foregroundStyle(WP.accent800)
                Text(text)
                    .font(WP.body(13.5)).lineSpacing(3)
                    .foregroundStyle(WP.text.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func source(_ brief: ParkBrief.Brief) -> String {
        let base = brief.byModel
            ? "Written on this iPhone by Apple Intelligence, from the park service's own description and reservations. The warnings are the park's own words, never a paraphrase."
            : "Composed from the park service's own description, alerts and reservations."
        if let note = ParkBrief.shared.modelAvailability, !brief.byModel {
            return base + " " + note
        }
        return base + " Every figure is measured; the reading is the only part written."
    }
}

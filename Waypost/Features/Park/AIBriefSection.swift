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
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Reading the fees, the forecast and the crowds…")
                        .font(WP.bodyItalic(12.5)).opacity(0.7)
                }
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
                .font(WP.body(11)).tracking(1.3).opacity(0.55)
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
                            .font(WP.body(10)).tracking(1.3).foregroundStyle(WP.accent800)
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

    private func point(_ glyph: String, _ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WP.accent700)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(WP.body(10)).tracking(1.3).foregroundStyle(WP.accent800)
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

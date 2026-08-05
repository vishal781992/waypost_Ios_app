import SwiftUI

/// The AI Overview tab: what to know before planning a trip to this park.
///
/// Four things — reservations, fees, how busy, the one attraction worth the drive —
/// written on the phone by Apple's model where it can run, and composed from the same
/// facts where it cannot. The exact fee and the timed-entry line are printed here from
/// NPS; the prose never states a number of its own.
struct AIBriefSection: View {
    var park: CuratedPark
    var date: Date?

    private var factsState: ParkFacts.State { ParkFacts.shared.state(for: park) }

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
        VStack(alignment: .leading, spacing: 14) {
            point("calendar.badge.clock", "Reservations", brief.reservations)
            point("ticket", "Fees", brief.fees, chip: liveFee)
            point("person.3", "Busyness", brief.busyness)
            point("star", "Worth the drive", brief.highlight)
        }
    }

    /// The real fee, printed by the app rather than the model — a chip beside the prose.
    private var liveFee: String? {
        if case .loaded(let f) = factsState { return f.fee }
        return nil
    }

    private func point(_ glyph: String, _ label: String, _ text: String, chip: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WP.accent700)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(label.uppercased())
                        .font(WP.body(10)).tracking(1.3).foregroundStyle(WP.accent800)
                    if let chip {
                        Text(chip)
                            .font(WP.body(10)).tracking(0.3)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(WP.accent100, in: Capsule())
                            .foregroundStyle(WP.accent800)
                    }
                }
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
            ? "Written on this iPhone by Apple Intelligence, from the park service's fees and reservations, the forecast, and the month."
            : "Composed from the park service's fees and reservations, the forecast, and the month."
        if let note = ParkBrief.shared.modelAvailability, !brief.byModel {
            return base + " " + note
        }
        return base + " Every figure is measured; the reading is the only part written."
    }
}

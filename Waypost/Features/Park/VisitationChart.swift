import SwiftUI

/// The shape of a park's year, in twelve bars.
///
/// Two things are being said at once, so they are said in two different ways rather than
/// two colours: the busiest month is the filled bar, and the month being planned is the one
/// with a ring round it. Colour alone would also leave the reader who cannot separate the
/// two hues with nothing, where the ring reads either way.
struct VisitationChart: View {
    var profile: Visitation.Profile
    /// Zero-based, and the month the rest of the screen is about — the trip's first day
    /// where there is one, today where there is not.
    var month: Int

    private var peak: Int { profile.peakIndex }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<12, id: \.self) { index in
                    bar(index)
                }
            }
            .frame(height: 46)

            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { index in
                    Text(Visitation.monthInitials[index])
                        .font(WP.body(9.5))
                        .foregroundStyle(index == month ? WP.accent800 : WP.text.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            Text(caption)
                .font(WP.body(11.5))
                .foregroundStyle(WP.text.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bar(_ index: Int) -> some View {
        // A floor of two points, so a park's dead month is still a mark on the axis rather
        // than a gap that reads as missing data.
        let height = max(2, 46 * profile.share(index))
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            // The mark, let down to 0.55 so twelve of them stay a chart rather than twelve
            // things asking to be pressed; the busiest month is the same colour a step
            // deeper, which reads as the top of the ramp instead of a different subject.
            .fill(index == peak ? WP.markDeep : WP.mark.opacity(0.55))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if index == month {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(WP.accent800, lineWidth: 1.5)
                        .frame(height: height)
                }
            }
    }

    /// Says what the bars show, for anyone who is not going to read a chart — and names the
    /// figure rather than implying one, since these are counted visitors and not a rating.
    private var caption: String {
        let peakName = Visitation.monthName(peak)
        let thisName = Visitation.monthName(month)
        guard month != peak else {
            return "\(thisName) is the busiest month here, averaged over \(years)."
        }
        let share = Int((profile.share(month) * 100).rounded())
        return "\(peakName) is the busiest month; \(thisName) runs about \(share)% of that, averaged over \(years)."
    }

    private var years: String {
        guard let first = profile.years.first, let last = profile.years.last else { return "recent years" }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}

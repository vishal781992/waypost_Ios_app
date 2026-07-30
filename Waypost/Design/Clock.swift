import Foundation

extension String {
    /// Zero-pads a single-digit hour in a clock time: `6:45 am` becomes `06:45 am`.
    ///
    /// The field library writes times the way a person says them; a list of them reads
    /// as a ragged column, because the minutes no longer line up under each other. This
    /// pads at the point of display, so the data keeps the designer's wording and only
    /// the column is squared off.
    ///
    /// Anything that is not an hour is left alone — `3 h 19 m`, `1.5 mi`, `Day 1 of 2`.
    var clockPadded: String {
        replacingOccurrences(
            of: "(?<![0-9:.])([0-9]):([0-9]{2})",
            with: "0$1:$2",
            options: .regularExpression
        )
    }
}

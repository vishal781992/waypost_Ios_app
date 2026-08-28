import Foundation

/// What a day of travelling is, before anybody has driven one.
///
/// The composer used to give every leg exactly one day. Castle Pines to Miami is 2,074
/// miles and thirty-seven and a half hours at the wheel, and the trip said it was a day —
/// the same day it gave the forty-minute run from the airport to Biscayne. Nothing in the
/// app looked at a duration to decide how long a trip was; the stat line multiplied the
/// park count by three.
///
/// These are the assumptions that replace that arithmetic. They are assumptions, which is
/// why they are gathered in one named place rather than spread as literals through the
/// composer: a trip that says it takes eleven days is making a claim, and the claim has to
/// be inspectable and, eventually, adjustable.
struct TripPace: Hashable {
    /// Hours at the wheel in one day. Eight is the number road-trip planners settle on —
    /// about five hundred miles. Past ten it stops being a holiday.
    var wheelHours: Double = 8

    /// What the router does not count. A routed hour is time moving: no fuel, no food,
    /// no legs stretched, no queue at the park gate. Fifteen per cent is the usual
    /// allowance. It does not shorten the driving — it decides when the driving ends, so a
    /// full eight-hour day set off at eight gets in a little after six rather than at four.
    var breakRate: Double = 0.15

    /// When the first day sets off. Later than the rest, because the first morning has a
    /// house to lock up and a car to load.
    var firstDepartureHour: Int = 9
    var departureHour: Int = 8

    /// Arrive before this and there is enough day left for the park. After it, the day is
    /// spent arriving: find the bed, eat, and start in the morning.
    var parkCutoffHour: Int = 16

    /// What a flying day will absorb before the drive at the far end becomes a day of its
    /// own. Nine hours door to door and forty minutes to Biscayne is one day; nine hours
    /// and the six from Salt Lake City to Yellowstone is not.
    var flyingDayHours: Double = 13

    static let standard = TripPace()
}

/// One leg, cut into the days it actually takes.
///
/// Every function here is pure: give it minutes and it gives back days. Nothing reaches a
/// network, nothing touches the main actor, and every answer is decided by its arguments —
/// so `compose` and `plannedShape` can both ask and be guaranteed the same answer, which
/// is the one thing the skeleton and the finished list must agree on.
enum TripClock {

    /// One day of a leg: its share of the hours, its share of the miles, and — where the
    /// trip has a real start date — the clock times either end of it.
    struct DayPart: Hashable {
        var number: Int
        var of: Int
        var minutes: Int
        var miles: Int
        var departs: Date?
        var arrives: Date?

        var isLast: Bool { number == of }
    }

    /// A leg's days.
    struct Span: Hashable {
        var parts: [DayPart]

        /// When the leg gets in, where the trip has dates to say it with.
        var arrival: Date? { parts.last?.arrives }
    }

    /// Driving minutes as they are actually spent, breaks included.
    static func elapsedMinutes(driving minutes: Int, pace: TripPace = .standard) -> Int {
        Int((Double(max(0, minutes)) * (1 + pace.breakRate)).rounded())
    }

    /// How many days a drive takes. The number the whole feature turns on.
    ///
    /// Counted against the wheel, not against the clock. Eight hours means eight hours of
    /// driving; the breaks are what make that day end at half past five rather than at
    /// five, and they are added to the clock below. Counting them here instead pushed a
    /// seven-hour drive — obviously one day — into two, because seven hours and fifteen
    /// per cent is eight hours and three minutes.
    static func days(forDriving minutes: Int, pace: TripPace = .standard) -> Int {
        let cap = max(60, Int((pace.wheelHours * 60).rounded()))
        return max(1, Int((Double(max(0, minutes)) / Double(cap)).rounded(.up)))
    }

    /// When a day sets off.
    static func departure(on day: Date, first: Bool, pace: TripPace = .standard) -> Date {
        let calendar = Calendar.current
        let hour = first ? pace.firstDepartureHour : pace.departureHour
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    /// Whether an arrival at this time leaves any of the day for the park.
    static func reachesPark(by arrival: Date?, pace: TripPace = .standard) -> Bool {
        guard let arrival else { return false }
        return Calendar.current.component(.hour, from: arrival) < pace.parkCutoffHour
    }

    /// A drive, cut into days.
    ///
    /// Split evenly rather than filled and spilled. A nine-hour drive is two half days,
    /// not a full one followed by an hour — nobody drives to the cap and then puts an hour
    /// on the far side of a night's sleep, and a trip that said they did would be
    /// describing a day nobody is going to have.
    ///
    /// `startingOn` is the day the leg begins, not the instant: the hours live here so
    /// there is one place that decides what time anybody sets off. It may be `nil` — a
    /// trip whose dates will not parse still knows how many days its drives take, and the
    /// clock times are simply absent rather than invented.
    static func split(driving minutes: Int, miles: Int, startingOn day: Date?, first: Bool,
                      pace: TripPace = .standard) -> Span {
        let count = days(forDriving: minutes, pace: pace)
        var parts: [DayPart] = []
        // Wheel minutes, so a day's hours and the leg's own hours are the same measure and
        // the days sum back to the leg exactly. The breaks go on when the clock is read.
        var minutesLeft = max(0, minutes)
        var milesLeft = max(0, miles)
        var cursor = day.map { departure(on: $0, first: first, pace: pace) }

        for number in 1...count {
            // The last day takes what is left, so the parts sum to the leg exactly rather
            // than to the leg plus or minus a rounding error per day.
            let remaining = count - number + 1
            let share = number == count
                ? minutesLeft
                : Int((Double(minutesLeft) / Double(remaining)).rounded())
            let mileShare = number == count
                ? milesLeft
                : Int((Double(milesLeft) * Double(share) / Double(max(1, minutesLeft))).rounded())

            let departs = cursor
            let arrives = departs.map {
                $0.addingTimeInterval(TimeInterval(elapsedMinutes(driving: share, pace: pace) * 60))
            }
            parts.append(DayPart(number: number, of: count, minutes: share, miles: mileShare,
                                 departs: departs, arrives: arrives))

            minutesLeft -= share
            milesLeft -= mileShare
            cursor = arrives.flatMap { arrival in
                Calendar.current.date(byAdding: .day, value: 1, to: arrival).map {
                    departure(on: Calendar.current.startOfDay(for: $0), first: false, pace: pace)
                }
            }
        }

        return Span(parts: parts)
    }

    /// Minutes in the form the rest of the app writes them — "7 h 45 m", rounded to five
    /// the way the router's own labels are, so a day's hours and a leg's hours are written
    /// the same way on the same screen.
    static func clock(_ minutes: Int) -> String {
        var hours = max(0, minutes) / 60
        var rest = Int((Double(max(0, minutes) % 60) / 5).rounded()) * 5
        if rest == 60 { hours += 1; rest = 0 }
        return rest > 0 ? "\(hours) h \(rest) m" : "\(hours) h"
    }
}

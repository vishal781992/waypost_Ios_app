import Foundation

/// Whether flying a leg actually beats driving it.
///
/// "Fly when faster" was a switch with nothing behind it. The builder stored the answer,
/// the review screen read it back, and every trip was routed by road regardless — the
/// preference reached no code that could act on it. This is the missing half.
///
/// **It compares doors, not airports.** A 900-mile drive is fourteen hours of wheel time;
/// the flight that replaces it is an hour to the airport, most of two before the door
/// closes, two in the air, and the better part of another at the hire-car desk on the far
/// side. Comparing gate to gate against a whole day's drive is how an app talks somebody
/// into a flight that saves them nothing.
///
/// **It says no out loud.** A leg the switch declines to fly comes back as `.drives` with
/// the reason, so the screen can say why rather than showing nothing and reading as
/// broken — which is what the switch did for its whole life until now.
///
/// **Large hubs only.** The flight anybody is weighing against a drive leaves from one of
/// about a hundred airports. Naming the regional field twenty miles from the park instead
/// is technically nearer and practically useless — see `hub(near:)`.
///
/// **Every number is an estimate and the copy says so.** No airline publishes schedules to
/// an app without a contract. This cannot claim a flight exists on a given day; it says
/// which airports the leg would be flown between, and what that would cost in hours.
enum FlightCompare {
    enum Verdict: Hashable {
        /// Flying wins, by enough to be worth the fares.
        case flies(FlyOption)
        /// Driving wins, and why.
        case drives(String)
    }

    // MARK: What the model assumes

    /// Below this, the airports alone cost more than the drive they replace. The best case
    /// — two large hubs, a nonstop — is about four and a half hours of door-to-door
    /// overhead, and four and a half hours is a 250-mile drive.
    private static let shortestWorthFlying = 250.0
    /// How far somebody will drive to reach a large hub. Further than it sounds, because
    /// this is what people actually do: fly into Las Vegas and drive the three hours to
    /// Zion, into Salt Lake City and drive to Arches. The drive is counted in the total,
    /// so a hub that is too far to be worth it loses the comparison on its own — this is
    /// only the point past which there is no hub worth naming at all.
    private static let farthestToAirport = 350.0
    /// A flight has to beat the drive by more than this to be worth recommending. Forty
    /// minutes is not a saving once it is bought with fares, bags and a hire car.
    private static let worthwhileSaving = 60

    private static let cruiseMPH = 500.0
    private static let airportDriveMPH = 55.0
    /// Pushback, taxi, climb and descent — the part of a flight that is not cruise, and
    /// the reason a 400-mile hop is never 48 minutes.
    private static let taxiClimbDescent = 35
    /// Kerbside to door-closed at a large airport.
    private static let beforeDeparture = 105
    /// No flight leaves at the minute somebody wants one, and not every pair of hubs has a
    /// nonstop. No schedule is published to this app, so rather than guess at connections
    /// one way or the other, every flight carries an hour of slack — which keeps the
    /// estimate on the conservative side of the comparison it is used for.
    private static let scheduleSlack = 60
    private static let deplaneAndBags = 25
    private static let hireCarDesk = 45

    // MARK: The comparison

    /// - Parameter driveMinutes: what the router said the drive actually takes. The
    ///   comparison is only as honest as this, so it is never modelled from distance when
    ///   a measured number exists.
    static func verdict(from: (lat: Double, lon: Double),
                        to: (lat: Double, lon: Double),
                        driveMinutes: Int) -> Verdict {
        guard driveMinutes > 0 else {
            return .drives("This leg has no measured drive to compare a flight against.")
        }

        let direct = Geo.haversine(from, to)
        guard direct >= shortestWorthFlying else {
            return .drives("Too short to fly — the airports at either end would cost more than the whole drive.")
        }

        guard let origin = hub(near: from), let destination = hub(near: to) else {
            return .drives("No major airport within \(Int(farthestToAirport)) miles of both ends of this leg.")
        }
        guard origin.airport.code != destination.airport.code else {
            return .drives("Both ends of this leg are served by \(origin.airport.code) — there is nothing to fly between.")
        }

        let airMiles = Geo.haversine((origin.airport.lat, origin.airport.lon),
                                     (destination.airport.lat, destination.airport.lon))
        let toAirport = minutes(driving: origin.miles)
        let fromAirport = minutes(driving: destination.miles)
        let gateToGate = Int((airMiles / cruiseMPH * 60).rounded()) + taxiClimbDescent

        let doorToDoor = toAirport + beforeDeparture + gateToGate + scheduleSlack
            + deplaneAndBags + hireCarDesk + fromAirport
        let saving = driveMinutes - doorToDoor

        guard saving > worthwhileSaving else {
            return .drives(saving > 0
                ? "Flying via \(origin.airport.code) saves under an hour door to door — not worth the fares."
                : "Driving is quicker than flying via \(origin.airport.code) once both airports are counted.")
        }

        return .flies(FlyOption(
            via: "\(origin.airport.code) → \(destination.airport.code)",
            time: "≈ \(clock(doorToDoor)) door to door",
            note: "About \(clock(saving)) quicker than driving it. Counts \(clock(toAirport)) to "
                + "\(origin.airport.code) and \(clock(fromAirport)) from \(destination.airport.code) "
                + "in a hire car. Estimated — no airline schedule is published to this app.",
            from: FlyAirport(code: origin.airport.code,
                             lat: origin.airport.lat, lon: origin.airport.lon),
            to: FlyAirport(code: destination.airport.code,
                           lat: destination.airport.lat, lon: destination.airport.lon),
            // The same two numbers the sentence above is written from, kept as numbers so
            // the day composer can spend them. `fromAirport` is already counted inside
            // `doorToDoor`; it travels alongside so anything with the router's real figure
            // for that drive can swap it in rather than add it on.
            doorToDoorMinutes: doorToDoor,
            fromAirportMinutes: fromAirport
        ))
    }

    // MARK: Picking the airports

    /// The airport this end of the leg would actually be flown through: large hubs only,
    /// the hundred fields most people's flights already go through.
    ///
    /// Regional and small fields are excluded outright, not merely ranked below the hubs.
    /// Mammoth Yosemite and Cedar City are nearer to their parks than any hub is, and an
    /// earlier version of this named them for exactly that reason — but two flights a day
    /// at four times the fare is not the flight anybody is comparing against a drive.
    /// Nearly everyone flies to Las Vegas and drives to Zion, to Salt Lake City and drives
    /// to Arches, and the extra hours in the hire car are counted below rather than
    /// avoided by naming an airport nobody uses.
    /// Scans the hundred hubs rather than ranking every field and filtering the top of the
    /// list: in a crowded corner of the country, forty airports can all be small ones, and
    /// the hub 300 miles out — the one actually flown to — never appears.
    private static func hub(near point: (lat: Double, lon: Double)) -> (airport: Airport, miles: Double)? {
        var best: (airport: Airport, miles: Double)?
        for airport in Datasets.shared.airports where airport.t == 1 {
            // The same road-to-straight-line factor `AirportFinder` uses, so the drive to
            // the airport is measured the way the rest of the app measures one.
            let miles = Geo.haversine(point, (airport.lat, airport.lon)) * 1.25
            guard miles <= farthestToAirport else { continue }
            if best == nil || miles < best!.miles { best = (airport, miles) }
        }
        return best
    }

    // MARK: Numbers into words

    private static func minutes(driving miles: Double) -> Int {
        Int((miles / airportDriveMPH * 60).rounded())
    }

    private static func clock(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }
}

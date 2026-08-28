import MapKit
import SwiftUI

/// The four bottom sheets: a park alert, a permit window, a driving leg, a passport stamp.
struct DetailSheet: View {
    @Environment(AppState.self) private var app

    /// The day this drive is actually being made, when one of the saved trips starts
    /// today. Nil otherwise, and the stops and traffic stay unasked-for.
    @Environment(\.planningTrip) private var planningTrip

    private var driveDate: Date? {
        var trips = app.myTrips
        // The seed trip lives outside `myTrips` but is still a trip the user has.
        if !app.seedTripHidden { trips.append(SavedTrip.seed(dayNumber: app.day)) }
        return trips.compactMap(\.startDate).first { LegStops.isLive($0) }
    }
    /// The day this drive happens on the trip it belongs to.
    ///
    /// Not `driveDate` — that one answers "is this drive happening *today*", which is what
    /// traffic needs and is nil for every trip that is not under way right now. A stop
    /// added from this sheet belongs to the day the drive is made, whenever that is, so it
    /// is looked up from the trip's own day-by-day plan by matching the leg's two ends.
    private var planDay: Date? {
        guard let planningTrip, let trip = app.trip(planningTrip),
              case .ready(let days) = TripDays.shared.state(for: trip),
              case .routedLeg(let leg, _) = sheet
        else { return nil }
        return days.first { day in
            if case .travel(let from, let to, _, _, _) = day.kind {
                return from == leg.from && to == leg.to
            }
            return false
        }?.date
    }

    @Environment(\.dismiss) private var dismiss
    var sheet: ActiveSheet

    /// The stops the driver has picked to actually stop at, by `Stop.id`.
    ///
    /// Apple Maps takes a whole chain of places, not just a destination, so the ones ticked
    /// here are handed over as waypoints in mile order and the drive arrives in Maps with
    /// the stops already in it.
    /// Park-service places picked for this drive, kept apart from the fuel-and-food picks
    /// because they come from a different source and are handed to Maps in their own order.

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                switch sheet {
                case .alert(let park, let alert): alertBody(park: park, alert: alert)
                case .permit(let drop): permitBody(drop)
                case .leg(let index, let date): legBody(index: index, date: date)
                case .routedLeg(let leg, let label): routedLegBody(leg, label: label)
                case .stamp(let name, let city, let dist): stampBody(name: name, city: city, dist: dist)
                case .directions(let park, let text): directionsBody(park: park, text: text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WP.gutter)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        // The drive's numbers and the button that hands it to Maps stay put while the
        // stops scroll behind them. A long leg lists twenty-eight places, and the button
        // was at the bottom of all of them — the one control the screen exists for was the
        // hardest thing on it to reach, and the running count of picked stops sat out of
        // sight while the picking was going on. `safeAreaInset` also pads the scrolling
        // content by the bar's height, so the last stop still clears it.
        .safeAreaInset(edge: .bottom, spacing: 0) { pinnedFooter }
        .background(WP.bg.opacity(0.94).ignoresSafeArea())
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .presentationCornerRadius(WP.sheetCorner)
    }

    /// The bar welded to the bottom of a routed leg, and of the directions.
    ///
    /// Nothing for the other three sheets, which are short enough to read in one screen
    /// and whose buttons answer the text — "Understood" belongs under the sentence it
    /// answers. Directions are read and then left, at whichever detent the reader dragged
    /// the sheet to, so the way out sits at the bottom edge rather than wherever the
    /// park service's last sentence happened to end.
    @ViewBuilder
    private var pinnedFooter: some View {
        if case .directions = sheet {
            VStack(spacing: 0) {
                GlowButton(title: "Done", minHeight: 48) { dismiss() }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, WP.gutter)
            .padding(.top, 9)
            .padding(.bottom, -12)
            .background(WP.bg.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Hairline() }
        } else if case .routedLeg(let leg, _) = sheet {
            VStack(spacing: 9) {
                // The three-column block this replaces was worth about a hundred points of
                // a phone sheet — most of the room the stops need. The same three numbers
                // on one line say as much while the list is being read; the roads they are
                // driven on stay in the body, where they are reference rather than a thing
                // consulted mid-decision.
                // On a flown leg the mileage is the road not taken.
                //
                // No button under it any more. Opening this one leg in Maps was worth a
                // pinned control while the sheet was also where a drive's stops were
                // chosen; the list does that now, across the whole trip, so a button here
                // would hand Maps a single leg with nothing in it — a worse version of
                // what "Drive it with N stops" already does, one screen away. The rows
                // keep their own directions control for one place at a time.
                if let fly = leg.fly {
                    // The driving is part of the summary. Naming only the flight is what
                    // made a six-hour hire-car drive invisible until the sheet was opened.
                    let driven = leg.flightPath.map { "\($0.drivenMiles) mi driving" }
                    Text(([fly.via, fly.time] + [driven].compactMap { $0 }).joined(separator: " · "))
                        .font(WP.body(12.5)).foregroundStyle(WP.text.opacity(0.72)).tnum()
                } else {
                    Text("\(leg.miles) mi · \(leg.drive) · \(leg.road.split(separator: " → ").count) roads")
                        .font(WP.body(12.5)).foregroundStyle(WP.text.opacity(0.72)).tnum()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, WP.gutter)
            .padding(.top, 9)
            // Negative, and the background run into the safe area: the same trick the trip
            // builder's footer uses. Padding here only stacks on top of the clearance the
            // home indicator already provides, and stacking it twice cost about two stops'
            // worth of list. Opaque, or the rows slide visibly under the button.
            .padding(.bottom, -12)
            .background(WP.bg.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Hairline() }
        }
    }

    private var detents: Set<PresentationDetent> {
        switch sheet {
        case .alert: return [.medium]
        case .permit: return [.medium, .large]
        case .leg, .routedLeg: return [.medium, .large]
        case .stamp: return [.medium]
        // A paragraph for a park a mile off the highway, most of a page for one reached
        // by three named roads. Both detents, so neither is read through a letterbox.
        case .directions: return [.medium, .large]
        }
    }

    // MARK: Getting there

    /// The park service's own written approach.
    ///
    /// This text has been in every park's record since the app first called NPS, and no
    /// screen ever drew it — the road in was written down for the eight bundled parks and
    /// nowhere at all for the other four hundred and sixty. It is deliberately the park's
    /// wording rather than a route the app computes: it names the seasonal closures, the
    /// gates that are the wrong way round, and the last town with fuel.
    private func directionsBody(park: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 10)
            // The park's name in the serif it wears on its own screen, at the size the
            // masthead there uses, rather than in the sheet's system heading — the sheet
            // is about a park, and this is the same object under a different roof. Set
            // down off the drag indicator too: 18 points put the kicker in the corner.
            Text("GETTING THERE · NPS")
                .font(WP.body(11.5)).tracking(1.4).opacity(0.5)
            Text(park).font(WP.display(32)).padding(.top, 4)
            Text(text)
                .font(WP.body(14)).lineSpacing(4).opacity(0.85)
                .padding(.top, 10)
            Text("Written by the park. Roads close by season — check the alerts before a winter drive.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 14)
        }
    }

    // MARK: Alert

    private func alertBody(park: String, alert: CuratedAlert) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(alert.cat)
                    .font(WP.body(10))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .overlay(Capsule().stroke(WP.accent, lineWidth: 1))
                    .foregroundStyle(WP.accent700)
                Text(park.uppercased())
                    .font(WP.body(11)).tracking(1.3).opacity(0.45)
            }
            Text(alert.title).font(WP.heading(24)).padding(.top, 11)
                .multilineTextAlignment(.leading)
            Text(alert.body).font(WP.body(14)).lineSpacing(3).opacity(0.85).padding(.top, 8)
            Text("Posted by the park. ParkHop pushes these while a trip is running.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 12)

            GlowButton(title: "Understood") { dismiss() }
                .padding(.top, 16)
        }
    }

    // MARK: Permit window

    private func permitBody(_ drop: PermitDrop) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permit window".uppercased())
                .font(WP.body(12)).tracking(1.5).foregroundStyle(WP.accent700)
            Text(drop.what).font(WP.heading(23)).padding(.top, 9)
                .multilineTextAlignment(.leading)
            Text("They \(drop.when.clockPadded) and are gone in minutes. ParkHop can put a notification on your lock screen fifteen minutes before, with the booking link.")
                .font(WP.body(13.5)).lineSpacing(3).opacity(0.8).padding(.top, 6)

            // What that notification looks like.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("W")
                        .font(WP.headingUI(11))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(WP.accent, in: RoundedRectangle(cornerRadius: 6))
                    Text("PARKHOP").font(WP.body(11.5)).opacity(0.75)
                    Spacer(minLength: 0)
                    Text("15m before").font(WP.body(11)).opacity(0.55)
                }
                Text("Tickets in 15 minutes").font(WP.rowTitle(17)).padding(.top, 8)
                Text("\(drop.what) — tap to open Recreation.gov with your dates filled in.")
                    .font(WP.body(12.5)).opacity(0.78).lineSpacing(2).padding(.top, 3)
            }
            .foregroundStyle(WP.onInk)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WP.ink, in: RoundedRectangle(cornerRadius: 16))
            .padding(.top, 15)

            GlowButton(
                title: app.notifyPermits ? "✓  Alert set for this window" : "Notify me 15 minutes before",
                minHeight: 50
            ) {
                app.notifyPermits.toggle()
                app.persist()
                Haptics.tap()
                app.show(app.notifyPermits ? "Alert set — 15 minutes before" : "Alert cleared")
            }
            .padding(.top, 16)
        }
    }

    // MARK: A routed leg
    //
    // The same sheet as a seed leg, minus the things a router does not know: there is no
    // flight alternative and no charging plan, and no arrival time — an arrival needs a
    // departure, and nobody has said when they are leaving.

    /// Fuel, charging and today's traffic, for the day it is actually driven.
    ///
    /// Whether the lists above the roads line closed themselves.
    ///
    /// `legStops` is the last thing drawn before the roads, so it answers first: rows mean
    /// a trailing rule, and every other state of it ends in a sentence. With no stop list
    /// at all the question falls to the park service's own row list above it.
    private func stopsDrewTheirOwnRule(_ leg: TripRouting.Leg) -> Bool {
        switch LegStops.shared.state(for: leg) {
        case .ready(let stops, _): return !stops.isEmpty
        case .idle: return !(TripDays.shared.legStops[leg.id] ?? []).isEmpty
        case .loading, .failed: return false
        }
    }

    /// Only on the day: Apple's traffic estimate for a drive three weeks out is not a
    /// forecast of anything, and neither is a list of petrol stations that may not be open.
    /// Stops come every eighty miles along the route the app already holds — roughly an
    /// hour and a quarter apart, and inside Apple Maps' 50 km search radius either side.
    @ViewBuilder
    private func legStops(_ leg: TripRouting.Leg) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch LegStops.shared.state(for: leg) {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Finding fuel, charging and food along the way…")
                        .font(WP.bodyItalic(12.5)).opacity(0.7)
                }
                .padding(.top, 16)
            case .failed(let why):
                Text(why).font(WP.bodyItalic(12.5)).opacity(0.6).padding(.top, 16)
            case .ready(let stops, let traffic):
                if let traffic {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Leaving now".uppercased())
                            .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent800)
                        Text(traffic.wheelTime).font(WP.statValue(20)).tnum()
                        Text("with traffic, from Apple Maps")
                            .font(WP.bodyItalic(11.5)).opacity(0.6)
                    }
                    .padding(.top, 16)
                }
                if stops.isEmpty {
                    Text("Apple Maps lists no fuel or charging along this route.")
                        .font(WP.bodyItalic(12.5)).opacity(0.6).padding(.top, 14)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("On the way".uppercased())
                            .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent800)
                        Text(planningTrip == nil
                             ? "fuel, charging and food along this drive"
                             : "add puts it on your list")
                            .font(WP.bodyItalic(11)).opacity(0.5)
                    }
                    .padding(.top, 18).padding(.bottom, 2)

                    ForEach(stops) { stop in
                        DividedRow(vertical: 11) {
                            HStack(spacing: 12) {
                                // The disc carries the colour, the glyph sits in it: four
                                // kinds of stop repeat at every mile marker, and in one
                                // accent the column cannot be read at a glance.
                                Image(systemName: stop.glyph)
                                    .font(.system(size: 14))
                                    .foregroundStyle(stop.kind.tint)
                                    .frame(width: 28, height: 28)
                                    .background(stop.kind.tintSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name).font(WP.rowTitle(15))
                                        .multilineTextAlignment(.leading)
                                    Text("mile \(stop.mile) · \(stop.label)")
                                        .font(WP.body(11.5)).foregroundStyle(stop.kind.tint).tnum()
                                }
                                Spacer(minLength: 0)

                                // This used to hold a second control that put the stop
                                // into a chain handed straight to Maps. The list does that
                                // job now and does it better: a place goes on it once, from
                                // whichever screen the reader found it on, and can be
                                // switched out of the drive there without leaving the list.
                                PlaceRowActions(place: PlannedPlace(
                                    name: stop.name,
                                    subtitle: "mile \(stop.mile) · \(stop.label)",
                                    lat: stop.mapItem.placemark.coordinate.latitude,
                                    lon: stop.mapItem.placemark.coordinate.longitude,
                                    category: stop.kind.rawValue
                                ), day: planDay)
                            }
                        }
                    }
                }
            }
        }
        .task(id: leg.id) {
            // Neither is asked for on a leg that is flown: a filling station and a monument
            // an hour up a valley are answers to a question nobody on this leg is asking,
            // and each one costs a routing request to measure.
            guard leg.fly == nil else { return }
            // The stops are useful whenever the trip is being looked at, so they always
            // load. Traffic is a "leaving now" estimate, which only means anything within
            // the departure window — so it is fetched only when the drive is live.
            LegStops.shared.load(leg, electric: app.vehicleIsElectric,
                                 includeTraffic: LegStops.isLive(driveDate))
            TripDays.shared.loadStops(for: leg)
        }
    }

    private func routedLegBody(_ leg: TripRouting.Leg, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Set down from the drag indicator rather than tucked under it, and at a size
            // that reads as the sheet's title instead of a caption above one.
            Text(label.uppercased())
                .font(WP.body(13.5)).tracking(1.7).foregroundStyle(WP.accent700)
                .padding(.top, 10)
            Text("\(leg.from) → \(leg.arrivesAt)").font(WP.heading(23)).padding(.top, 9)
                .multilineTextAlignment(.leading)

            if let fly = leg.fly {
                // The flight is not the whole leg, and this used to read as though it were.
                //
                // A flown leg is a drive to an airport, the flight, and a drive from the
                // far airport to the park — and that last one is routinely the longest
                // single stretch of the day. Salt Lake City to Yellowstone is 327 miles and
                // the better part of six hours. The sheet named the two airports and then
                // said "driven instead it is 1,470 miles", which describes the drive being
                // declined and says nothing at all about the six hours that are actually
                // going to be spent behind a wheel.
                //
                // What still does not apply is the roadside: stops are chosen along
                // `leg.coordinates`, which is the drive nobody is making. The stretches
                // below are the real ones, and they carry their own distance and roads.
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(fly.via).font(WP.mono(14)).tracking(2.2).foregroundStyle(WP.accent800)
                        Text(fly.time).font(WP.rowTitle(16))
                    }
                    Text(fly.note).font(WP.bodyItalic(12.5)).opacity(0.7).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 14)

                if let path = leg.flightPath {
                    Kicker(text: "And the driving either side")
                        .padding(.top, 18)
                        .overlay(alignment: .top) { Hairline() }
                        .padding(.top, 14)

                    // The drive to the airport, listed however short — `drawsOriginStub`
                    // is a rule about what is too small to draw on a map, and eleven miles
                    // to Midway is still eleven miles somebody has to leave the house for.
                    if let toAirport = path.toAirport {
                        airportDrive("\(leg.from) → \(path.departure.code)", toAirport)
                    } else {
                        Text("The routing service did not answer for the drive to \(path.departure.code), so it has no distance here.")
                            .font(WP.bodyItalic(12)).opacity(0.6).lineSpacing(3).padding(.top, 8)
                    }

                    // The drive off the far end is a leg of its own on the trip, with its
                    // own fuel, charging and monuments along it. Repeating its distance
                    // here would be the only place in the app where one drive is two rows.
                    if let fromAirport = path.fromAirport {
                        Text("Landing at \(path.arrival.code) leaves \(fromAirport.miles) mi to \(leg.to) — its own leg on this trip, with the stops along it.")
                            .font(WP.body(13)).lineSpacing(3).opacity(0.8).padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(path.drivenMiles) mi behind a wheel in all — against \(leg.miles) mi and \(leg.drive) driving the whole way instead.")
                            .font(WP.bodyItalic(12)).opacity(0.62).lineSpacing(3).padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Driven instead it is \(leg.miles) mi and \(leg.drive), by \(leg.road).")
                        .font(WP.body(13)).lineSpacing(3).opacity(0.8)
                        .padding(.top, 14)
                        .overlay(alignment: .top) { Hairline() }
                }

                // The branch above this drew the rule that closes the sheet, either over
                // the driving-either-side kicker or over the paragraph.
                SourceLine("Airports from the OurAirports table of large US hubs. The two drives are measured by Apple Maps over the roads named; the hours in the air are modelled. No airline schedule is published to this app, so this names the airports the leg would be flown between rather than a flight — check fares and times with an airline before planning around it.", ruled: false)
                    .padding(.top, 16)
            } else {
                // Places first, then the roadside. A long leg lists thirty petrol stations
                // and charging points, and the park service's monuments were under all of
                // them — the one part of the list somebody might change their day for was
                // the part they had to scroll furthest to find.
                worthStopping(leg)
                legStops(leg)

                // Distance, wheel time and the button now live in the pinned footer; the
                // roads stay here, under the stops they are driven between.
                // Only where nothing above it has already drawn one. The stop lists are
                // built from `DividedRow` and each ends in a rule; with a rule here as
                // well, the roads line sat in a band of its own and the sheet carried
                // three lines inside seventy points. Where no stops came back there is no
                // rule above, and this one is what separates the roads from the sentence
                // saying so.
                Text(leg.road).font(WP.body(13)).lineSpacing(3).opacity(0.8)
                    .padding(.top, 14)
                    .overlay(alignment: .top) { if !stopsDrewTheirOwnRule(leg) { Hairline() } }

                SourceLine("Distance and wheel time from Apple Maps over the roads listed, its estimate for the road as it usually drives. Fuel, charging, food and somewhere to sleep along the way from Apple Maps — add any of them and they are handed to Maps as stops on the drive. Traffic is added on the day of the drive, when a leaving-now time means something.", ruled: false)
                    .padding(.top, 16)
            }
        }
    }

    private func openInMaps(from: String, to: String) {
        let query = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? to
        if let url = URL(string: "http://maps.apple.com/?daddr=\(query)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }

    /// The park service's own places worth breaking the drive for.
    ///
    /// The same section the day-by-day plan carries, in the sheet where the drive is
    /// actually handed to Maps — a monument twenty minutes off the road is no use to
    /// anybody if reading about it and driving to it are on two different screens. Each
    /// one gets the two controls the fuel and food rows already have: add it to the drive,
    /// or open it on its own.
    @ViewBuilder
    private func worthStopping(_ leg: TripRouting.Leg) -> some View {
        let units = TripDays.shared.legStops[leg.id] ?? []
        if TripDays.shared.isMeasuring(leg) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Measuring what the park service has near this road…")
                    .font(WP.bodyItalic(12.5)).opacity(0.7)
            }
            .padding(.top, 16)
        } else if !units.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Worth stopping for".uppercased())
                    .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.mark)
                Text("detour measured against this drive")
                    .font(WP.bodyItalic(11)).opacity(0.5)
            }
            .padding(.top, 18).padding(.bottom, 2)

            ForEach(units) { unit in
                DividedRow(vertical: 11) {
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WP.notice)
                            .frame(width: 28, height: 28)
                            .background(WP.notice.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.name).font(WP.rowTitle(15))
                                .multilineTextAlignment(.leading)
                            Text("\(unit.place) · \(unit.designation) · \(unit.diversionLine)")
                                .font(WP.body(11.5)).foregroundStyle(WP.accent700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)

                        PlaceRowActions(place: PlannedPlace(
                            name: unit.name,
                            subtitle: "\(unit.place) · \(unit.designation)",
                            lat: unit.lat, lon: unit.lon,
                            category: PlacesService.Kind.campground.rawValue
                        ), day: planDay)
                    }
                }
            }
        }
    }

    private static func mapItem(lat: Double, lon: Double, name: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        item.name = name
        return item
    }

    /// The stops this leg has found, if it has finished looking.
    private func readyStops(_ leg: TripRouting.Leg) -> [LegStops.Stop] {
        if case .ready(let stops, _) = LegStops.shared.state(for: leg) { return stops }
        return []
    }

    // MARK: Leg

    private func legBody(index: Int, date: String) -> some View {
        let leg = app.library.legs.indices.contains(index) ? app.library.legs[index] : nil
        return VStack(alignment: .leading, spacing: 0) {
            if let leg {
                Text("Driving day · \(date)".uppercased())
                    .font(WP.body(12)).tracking(1.5).foregroundStyle(WP.accent700)
                Text("\(leg.from) → \(leg.to)").font(WP.heading(23)).padding(.top, 9)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 0) {
                    legStat("Distance", "\(leg.mi) mi")
                    legStat("Wheel time", leg.drive)
                    legStat("Arrive", "3:20 pm".clockPadded)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }

                Text(leg.road).font(WP.body(13)).lineSpacing(3).opacity(0.8).padding(.top, 11)

                if let fly = leg.fly {
                    VStack(alignment: .leading, spacing: 5) {
                        Kicker(text: "By air")
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(fly.via).font(WP.mono(14)).tracking(2.2).foregroundStyle(WP.accent800)
                            Text(fly.time).font(WP.rowTitle(16))
                        }
                        Text(fly.note).font(WP.bodyItalic(12.5)).opacity(0.7).lineSpacing(2)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
                }

                ForEach(leg.ev, id: \.self) { stop in
                    DividedRow(vertical: 9) {
                        HStack(alignment: .top, spacing: 9) {
                            Text("⚡").foregroundStyle(WP.accent)
                            Text(stop).font(WP.body(13)).lineSpacing(2)
                        }
                    }
                }

                HStack(spacing: 9) {
                    Button {
                        app.toggleLiveActivity()
                    } label: {
                        Text(app.liveActivityOn ? "Live Activity on" : "Start Live Activity")
                            .font(WP.headingUI(14.5))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .glassControl()
                    }
                    .buttonStyle(PressStyle(scale: 0.98))

                    Button {
                        openInMaps(leg)
                    } label: {
                        Text("Maps")
                            .font(WP.headingUI(14.5))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 48)
                            .glassControl()
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
                .padding(.top, 16)
            }
        }
    }

    private func legStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(WP.body(10)).tracking(1.4).opacity(0.55)
            Text(value).font(WP.statValue(19)).tnum()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    /// Hands the leg to Apple Maps — the one place the app defers to the system rather
    /// than drawing its own route.
    private func openInMaps(_ leg: CuratedLeg) {
        let query = "\(leg.from) to \(leg.to)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?daddr=\(query)&dirflg=d") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }

    /// One end of a flown leg: where it runs, how far, how long, and on what.
    private func airportDrive(_ title: String, _ drive: TripRouting.AirportDrive) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(title).font(WP.rowTitle(15))
                Spacer(minLength: 0)
                Text("\(drive.miles) mi · \(drive.drive)")
                    .font(WP.body(12.5)).tnum().foregroundStyle(WP.accent700)
            }
            Text(drive.road).font(WP.bodyItalic(11.5)).opacity(0.62).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: Stamp

    private func stampBody(name: String, city: String, dist: String) -> some View {
        let key = app.stampKey(forName: name)
        let collected = app.isStamped(key)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Passport · \(dist) away".uppercased())
                .font(WP.body(12)).tracking(1.5).foregroundStyle(WP.accent700)
            Text(name).font(WP.heading(23)).padding(.top, 9)
                .multilineTextAlignment(.leading)
            Text(city).font(WP.bodyItalic(12.5)).opacity(0.65).padding(.top, 4)

            HStack {
                Spacer(minLength: 0)
                Group {
                    if collected {
                        StampFace(name: name, caption: app.stamp(key)?.caption ?? "stamped",
                                  nameSize: 15, captionSize: 7.5)
                            .frame(width: 152, height: 152)
                            .rotationEffect(.degrees(-4))
                    } else {
                        Text("Stand inside the park to collect")
                            .font(WP.headingUI(14))
                            .foregroundStyle(WP.neutral600)
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .frame(width: 132, height: 132)
                            .overlay(
                                Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                    .foregroundStyle(WP.neutral400)
                            )
                            .pulseRing()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 20)
            .animation(Motion.stamp, value: collected)

            GlowButton(
                title: collected ? "Collected" : "Collect the stamp",
                filled: !collected,
                strongGlow: collected
            ) {
                app.collectStamp(key, name: name, place: city)
            }

            Text("The phone taps back when a stamp lands. Geofenced on device, so it only works when you are actually there.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 12)
        }
    }
}

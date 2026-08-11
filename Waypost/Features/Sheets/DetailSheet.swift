import MapKit
import SwiftUI

/// The four bottom sheets: a park alert, a permit window, a driving leg, a passport stamp.
struct DetailSheet: View {
    @Environment(AppState.self) private var app

    /// The day this drive is actually being made, when one of the saved trips starts
    /// today. Nil otherwise, and the stops and traffic stay unasked-for.
    private var driveDate: Date? {
        var trips = app.myTrips
        // The seed trip lives outside `myTrips` but is still a trip the user has.
        if !app.seedTripHidden { trips.append(SavedTrip.seed(dayNumber: app.day)) }
        return trips.compactMap(\.startDate).first { LegStops.isLive($0) }
    }
    @Environment(\.dismiss) private var dismiss
    var sheet: ActiveSheet

    /// The stops the driver has picked to actually stop at, by `Stop.id`.
    ///
    /// Apple Maps takes a whole chain of places, not just a destination, so the ones ticked
    /// here are handed over as waypoints in mile order and the drive arrives in Maps with
    /// the stops already in it.
    @State private var chosen: Set<String> = []
    /// Park-service places picked for this drive, kept apart from the fuel-and-food picks
    /// because they come from a different source and are handed to Maps in their own order.
    @State private var chosenUnits: Set<String> = []

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                switch sheet {
                case .alert(let park, let alert): alertBody(park: park, alert: alert)
                case .permit(let drop): permitBody(drop)
                case .leg(let index, let date): legBody(index: index, date: date)
                case .routedLeg(let leg, let label): routedLegBody(leg, label: label)
                case .stamp(let name, let city, let dist): stampBody(name: name, city: city, dist: dist)
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

    /// The bar welded to the bottom of a routed leg. Nothing for the other four sheets,
    /// which are short enough to read in one screen and have no standing action.
    @ViewBuilder
    private var pinnedFooter: some View {
        if case .routedLeg(let leg, _) = sheet {
            VStack(spacing: 9) {
                // The three-column block this replaces was worth about a hundred points of
                // a phone sheet — most of the room the stops need. The same three numbers
                // on one line say as much while the list is being read; the roads they are
                // driven on stay in the body, where they are reference rather than a thing
                // consulted mid-decision.
                Text("\(leg.miles) mi · \(leg.drive) · \(leg.road.split(separator: " → ").count) roads")
                    .font(WP.body(12.5)).foregroundStyle(WP.text.opacity(0.72)).tnum()

                GlowButton(title: openTitle(leg), minHeight: 48) { openRoute(leg) }
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
                        Text("+ adds a stop to the drive")
                            .font(WP.bodyItalic(11)).opacity(0.5)
                    }
                    .padding(.top, 18).padding(.bottom, 2)

                    ForEach(stops) { stop in
                        let picked = chosen.contains(stop.id)
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

                                // Two separate controls, so neither is reached by accident:
                                // the first puts this place in the chain handed to Maps, the
                                // second opens this one place on its own.
                                Button {
                                    withAnimation(.snappy(duration: 0.18)) {
                                        if picked { chosen.remove(stop.id) } else { chosen.insert(stop.id) }
                                    }
                                    Haptics.tap()
                                } label: {
                                    Image(systemName: picked ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(picked ? WP.accent : WP.accent700.opacity(0.55))
                                        .frame(width: 40, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle(scale: 0.9))
                                .accessibilityLabel(picked
                                    ? "Remove \(stop.name) from the drive"
                                    : "Add \(stop.name) to the drive")

                                Button {
                                    stop.mapItem.openInMaps(launchOptions: [
                                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                                    ])
                                } label: {
                                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                                        .font(.system(size: 20)).foregroundStyle(WP.accent700)
                                        .frame(width: 36, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(stop.name) in Maps")
                            }
                        }
                    }
                }
            }
        }
        .task(id: leg.id) {
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
            Text("\(leg.from) → \(leg.to)").font(WP.heading(23)).padding(.top, 9)
                .multilineTextAlignment(.leading)

            // Places first, then the roadside. A long leg lists thirty petrol stations and
            // charging points, and the park service's monuments were under all of them —
            // the one part of the list somebody might change their day for was the part
            // they had to scroll furthest to find.
            worthStopping(leg)
            legStops(leg)

            // Distance, wheel time and the button now live in the pinned footer; the roads
            // stay here, under the stops they are driven between.
            Text(leg.road).font(WP.body(13)).lineSpacing(3).opacity(0.8)
                .padding(.top, 14)
                .overlay(alignment: .top) { Hairline() }

            SourceLine("Distance and wheel time from OSRM over the roads listed. Fuel, charging, food and somewhere to sleep along the way from Apple Maps — add any of them and they are handed to Maps as stops on the drive. Traffic is added on the day of the drive, when a leaving-now time means something.")
                .padding(.top, 16)
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
                let picked = chosenUnits.contains(unit.id)
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

                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                if picked { chosenUnits.remove(unit.id) } else { chosenUnits.insert(unit.id) }
                            }
                            Haptics.tap()
                        } label: {
                            Image(systemName: picked ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 22))
                                .foregroundStyle(picked ? WP.accent : WP.accent700.opacity(0.55))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.9))
                        .accessibilityLabel(picked
                            ? "Remove \(unit.name) from the drive"
                            : "Add \(unit.name) to the drive")

                        Button {
                            Self.mapItem(lat: unit.lat, lon: unit.lon, name: unit.name)
                                .openInMaps(launchOptions: [
                                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                                ])
                        } label: {
                            Image(systemName: "arrow.triangle.turn.up.right.circle")
                                .font(.system(size: 20)).foregroundStyle(WP.accent700)
                                .frame(width: 36, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(unit.name) in Maps")
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

    /// The park-service stops picked for this drive, nearest detour first.
    private func pickedUnits(_ leg: TripRouting.Leg) -> [TripDays.Stop] {
        (TripDays.shared.legStops[leg.id] ?? []).filter { chosenUnits.contains($0.id) }
    }

    /// The stops this leg has found, if it has finished looking.
    private func readyStops(_ leg: TripRouting.Leg) -> [LegStops.Stop] {
        if case .ready(let stops, _) = LegStops.shared.state(for: leg) { return stops }
        return []
    }

    /// The picked stops, in the order they are driven past.
    private func pickedStops(_ leg: TripRouting.Leg) -> [LegStops.Stop] {
        readyStops(leg).filter { chosen.contains($0.id) }
    }

    private func openTitle(_ leg: TripRouting.Leg) -> String {
        let count = pickedStops(leg).count + pickedUnits(leg).count
        guard count > 0 else { return "Open in Maps" }
        return "Open in Maps · \(count) stop\(count == 1 ? "" : "s")"
    }

    /// Hands the whole drive to Apple Maps — start, every picked stop in mile order, then
    /// the park — as one route rather than a single destination.
    ///
    /// `MKMapItem.openMaps(with:)` takes the chain, which the old `?daddr=` URL could not:
    /// that carried a park *name* and no stops at all, so Maps had to guess the destination
    /// from a string and the driver re-added every stop by hand.
    private func openRoute(_ leg: TripRouting.Leg) {
        func item(_ point: (lat: Double, lon: Double), _ name: String) -> MKMapItem {
            let item = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)))
            item.name = name
            return item
        }

        var chain: [MKMapItem] = []
        if let start = leg.coordinates.first { chain.append(item(start, leg.from)) }
        chain += pickedStops(leg).map(\.mapItem)
        // The park-service stops after the roadside ones: fuel and food are ordered by the
        // mile they sit at, and a monument has no mile — it has a detour, which is what
        // `pickedUnits` is already sorted by.
        chain += pickedUnits(leg).map { Self.mapItem(lat: $0.lat, lon: $0.lon, name: $0.name) }
        if let end = leg.coordinates.last { chain.append(item(end, leg.to)) }

        // A leg with no geometry has nothing to hand over but the name it is going to.
        guard chain.count > 1 else { return openInMaps(from: leg.from, to: leg.to) }

        MKMapItem.openMaps(with: chain, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
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
                        StampFace(name: name, caption: "stamped · today", nameSize: 15, captionSize: 7.5)
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
                app.collectStamp(key, name: name)
            }

            Text("The phone taps back when a stamp lands. Geofenced on device, so it only works when you are actually there.")
                .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3).padding(.top, 12)
        }
    }
}

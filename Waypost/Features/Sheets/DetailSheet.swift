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
        .background(WP.bg.opacity(0.94).ignoresSafeArea())
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .presentationCornerRadius(WP.sheetCorner)
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
                    Text("Asking Apple Maps about today's road…")
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
                    Text("On the way".uppercased())
                        .font(WP.body(10)).tracking(1.4).foregroundStyle(WP.accent800)
                        .padding(.top, 18).padding(.bottom, 2)
                    ForEach(stops) { stop in
                        Button {
                            stop.mapItem.openInMaps(launchOptions: [
                                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                            ])
                        } label: {
                            DividedRow(vertical: 11) {
                                HStack(spacing: 12) {
                                    Image(systemName: stop.glyph)
                                        .font(.system(size: 14))
                                        .foregroundStyle(WP.accent700)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stop.name).font(WP.rowTitle(15))
                                            .multilineTextAlignment(.leading)
                                        Text("mile \(stop.mile) · \(stop.kind.title.lowercased())")
                                            .font(WP.body(11.5)).opacity(0.62).tnum()
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                                        .font(.system(size: 14)).foregroundStyle(WP.accent700)
                                }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.995))
                    }
                }
            }
        }
        .task(id: leg.id) {
            guard LegStops.isLive(driveDate) else { return }
            LegStops.shared.load(leg, electric: app.vehicleIsElectric)
        }
    }

    private func routedLegBody(_ leg: TripRouting.Leg, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(WP.body(12)).tracking(1.5).foregroundStyle(WP.accent700)
            Text("\(leg.from) → \(leg.to)").font(WP.heading(23)).padding(.top, 9)
                .multilineTextAlignment(.leading)

            legStops(leg)

            HStack(spacing: 0) {
                legStat("Distance", "\(leg.miles) mi")
                legStat("Wheel time", leg.drive)
                legStat("Roads", String(leg.road.split(separator: " → ").count))
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }

            Text(leg.road).font(WP.body(13)).lineSpacing(3).opacity(0.8).padding(.top, 11)

            GlowButton(title: "Open in Maps", minHeight: 48) {
                openInMaps(from: leg.from, to: leg.to)
            }
            .padding(.top, 16)

            SourceLine("Distance and wheel time from OSRM, driving profile, over the roads listed. No traffic, no departure time — this is the road, not the day.")
                .padding(.top, 16)
        }
    }

    private func openInMaps(from: String, to: String) {
        let query = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? to
        if let url = URL(string: "http://maps.apple.com/?daddr=\(query)&dirflg=d") {
            UIApplication.shared.open(url)
        }
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

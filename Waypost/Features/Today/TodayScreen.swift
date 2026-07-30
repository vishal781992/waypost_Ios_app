import SwiftUI

/// Today — the day you are actually living in. The web app had no such screen; on the
/// phone it is the front door, and it takes one of three shapes.
struct TodayScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    switch app.take {
                    case .field: FieldTake()
                    case .timeline: TimelineTake()
                    case .dash: DashboardTake()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 16)
                .padding(.bottom, WP.tabBarClearance)
                .id(app.take)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        ScreenHeader {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(app.today.d) of \(app.library.days.count) · Denver → Zion loop")
                        .kickerStyle()
                        .lineLimit(1)
                    Text(app.today.long)
                        .font(WP.heading(31))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                dayStepper
            }
            .frame(minHeight: 52, alignment: .top)
        }
    }

    private var dayStepper: some View {
        HStack(spacing: 4) {
            stepButton("chevron.left", -1)
            stepButton("chevron.right", 1)
        }
        .padding(3)
        .background(.white.opacity(0.5), in: Capsule())
        .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
    }

    private func stepButton(_ symbol: String, _ delta: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { app.stepDay(delta) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WP.accent700)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

// MARK: - Take 1 · the field card

struct FieldTake: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let park = app.todayPark {
            ParkOfTheDayCard(park: park)
        }
        if let leg = app.todayLeg {
            DrivingDayCard(leg: leg)
        }

        TheDayList()

        if let park = app.todayPark, let alert = park.alerts.first {
            AlertBanner(park: park, alert: alert)
        }

        if let drop = app.permitDrop {
            PermitWindowCard(drop: drop)
        }

        if let next = app.nextLegDay {
            NextLegBlock(day: next.day, leg: next.leg)
        }

        if let pack = app.packSuggestion {
            OfflinePackCard(park: pack)
        }

        if let park = app.todayPark, let stamp = park.stamps.first {
            StampNudge(stamp: stamp)
        }

        FieldJournal()
    }
}

/// The hero: where you are, in the park's own colours, with the day's numbers beneath.
struct ParkOfTheDayCard: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark

    private var light: WeatherLight { WeatherLight(high: park.wx.hi) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.openPark(park.code)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    BlobField(colors: park.c.map { Color(css: $0) })

                    VStack(alignment: .leading, spacing: 3) {
                        Kicker(text: "Where you are", color: .white.opacity(0.88), size: 9.5)
                        Text(park.name)
                            .font(WP.heading(34))
                            .foregroundStyle(.white)
                            .shadow(color: Color(hex: 0x181008, opacity: 0.28), radius: 10, y: 1)
                        Text("Day \(app.today.n ?? 1) of \(app.today.of ?? 1) in park · \(park.gw)")
                            .font(WP.bodyItalic(12))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(.onPhoto, radius: 18)
                    .padding(10)

                    HStack(spacing: 6) {
                        Circle().fill(WP.live).frame(width: 6, height: 6)
                        Text("All feeds live")
                            .font(WP.body(11.5))
                            .foregroundStyle(.white)
                            .shadow(color: Color(hex: 0x181008, opacity: 0.5), radius: 6)
                    }
                    .padding(.trailing, 15)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x1E1208, opacity: 0.2), radius: 17, y: 14)
            }
            .buttonStyle(PressStyle(scale: 0.995))

            // The four numbers that matter before you leave the room.
            HStack(spacing: 0) {
                statCell("High", "\(park.wx.hi)°")
                statCell("Low", "\(park.wx.lo)°")
                statCell("UV", park.wx.uvIndex)
                statCell("Sunset", park.wx.ss.replacingOccurrences(of: " pm", with: ""))
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }

            HStack(spacing: 8) {
                Circle().fill(light.color).frame(width: 9, height: 9)
                Text(light.label).font(WP.bodyItalic(12.5)).opacity(0.78)
            }
            .padding(.top, 9)
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(WP.body(11))
                .tracking(1.3)
                .foregroundStyle(WP.neutral900)
            Text(value).font(WP.heading(25)).tnum()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

/// A driving day gets the ink plate, the photograph you dropped in behind it out of focus,
/// and the leg's numbers on glass.
struct DrivingDayCard: View {
    @Environment(AppState.self) private var app
    var leg: CuratedLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                WP.ink

                // The design blurs a dropped photo here. Without one it keeps the plate,
                // with a dusk wash rather than a stand-in image.
                ButtonGlow(strong: true).opacity(0.5)

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.26), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.34),
                        .init(color: .clear, location: 0.54),
                        .init(color: .white.opacity(0.10), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "Driving day", color: .white.opacity(0.95), size: 10)
                        HStack(spacing: 6) {
                            Text(leg.from)
                            Text("→").foregroundStyle(WP.accent400)
                            Text(leg.to)
                        }
                        .font(WP.heading(26))
                        .foregroundStyle(.white)

                        HStack(spacing: 18) {
                            legStat("Distance", "\(leg.mi) mi")
                            legStat("Wheel time", leg.drive)
                        }
                        .padding(.top, 12)
                        .overlay(alignment: .top) {
                            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(.onPhoto, radius: 18)

                    Text(leg.road)
                        .font(WP.body(12.5))
                        .foregroundStyle(WP.bg.opacity(0.85))
                        .padding(.horizontal, 2)
                        .padding(.top, 12)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color(hex: 0x180F08, opacity: 0.2), radius: 17, y: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text("Charge stops on this leg".uppercased())
                    .font(WP.body(12))
                    .tracking(1.5)
                    .foregroundStyle(WP.accent700)
                    .padding(.bottom, 4)
                ForEach(leg.ev, id: \.self) { stop in
                    DividedRow(vertical: 9) {
                        HStack(alignment: .top, spacing: 9) {
                            Text("⚡").foregroundStyle(WP.accent)
                            Text(stop).font(WP.body(13)).lineSpacing(2)
                        }
                    }
                }
                Text(leg.fly.map { "\($0.via) · \($0.time)" } ?? "No flight beats the drive on this leg")
                    .font(WP.bodyItalic(12))
                    .opacity(0.6)
                    .padding(.top, 9)
            }
        }
    }

    private func legStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(WP.body(9))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value).font(WP.heading(20)).foregroundStyle(.white).tnum()
        }
    }
}

/// The day's plan as a tick list. Ticking one taps back.
struct TheDayList: View {
    @Environment(AppState.self) private var app

    private var items: [(key: String, time: String, text: String)] {
        let today = app.today
        if let park = app.todayPark {
            let index = min(max((today.n ?? 1) - 1, 0), max(park.days.count - 1, 0))
            let plan = park.days.isEmpty ? nil : park.days[index]
            return (plan?.items ?? []).enumerated().map { offset, item in
                (park.code + String(offset), item.time, item.text)
            }
        }
        if let leg = app.todayLeg {
            let rows = [
                ("7:30 am", "Coffee, ice, top up the battery before the highway"),
                ("9:00 am", "Roll — \(leg.road)"),
                ("1:15 pm", "Charge and lunch at the halfway stop"),
                ("4:40 pm", "Check in, then the gateway town for dinner"),
            ]
            return rows.enumerated().map { offset, row in ("leg" + String(offset), row.0, row.1) }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledHeading(title: "The day") {
                Text("\(items.filter { app.doneItems.contains($0.key) }.count) of \(items.count) done")
                    .font(WP.body(11))
                    .opacity(0.55)
            }
            .padding(.bottom, 5)

            ForEach(items, id: \.key) { item in
                let done = app.doneItems.contains(item.key)
                Button {
                    app.toggleDone(item.key)
                } label: {
                    DividedRow(vertical: 11) {
                        HStack(alignment: .top, spacing: 11) {
                            ZStack {
                                Circle()
                                    .strokeBorder(done ? WP.accent : WP.neutral400, lineWidth: 1.5)
                                Circle().fill(done ? WP.accent : .clear)
                                if done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 19, height: 19)
                            .padding(.top, 1)

                            Text(item.time)
                                .font(WP.heading(14, semibold: true))
                                .foregroundStyle(WP.accent700)
                                .frame(width: 56, alignment: .leading)
                                .padding(.top, 1)

                            Text(item.text)
                                .font(WP.body(13.5))
                                .lineSpacing(2)
                                .strikethrough(done)
                                .multilineTextAlignment(.leading)
                        }
                        .opacity(done ? 0.42 : 1)
                    }
                }
                .buttonStyle(PressStyle(scale: 0.995))
            }
        }
    }
}

struct AlertBanner: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark
    var alert: CuratedAlert

    var body: some View {
        Button {
            app.sheet = .alert(park: park.name, alert: alert)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(alert.cat.uppercased())
                        .font(WP.body(9.5))
                        .tracking(1.4)
                        .foregroundStyle(Color(oklch: 0.45, 0.16, 27))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(oklch: 0.45, 0.16, 27))
                }
                Text(alert.title).font(WP.heading(18))
                Text(alert.body).font(WP.body(12.5)).lineSpacing(2).opacity(0.8)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(oklch: 0.96, 0.03, 27), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(oklch: 0.86, 0.07, 27), lineWidth: 1))
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }
}

struct PermitWindowCard: View {
    @Environment(AppState.self) private var app
    var drop: PermitDrop

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permit window".uppercased())
                .font(WP.body(12))
                .tracking(1.5)
                .foregroundStyle(WP.accent700)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(drop.what).font(WP.body(13.5)).lineSpacing(1)
                    Text(drop.when).font(WP.bodyItalic(12)).opacity(0.65)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(drop.countdown).font(WP.heading(26)).tnum()
                    Text("to go".uppercased())
                        .font(WP.body(9.5)).tracking(1).opacity(0.5)
                }
            }
            .padding(.top, 6)

            GlowButton(
                title: app.notifyPermits ? "✓  Alert set" : "Notify me",
                filled: false,
                strongGlow: app.notifyPermits,
                minHeight: 48
            ) {
                app.sheet = .permit(drop: drop)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
    }
}

struct NextLegBlock: View {
    @Environment(AppState.self) private var app
    var day: CuratedDay
    var leg: CuratedLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledHeading(title: "Next leg") {
                Text(day.date).font(WP.body(11)).opacity(0.55)
            }
            .padding(.bottom, 5)

            Button {
                app.sheet = .leg(index: day.leg ?? 0, date: day.date)
            } label: {
                DividedRow(vertical: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(leg.from)
                            Text("→")
                            Text(leg.to)
                        }
                        .font(WP.heading(19))
                        Text("\(leg.mi) mi · \(leg.drive) · \(leg.ev.count) charge stops")
                            .font(WP.body(12.5)).opacity(0.7).tnum()
                    }
                }
            }
            .buttonStyle(PressStyle(scale: 0.995))

            Button {
                app.toggleLiveActivity()
            } label: {
                Text(app.liveActivityOn ? "Live Activity on" : "Start Live Activity")
                    .font(WP.headingUI(14.5))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(app.liveActivityOn ? WP.accent100 : .clear, in: Capsule())
                    .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
                    .foregroundStyle(app.liveActivityOn ? WP.accent800 : WP.text)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .padding(.top, 11)

            if app.liveActivityOn {
                LockScreenPreview(leg: leg)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
    }
}

/// What the drive looks like on the lock screen while it is running.
struct LockScreenPreview: View {
    var leg: CuratedLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("Lock screen".uppercased())
                    .font(WP.body(9)).tracking(1.3).opacity(0.55)
                Spacer(minLength: 0)
                Text("Waypost").font(WP.headingUI(11)).foregroundStyle(WP.accent400)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.to).font(WP.body(12.5)).opacity(0.75)
                    Text("arrive 3:20 pm").font(WP.heading(23))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(leg.mi) mi").font(WP.body(11)).opacity(0.6)
                    Text("\(leg.ev.count) charge stops").font(WP.body(11)).opacity(0.6)
                }
            }
            .padding(.top, 10)

            ProgressTrack(fraction: 0.34, tint: WP.accent400)
                .padding(.top, 11)
        }
        .foregroundStyle(WP.bg)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(WP.ink, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct OfflinePackCard: View {
    @Environment(AppState.self) private var app
    var park: CuratedPark

    private var state: PackState { app.packState(park.code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(park.name) pack").font(WP.headingUI(17))
                    Text(state == .ready
                         ? "Maps, alerts, day plans and campsites — no signal needed"
                         : "Cell service dies past the gate. Take it with you.")
                        .font(WP.body(12)).opacity(0.68).lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    app.startPack(park.code)
                } label: {
                    Text(state == .ready ? "Downloaded" : state == .busy ? "Downloading" : "Download")
                        .font(WP.headingUI(13))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .overlay(Capsule().stroke(WP.divider, lineWidth: 1))
                        .foregroundStyle(WP.accent700)
                }
                .buttonStyle(PressStyle(scale: 0.96))
            }

            if state == .busy {
                ProgressTrack(fraction: app.packProgress[park.code] ?? 0)
                    .padding(.top, 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(WP.neutral400)
        )
    }
}

struct StampNudge: View {
    @Environment(AppState.self) private var app
    var stamp: CuratedStamp

    var body: some View {
        Button {
            app.sheet = .stamp(name: stamp.name, city: stamp.city, dist: stamp.dist)
        } label: {
            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: 12) {
                    Text("stamp")
                        .font(WP.headingUI(10))
                        .foregroundStyle(WP.accent700)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                                .foregroundStyle(WP.accent400)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Kicker(text: "Passport, \(stamp.dist) away")
                        Text(stamp.name).font(WP.heading(17))
                        Text(stamp.city).font(WP.bodyItalic(12)).opacity(0.6)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WP.accent700)
                }
                .padding(.vertical, 12)
                Hairline()
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }
}

/// Photographs pinned to the day they were shot.
struct FieldJournal: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RuledHeading(title: "Field journal") {
                Button { app.addJournalPhoto() } label: {
                    Text("Add photo +").font(WP.headingUI(13)).foregroundStyle(WP.accent700)
                }
                .buttonStyle(PressStyle(scale: 0.94))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                ForEach(0..<app.journalCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        ZStack {
                            WP.neutral200
                            Text("Drop a photograph")
                                .font(WP.bodyItalic(11))
                                .foregroundStyle(WP.neutral600)
                                .multilineTextAlignment(.center)
                                .padding(6)
                        }
                        .frame(height: 106)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(WP.divider, lineWidth: 1))
                        Text(index == 0 ? "This morning" : "Golden hour")
                            .font(WP.bodyItalic(10.5)).opacity(0.55)
                    }
                }
            }
        }
    }
}

// MARK: - Take 2 · the timeline

struct TimelineTake: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let park = app.todayPark {
            let light = WeatherLight(high: park.wx.hi)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Where you are".uppercased())
                            .font(WP.body(12)).tracking(1.5).foregroundStyle(WP.accent700)
                        Text(park.name).font(WP.heading(29))
                        Text("Day \(app.today.n ?? 1) of \(app.today.of ?? 1) in park · \(park.gw)")
                            .font(WP.bodyItalic(12)).opacity(0.68)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(park.wx.hi)°").font(WP.heading(30)).tnum()
                        HStack(spacing: 5) {
                            Circle().fill(light.color).frame(width: 7, height: 7)
                            Text("UV \(park.wx.uvIndex)").font(WP.body(11)).opacity(0.6)
                        }
                    }
                }
                .padding(.bottom, 14)
                Hairline()
            }
        }

        TimelineRail()

        if let park = app.todayPark {
            Text(park.wx.note)
                .font(WP.bodyItalic(12.5))
                .lineSpacing(3)
                .opacity(0.85)
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 12))
        }

        if let next = app.nextLegDay {
            Button {
                app.sheet = .leg(index: next.day.leg ?? 0, date: next.day.date)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Hairline().padding(.bottom, 9)
                    Text("Tomorrow after that · \(next.day.date)".uppercased())
                        .font(WP.body(12)).tracking(1.4).foregroundStyle(WP.accent700)
                    Text("\(next.leg.from) → \(next.leg.to)").font(WP.heading(20))
                    Text("\(next.leg.mi) mi · \(next.leg.drive) · \(next.leg.ev.count) charge stops")
                        .font(WP.body(12.5)).opacity(0.68).tnum()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PressStyle(scale: 0.99))
        }
    }
}

/// The day as a vertical rail with dots — the same items, read as a sequence.
struct TimelineRail: View {
    @Environment(AppState.self) private var app

    private var items: [(key: String, time: String, text: String)] {
        let today = app.today
        if let park = app.todayPark, !park.days.isEmpty {
            let index = min(max((today.n ?? 1) - 1, 0), park.days.count - 1)
            return park.days[index].items.enumerated().map { (park.code + String($0.offset), $0.element.time, $0.element.text) }
        }
        if let leg = app.todayLeg {
            return [
                ("leg0", "7:30 am", "Coffee, ice, top up the battery"),
                ("leg1", "9:00 am", "Roll — \(leg.road)"),
                ("leg2", "1:15 pm", "Charge and lunch at the halfway stop"),
                ("leg3", "4:40 pm", "Check in, then the gateway town for dinner"),
            ]
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.key) { item in
                let done = app.doneItems.contains(item.key)
                Button {
                    app.toggleDone(item.key)
                } label: {
                    HStack(alignment: .top, spacing: 0) {
                        ZStack(alignment: .top) {
                            Rectangle().fill(WP.divider).frame(width: 1)
                            Circle()
                                .strokeBorder(done ? WP.accent : WP.neutral400, lineWidth: 1.5)
                                .background(Circle().fill(done ? WP.accent : WP.bg))
                                .frame(width: 11, height: 11)
                                .padding(.top, 19)
                        }
                        .frame(width: 11)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.time.uppercased())
                                .font(WP.body(11)).tracking(1.1).foregroundStyle(WP.accent700)
                            Text(item.text)
                                .font(WP.heading(18))
                                .lineSpacing(2)
                                .strikethrough(done)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.leading, 20)
                        .padding(.vertical, 14)
                        .opacity(done ? 0.42 : 1)

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(PressStyle(scale: 0.995))
            }

            if let drop = app.permitDrop {
                HStack(alignment: .top, spacing: 0) {
                    Circle().fill(WP.accent200).frame(width: 11, height: 11).padding(.top, 19)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drop.when.uppercased())
                            .font(WP.body(11)).tracking(1.1).foregroundStyle(WP.accent700)
                        Text("\(drop.what) — \(drop.countdown) from now")
                            .font(WP.heading(18)).lineSpacing(2)
                            .multilineTextAlignment(.leading)
                        GlowButton(title: app.notifyPermits ? "✓  Alert set" : "Notify me",
                                   filled: false, strongGlow: app.notifyPermits, minHeight: 40) {
                            app.sheet = .permit(drop: drop)
                        }
                        .frame(maxWidth: 190)
                        .padding(.top, 9)
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, 14)
                    Spacer(minLength: 0)
                }
                .overlay(alignment: .top) { Hairline() }
            }
        }
    }
}

// MARK: - Take 3 · the dashboard

struct DashboardTake: View {
    @Environment(AppState.self) private var app

    private struct Tile: Identifiable {
        var id: String
        var label: String
        var value: String
        var sub: String
        var dot: Color
        var ramp: Ramp
        var action: () -> Void
    }

    private var tiles: [Tile] {
        let park = app.todayPark
        let light = WeatherLight(high: park?.wx.hi ?? 74)
        let drop = app.permitDrop
        let next = app.nextLegDay
        let pack = app.packSuggestion
        let packReady = pack.map { app.packState($0.code) == .ready } ?? false
        let stamp = park?.stamps.first

        return [
            Tile(id: "wx", label: "Conditions", value: "\(park?.wx.hi ?? 74)°",
                 sub: park?.wx.uv ?? "Fair", dot: light.color,
                 ramp: (park?.wx.hi ?? 74) >= 95 ? .ember : (park?.wx.hi ?? 74) >= 84 ? .brass : .sage,
                 action: { if let park { app.openPark(park.code, segment: .weather) } }),
            Tile(id: "drop", label: "Permit drop", value: drop?.countdown ?? "—",
                 sub: drop?.when ?? "Nothing pending", dot: WP.accent,
                 ramp: drop == nil ? .dust : .brass,
                 action: { if let drop { app.sheet = .permit(drop: drop) } }),
            Tile(id: "leg", label: next.map { "Next leg · \($0.day.date)" } ?? "Next leg",
                 value: next?.leg.drive ?? "—",
                 sub: next.map { "\($0.leg.mi) mi · \($0.leg.ev.count) charge stops" } ?? "Home",
                 dot: Color(oklch: 0.60, 0.10, 240), ramp: next == nil ? .dust : .dusk,
                 action: { if let next { app.sheet = .leg(index: next.day.leg ?? 0, date: next.day.date) } }),
            Tile(id: "pack", label: "Offline",
                 value: pack.map { packReady ? "Ready" : $0.pack } ?? "—",
                 sub: pack.map { "\($0.name) pack" } ?? "Nothing queued",
                 dot: packReady ? WP.live : WP.neutral500, ramp: packReady ? .sage : .dust,
                 action: { if let pack { app.startPack(pack.code) } }),
            Tile(id: "pass", label: "Passport", value: "\(app.stamps.count) / 63",
                 sub: stamp.map { "\($0.name.replacingOccurrences(of: " NM", with: "").replacingOccurrences(of: " NP", with: "")) · \($0.dist)" } ?? "Nothing nearby",
                 dot: WP.accent600, ramp: .plum,
                 action: { app.savedShowsPassport = true; app.go(.saved) }),
            Tile(id: "jour", label: "Journal", value: "\(app.journalCount) shots",
                 sub: "Pinned to day \(app.today.d)", dot: WP.neutral600, ramp: .sepia,
                 action: { app.take = .field }),
        ]
    }

    var body: some View {
        if let park = app.todayPark {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(park.name).font(WP.heading(26))
                Spacer(minLength: 0)
                Text("Day \(app.today.n ?? 1) of \(app.today.of ?? 1) · \(park.gw)")
                    .font(WP.bodyItalic(11.5)).opacity(0.6)
            }
        }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(tiles) { tile in
                Button(action: tile.action) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Circle().fill(tile.dot).frame(width: 7, height: 7)
                            Text(tile.label.uppercased())
                                .font(WP.body(9)).tracking(1.1).opacity(0.6).lineLimit(1)
                        }
                        Text(tile.value).font(WP.heading(25)).tnum().padding(.top, 8)
                        Spacer(minLength: 6)
                        Text(tile.sub).font(WP.body(11)).opacity(0.82).lineSpacing(1)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .padding(13)
                    .background {
                        ZStack {
                            WP.neutral100
                            RampCorner(ramp: tile.ramp)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }
        }

        VStack(alignment: .leading, spacing: 0) {
            TheDayList()
        }
        .padding(.top, 6)
    }
}

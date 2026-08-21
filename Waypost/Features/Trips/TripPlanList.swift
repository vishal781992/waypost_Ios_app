import SwiftUI

/// My list — the trip's third tab.
///
/// Not a catalogue the app assembled. Everything here was put on by hand, by pressing
/// *add* on a row somewhere else in the trip: a charger before the climb, the last shop
/// before the gate, the café in the gateway town, the permit page, a note about the shuttle
/// selling out by seven. The other two tabs are what the trip *is*; this is what the
/// traveller decided about it.
///
/// Grouped by the day each thing is for, on the same date spine the Days tab uses, so the
/// two read as the same trip. Undated things sit above the first day — a packing document
/// is not a Tuesday thing, and making somebody file it under one would be a small lie.
struct TripPlanList: View {
    @Environment(AppState.self) private var app
    var trip: SavedTrip

    /// Which day the add sheet is opening for. Nil while it is shut.
    @State private var adding: AddTarget?
    /// Whether the "clear the whole list" question is showing.
    @State private var confirmingClear = false

    private var items: [PlanItem] { app.plan(for: trip.id) }

    /// The days of the trip, from the same plan the Days tab draws — so a list day and a
    /// trip day are the same day, in the same order, with the same label.
    private var days: [TripDays.Day] {
        if case .ready(let days) = TripDays.shared.state(for: trip) { return days }
        return []
    }

    /// Everything with no day of its own: for the whole trip rather than for a Tuesday.
    private var undated: [PlanItem] { items.filter { $0.day == nil } }

    /// The first day with nothing on it, which is the only one that explains itself.
    private var firstEmptyDay: Date? {
        days.compactMap(\.date).first { items(on: $0).isEmpty }
    }

    private func items(on date: Date) -> [PlanItem] {
        items.filter { $0.day.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                empty
            } else {
                if !undated.isEmpty {
                    header(title: "Anytime on this trip", day: nil)
                    ForEach(undated) { row($0) }
                    Rectangle().fill(WP.divider).frame(height: 1).padding(.vertical, 11)
                }

                ForEach(days) { day in
                    if let date = day.date {
                        header(title: label(day), date: date, day: date)
                        let onThisDay = items(on: date)
                        if onThisDay.isEmpty {
                            // Said once, on the first empty day. A fortnight's trip printed
                            // this fourteen times, which is a paragraph of apology where a
                            // list should be.
                            if date == firstEmptyDay {
                                Text("Nothing here yet — add from any list on this trip.")
                                    .font(WP.bodyItalic(11.5)).opacity(0.5)
                                    .padding(.bottom, 4)
                            }
                        } else {
                            ForEach(onThisDay) { row($0) }
                        }
                        Rectangle().fill(WP.divider).frame(height: 1).padding(.vertical, 11)
                    }
                }

                SourceLine(count)

                // Low and quiet, at the end of the list rather than beside the controls
                // that use it. Clearing is rare, destructive and has no undo, so it does
                // not sit where a thumb rests.
                Button {
                    confirmingClear = true
                } label: {
                    Text("Clear this list")
                        .font(WP.body(13))
                        .foregroundStyle(WP.danger)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .padding(.top, 2)
            }
        }
        .alert("Clear this list?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                withAnimation(Motion.panel) { app.clearPlan(trip.id) }
            }
        } message: {
            Text("All \(items.count) thing\(items.count == 1 ? "" : "s") come off — the places you added, and the links and notes you wrote. This cannot be undone.")
        }
        .sheet(item: $adding) { target in
            AddYourOwnSheet(trip: trip.id, day: target.day, label: target.label)
                // The same presentation every other sheet in the app uses: the phone's own
                // display corner rather than the system's tighter default, a clear ground
                // so the sheet's own paper is what shows, and a drag indicator.
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(WP.sheetCorner)
        }
    }

    // MARK: Nothing on it yet

    private var empty: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Your list is empty")
                .font(WP.display(22))
            Text("Every list on this trip — charging, fuel, shops, campgrounds, beds and food — has an add beside each row. What you add lands here, under the day you will use it.")
                .font(WP.body(13)).opacity(0.7).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                adding = AddTarget(day: nil, label: "this trip")
            } label: {
                Text("Add a link or a note")
                    .font(WP.body(13, semibold: true))
                    .foregroundStyle(WP.text)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(WP.book, in: Capsule())
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .padding(.top, 4)
        }
        .padding(.vertical, 18)
    }

    // MARK: A day's heading

    private func label(_ day: TripDays.Day) -> String {
        switch day.kind {
        case .travel(let from, let to, _, _, _): return "\(from) → \(to)"
        case .park(_, let name, let number, let of): return "\(name) · day \(number) of \(of)"
        }
    }

    private func header(title: String, date: Date? = nil, day: Date?) -> some View {
        // Centred, not baseline-aligned. On a baseline the row's height came from the 11pt
        // date, so the 44pt target overflowed the row and everything outside it stopped
        // answering — the plus looked like a control and behaved like a picture, except
        // for the few points that happened to overlap the line of text.
        HStack(alignment: .center, spacing: 8) {
            if let date {
                Text(Self.dayLabel.string(from: date))
                    .font(WP.body(11.5)).foregroundStyle(WP.accent700)
            }
            Text(title.uppercased())
                .font(WP.body(9.5)).tracking(1.3).opacity(0.55)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                adding = AddTarget(day: day, label: date.map { Self.dayLabel.string(from: $0) } ?? "this trip")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WP.accent700)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(WP.text.opacity(0.22), lineWidth: 0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.92))
            .accessibilityLabel("Add a link or note to \(title)")
        }
        .padding(.bottom, 2)
    }

    private static let dayLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        return formatter
    }()

    // MARK: One item

    private func row(_ item: PlanItem) -> some View {
        // The menu is a visible control on every row, not a swipe. `swipeActions` compiles
        // outside a `List` and does nothing at all — this list is a `VStack` in a
        // `ScrollView`, so the swipe drawn in the design was inert and the only way to take
        // anything off was a long press nobody would ever find.
        HStack(spacing: 2) {
            Group {
                switch item.kind {
                case .place(let place): placeRow(item, place)
                case .link(let url): LinkCard(url: url)
                case .note(let text): noteRow(text)
                }
            }
            menu(item)
        }

    }


    /// Move and remove, on a control that can be seen.
    ///
    /// Everything on this list was put here by hand, so taking it off again has to be as
    /// easy as putting it on — and a menu that only opens on a long press is a feature most
    /// readers never learn exists.
    private func menu(_ item: PlanItem) -> some View {
        Menu {
            if item.isPlace {
                Button {
                    app.togglePlanStop(trip.id, itemID: item.id)
                } label: {
                    Label(item.isStop ? "Don't drive to this" : "Drive to this",
                          systemImage: item.isStop ? "car.slash" : "car.fill")
                }
            }

            Menu("Move to…") {
                ForEach(days) { day in
                    if let date = day.date {
                        Button(Self.dayLabel.string(from: date)) {
                            withAnimation(Motion.panel) {
                                app.movePlanItem(trip.id, itemID: item.id, to: date)
                            }
                        }
                    }
                }
                Button("Anytime on this trip") {
                    withAnimation(Motion.panel) {
                        app.movePlanItem(trip.id, itemID: item.id, to: nil)
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(Motion.panel) {
                    app.removeFromPlan(trip.id, itemID: item.id)
                }
            } label: { Label("Remove", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WP.text.opacity(0.45))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Options")
    }

    private func placeRow(_ item: PlanItem, _ place: PlannedPlace) -> some View {
        HStack(spacing: 10) {
            Image(systemName: place.kind?.glyph ?? "mappin")
                .font(.system(size: 13))
                .foregroundStyle(place.kind?.tint ?? WP.accent700)
                .frame(width: 26, height: 26)
                .background(place.kind?.tintSoft ?? WP.accent100, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).font(WP.rowTitle(14.5)).multilineTextAlignment(.leading)
                Text(place.subtitle)
                    .font(WP.body(11)).foregroundStyle(place.kind?.tint ?? WP.accent700)
            }
            Spacer(minLength: 0)

            // Only a place can be driven to, so only a place is offered as a stop. Off
            // leaves it on the list and out of the route — "I am not going" and "I do not
            // need directions to it" are different, and the list can say both.
            //
            // A car, not a tick. A checkmark here read as "done" — the one thing this
            // control does not mean.
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    app.togglePlanStop(trip.id, itemID: item.id)
                }
            } label: {
                Image(systemName: item.isStop ? "car.fill" : "car")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isStop ? WP.accent700 : WP.text.opacity(0.25))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityLabel(item.isStop
                ? "\(place.name) is a stop on the drive"
                : "\(place.name) is not a stop on the drive")
        }
        .padding(.vertical, 3)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "pencil")
                .font(.system(size: 12))
                .foregroundStyle(WP.accent700)
                .padding(.top, 2)
            Text(text)
                .font(WP.body(12.5)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(WP.onInk, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(WP.divider, lineWidth: 1))
        .padding(.vertical, 3)
    }

    private var count: String {
        let places = items.filter(\.isPlace).count
        let own = items.count - places
        var parts: [String] = []
        if places > 0 { parts.append("\(places) place\(places == 1 ? "" : "s")") }
        if own > 0 { parts.append("\(own) of your own") }
        return parts.joined(separator: " · ")
            + ". Places come from the lists on this trip; links and notes are yours."
    }
}

/// Which day the add sheet is opening for.
private struct AddTarget: Identifiable {
    var day: Date?
    var label: String
    var id: String { label }
}

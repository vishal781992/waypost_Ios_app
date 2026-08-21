import MapKit
import SwiftUI

/// The control that puts a place on a trip's list.
///
/// Drawn only where there is a trip to add to. The same charging row appears on a park
/// opened from the home screen and on one opened from a trip; only the second offers,
/// because only the second has a list behind it.
///
/// One control, both directions: pressing it again takes the place off. A row that could
/// add but never remove would leave the only way to undo a mis-tap on another screen.
struct AddToPlanButton: View {
    @Environment(AppState.self) private var app
    @Environment(\.planningTrip) private var trip

    @Environment(\.planningDay) private var screenDay

    var place: PlannedPlace
    /// The day this row knows about — a driving day's stops are for that day. When the row
    /// does not know, the screen usually does: a park opened from a trip was opened for the
    /// day the trip reaches it. Only when neither knows does it go undated.
    var day: Date?

    var body: some View {
        if let trip {
            let added = app.planContains(trip, place: place)
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    app.togglePlanPlace(trip, place: place, day: day ?? screenDay)
                }
            } label: {
                // Added, it is a tick and nothing else.
                //
                // "Added" is a longer word than "Add" in a row that has no more width to
                // give, so it wrapped — a capsule containing "Add / ed" over two lines. The
                // state does not need the word anyway: a lime capsule with a tick in it
                // says the thing has been taken, and it is the state a reader spends most
                // of their time looking at.
                HStack(spacing: 5) {
                    Image(systemName: added ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                    if !added {
                        Text("Add")
                            .font(WP.body(11.5))
                            // Belt and braces: the label never wraps, whatever the row does.
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                // Lime with ink on it once it is on the list; the warm accent tint the
                // icons beside it wear until then. The two states are now two colours
                // rather than a fill appearing under an unchanged mark, and the unadded
                // pill is the same object as its neighbours instead of the one transparent
                // control in a row of tinted ones.
                .foregroundStyle(added ? WP.text : WP.accent800)
                .padding(.horizontal, added ? 0 : 10)
                // Matches `PlaceAction` exactly when it is a tick, so a row of controls
                // reads as one set rather than as a pill among icons.
                .frame(width: added ? 38 : nil, height: 30)
                .background {
                    Capsule().fill(added ? WP.book : WP.accent100)
                    Capsule().stroke(added ? Color.clear : WP.accent600.opacity(0.45),
                                     lineWidth: added ? 0 : 0.75)
                }
                // 30 points of ink, 44 of target — the row is already crowded and the
                // pill cannot grow, so the reach around it does.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.94))
            .accessibilityLabel(added ? "Remove \(place.name) from my list"
                                      : "Add \(place.name) to my list")
        }
    }
}

/// The controls at the end of a place's row, in one order, everywhere.
///
/// There were four arrangements of these across the app — directions before *add* on a park
/// screen because the glyph lived inside the name's own button, after it on a leg sheet,
/// missing entirely on a driving day, and a different order again beside a campground. Four
/// rows that do the same four things should not each teach a different muscle memory.
///
/// The order is fixed and reads left to right as the sequence a reader actually goes
/// through: **put it on my list**, then *ring them*, then *read their page*, then *take me
/// there now*. Add is a labelled pill because it is the one whose state matters and the one
/// with no established glyph; the rest are icons of equal size.
struct PlaceRowActions: View {
    var place: PlannedPlace
    /// The day the row belongs to, when it knows one.
    var day: Date?
    var call: URL?
    var site: URL?
    /// Drawn unless a row's own name already opens directions and a second control would
    /// be the same errand twice.
    var showsDirections: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            AddToPlanButton(place: place, day: day)

            if let call {
                Link(destination: call) { PlaceAction(glyph: "phone.fill") }
                    .accessibilityLabel("Call \(place.name)")
            }

            if let site {
                Link(destination: site) { PlaceAction(glyph: "safari") }
                    .accessibilityLabel("Open the website for \(place.name)")
            }

            if showsDirections {
                Button {
                    place.mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                    ])
                } label: {
                    // `arrow.turn.up.right`, not `arrow.triangle.turn.up.right` — the
                    // latter exists only in its `.circle` and `.diamond` forms, so the
                    // bare name drew an empty box. The circle form would also put a ring
                    // inside `PlaceAction`'s own border.
                    PlaceAction(glyph: "arrow.turn.up.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(place.name)")
            }
        }
    }
}

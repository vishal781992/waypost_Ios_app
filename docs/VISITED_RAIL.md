# Parks visited with ParkHop — agreed design

Part 1 (larger monogram) shipped in v2.27.0.12. Parts 2–4 below are specified and not
started. Decisions recorded here so they are not re-litigated.

## Where visits come from
The union of three sources, deduplicated by park code:
1. **Past trips** — `myTrips` whose dates have passed.
2. **Stamps** — `AppState.stamps`, the passport concept already in the app.
3. **Manual entries** — added through the control in the rail.

No invented visits. A clean install shows an empty rail, which is correct and expected.

## The park picker
Bundled 62 (`NationalParks.all`) first — instant, offline, and they now carry real NPS
codes so photos resolve without a lookup — then live NPS results merged in for anything
not on the phone (monuments, historic sites). Not a separate hard-coded 56: that would
disagree with Discover's "sixty-three parks" and with the trip builder.

## Empty state
The rail always renders. With nothing in it, show a single empty placeholder tile with the
add control beside it, inside the rail. The add control stays at the trailing end of the
rail once there are visits — it is not a full-width pill below it.

## Dates
Derived visits carry the month and year they came from. **Manual entries carry no date** —
the tile shows the park name alone rather than stamping today, which would be inventing a
visit date. The rail is therefore mixed, and that is intended.

## Layout
- Tiles ~132×104, 16pt radius, `ParkImage` with a dark bottom gradient.
- Park name in the display serif (`WP.display`), date beneath in `WP.body`.
- Park count at the right end of the section rule, in `WP.accent700`.
- Horizontal `ScrollView` with the same scroll behaviour as the Discover chip rail.
- Tap a tile → `app.openPark(code)`, which already carries the zoom transition through
  `RootShell`.
- Adding fires the existing toast via `app.show(...)`.

## Persistence
A `Visit { code: String, date: Date? }` list on `AppState`, written into the existing
snapshot as an **optional** field so snapshots saved before this still decode — the same
approach `SavedTrip.originName` uses.

## Known open question
The identity block above this section still shows fabricated data — "Miriam Halloran",
"Trips synced by iCloud · 3 devices" — on a clean install. That is Pain point 2 (P0) and
the iCloud claim is not true of the app. Building a genuinely-sourced visit rail directly
beneath invented personal details is worth resolving at the same time.

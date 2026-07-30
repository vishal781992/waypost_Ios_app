# Waypost for iOS

A native SwiftUI port of [Waypost](https://parkhop.us) — the national- and state-park trip
planner. Pick parks, set a date and an origin, and get a composed itinerary: real weather
for your dates, real campgrounds and stays near the gateway, real drive routes, and a
road-or-air comparison for the long legs.

The web app lives in the sibling repo, `../waypoint`. This one is a separate app, not a
wrapper: the screens are SwiftUI, the datasets are re-generated from the web repo's
modules, and the same sources are called directly.

---

## The rule that shapes everything: never show an invented value

Carried over from the web app, and it is the reason several things here are more awkward
than they would otherwise be:

- **A refusal and an absence are different states.** `NPSService.fetch` returns `nil` when
  a request fails and `[]` when NPS answers with nothing. Collapsing those into one empty
  array is what makes a blocked host read as "no data exists" — so the panels say
  *"NPS did not answer"* when that is what happened, and *"NPS publishes no current
  alerts"* only when NPS actually said so.
- **A live dot is a claim about provenance.** `TripStore.campsAreLive` / `alertsAreLive` /
  `staysAreLive` record which panels were fed by a source that answered. The bundled
  curated record can stand in, but it is badged *Curated*, never *Live*.
- **Availability is never projected.** Recreation.gov blocks most non-browser callers;
  when it refuses, the campground reads *"Availability not published — check
  Recreation.gov"*.
- **UV beyond the forecast window is modelled**, and the cell says `· modelled from solar
  geometry` — ERA5 publishes no UV field, so it is derived and labelled.
- **Failures are recorded, not swallowed.** Every `catch` calls `FailureLog.note`, and the
  trip header names the sources that did not answer.

---

## Building

Requires Xcode 16+ (built against Xcode 26.4) and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate            # writes Waypost.xcodeproj — it is not committed
open Waypost.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project Waypost.xcodeproj -scheme Waypost \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Deployment target is iOS 17 (the app uses `@Observable` and the iOS 17 `Map` API).

---

## Layout

```
Waypost/
  App/          WaypostApp.swift, RootView, the dark app bar, the version badge
  Design/       Theme.swift — the Classical tokens, transcribed from the design system
  Models/       Park, Leg, Stop, WeatherDay, AvailabilityLevel …
  State/        TripStore (all state + every fetch), TripPresentation (derived views)
  Services/     NPS, weather, routing, Overpass, Recreation.gov, the proxy, location
  Features/
    Plan/       PlanView — the Itinerary Desk: parks, date, origin, vehicle
    Trip/       TripView — stats, route map, legs; ParkSection — the six park panels
  Resources/    cities · parks · legs · airports · state-parks (generated JSON)
tools/
  convert-data.mjs   re-generates Resources/*.json from ../waypoint
```

### Datasets

`airports.js`, `state-parks.js` and `parks-data.js` are maintained in the web repo. This
app does not fork them — it converts them:

```sh
node tools/convert-data.mjs [path-to-web-repo]   # defaults to ../waypoint
```

`state-parks.json` is 426 KB and is only read the first time the user switches the source
to state parks, mirroring the web app's dynamic `import()`.

---

## What this pass covers

Built and working:

- **Plan screen** — nearby-park shelf from your location, NPS search (or the bundled
  parks without a proxy), state-park search entirely on-device, day counts per park,
  origin city with suggestions, first-day calendar, drive/fly and gas/EV preferences,
  proxy field.
- **Trip screen** — route line, stats, rough budget, feasibility field notes, a MapKit
  route with the dotted line home, and a leg card per hop with live OSRM mileage, drive
  time, the highway corridor, EV stops and the air option where a real one exists.
- **Park panels** — Overview (reservation, gates, parking, hours & fee, fly-in airports
  ranked from OurAirports, fuel & charging), Weather (live forecast, or 10-year climate
  normals computed for your exact date beyond the forecast window), Camping & stay
  (NPS + Recreation.gov campgrounds with availability, stays for your nights).

Named but not built in this pass — each panel says so rather than looking empty:

- **Day plan** renders when the NPS things-to-do feed answers, and the curated day plans
  for the six bundled parks; it does not yet spread activities by time of day.
- **Passport stamps** (nearby NPS units within 160 miles).
- **Know before you go** shows live alerts; the timed-entry deadlines and `.ics` exports
  are not built.

Also not yet ported: flight schedules and the door-to-door fly-drive model, hotel
availability by night, print/share of field sheets, deep links into a shared trip.

---

## The proxy, and why the live panels may be blank

The Cloudflare Worker in `../waypoint/flights-proxy` holds every API key server-side. It
allowlists **browser origins** (`ALLOWED_ORIGINS` in `wrangler.toml`) and answers anything
else with `403 forbidden`. A native app sends no `Origin` header, so out of the box every
proxy-backed panel here is refused.

The app therefore identifies itself rather than impersonating the website: it sends

```
Origin: app://waypost-ios
X-Waypost-Client: ios
```

To switch the live panels on, add that origin to the worker's allowlist:

```toml
ALLOWED_ORIGINS = "https://parkhop.us,https://www.parkhop.us,https://parkhop-69p.pages.dev,app://waypost-ios"
```

Until then the app runs on the sources that need no key — weather, climate normals, OSRM
routing, OpenStreetMap fuel, the map — and the header names what did not answer. Nothing
is filled in with estimates in the meantime.

---

## Typography

San Francisco, app-wide — Apple's own face, and the one iOS renders best at these sizes.

The Classical design system pairs Cormorant Garamond with Lora, and 2.0 shipped both as
bundled OFL faces. On a phone they read unevenly: the serif loses legibility at the small
sizes the layout leans on, and Cormorant's old-style figures make numerals fight the
labels beside them. 2.1.1 moved to the system face and removed the font files.

The design's *sizes* are unchanged. Cormorant runs small for its point size and SF does
not, so `WP.heading` scales heading sizes by 0.86 — a line that filled its space in the
design still fills it here. Everything routes through `WP.heading` / `WP.body` /
`WP.mono` in `Design/Tokens.swift`, so the face is one edit away if it ever changes again.

**One exception: `WP.display`.** Cormorant Garamond SemiBold, in the two roles big enough
to carry it — a national park's name standing alone over its own colour field, and the
title at the head of a screen. Ten places: the Today hero card (34), the park screen hero
(38), a Discover card (28), the Timeline (29) and Dashboard (26) takes, and the five screen
titles (31). Those sizes are the design's own, with no SF scaling, because they were drawn
in this face.

It is a separate token rather than a flag on `WP.heading` so the rule is enforced by which
function a view calls. Everything smaller stays on SF: park names in lists, the pushed-screen
nav title, trip names, campgrounds and stamps. At 16–19pt the serif thins out, which is the
unevenness 2.1.1 removed. One font file ships (`CormorantGaramond-SemiBold.ttf`).

## Versioning

`VERSION` holds semver and is kept in step with the web repo, so a shared release carries
one number across both apps. `./sync-version.sh` stamps it into `project.yml`
(`MARKETING_VERSION`), which the app reads back out of the bundle for the nav badge —
the version in the UI is never typed by hand. `./sync-version.sh --check` fails on drift.

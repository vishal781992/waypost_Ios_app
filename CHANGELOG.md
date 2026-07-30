# Waypost for iOS — change log

Running record of every change to the iOS app, newest first.

Versions track the web repo (`../waypoint`): the same number means the two apps are built
from the same understanding of the data, not that they have the same features. Semver
lives in `VERSION`, is stamped into `project.yml` by `./sync-version.sh`, and is read back
out of the bundle for the nav badge.

Guiding rule, inherited from the web app: **never show an invented value.** If a source
cannot be reached or publishes nothing, the interface says so rather than substituting a
plausible-looking number.


## 2.1.2 — The serif, in one place

A national park's name is the one line in this app worth setting in the design system's
serif, so `WP.parkDisplay` brings Cormorant Garamond SemiBold back for exactly that: the
Today hero card, the park screen hero, a Discover card, and the Timeline and Dashboard
takes. Five headlines, each a park name alone over its own colour, at the sizes the design
drew them — no SF scaling, because those sizes were drawn in this face.

Everywhere else stays San Francisco, including park names in lists, the pushed-screen
title bar, trip names, and every label and number. That is the split that made 2.1.1
readable, and a separate token keeps it: which face a line gets is decided by which
function the view calls, so it cannot drift back.

One font file ships instead of eight.


## 2.1.1 — San Francisco

The bundled serifs are gone. Cormorant Garamond and Lora are the design system's voice on
a wide screen, but on a phone they read unevenly — the serif thins out at the small sizes
this layout leans on, and Cormorant's old-style figures never sat right beside their
labels even after lining figures were forced on. The app now uses San Francisco
everywhere, including SF Mono for airport codes.

The design's sizes are kept. SF has the larger x-height, so headings are scaled by 0.86
and the layout is unchanged. The font files and their `UIAppFonts` declaration are
removed with the code that registered them; every size still routes through `WP.heading`,
`WP.body` and `WP.mono`.


## 2.1.0 — A brief written on the phone

Discover opens with **Near you**: the parks actually within reach, ranked by real
distance from your location, and a short brief about them written by Apple's on-device
model. Nothing leaves the iPhone — no network call, no account, no server.

**The model is never the source of a fact.** Distances are measured from coordinates in
`NearbyBriefing.rank`; conditions, fees, reservations and alerts come from the field
library. Those are what the prompt contains, and the ranked list renders whether the
model answers, refuses, or is missing from the device.

**Why the guard is as strict as it is.** Given two parks and their real distances, the
first thing the model wrote was that the farther one was *"175 miles closer"*, and that a
park with timed entry *"does not require a permit"*. Confident, fluent, wrong. In an app
whose one rule is never to show an invented value, that cannot reach the screen. So:

- the model is forbidden to write a number at all — the figures are printed beside its
  words by the app — and any sentence containing a digit is dropped rather than shown;
- unquantified comparisons are allowed but checked against the measured ranking, so a
  note calling the second-nearest park "the closest" is dropped;
- every park it names is matched back to the shortlist, so an invented park cannot appear;
- if the headline fails any check, the app substitutes one written from the arithmetic.

**When it cannot run** — no Apple Intelligence, not enabled, model still downloading, or
an older iOS — the card says which of those it is and shows the ranked list anyway.


## 2.0.0 — The native app

A second design round arrived (Claude Design project `2a11fe09`), and it is not a phone
version of the website: it is an iPhone app. Five destinations instead of one long scroll,
the day you are living in given a home of its own, and Liquid Glass throughout. This
release rebuilds the interface on it.

**Five destinations.** Today, Trips, Discover, Saved and Profile, under a floating glass
tab bar. The plan-then-itinerary pair the web app has becomes: Trips → `+` opens a
three-step modal; the itinerary becomes a trip screen with Route / Days / Stays; the six
in-park tabs become one park screen with a scrolling segment rail; "print field sheets"
becomes an offline pack; the proxy field moves to Profile.

**Today** is the new front door, and it takes one of three shapes — a field card, a
timeline, or a dashboard of tiles. It knows whether you are in a park or driving, ticks
off the day's plan with a haptic, counts down the next permit window, previews the next
leg with its Live Activity, offers the offline pack for the park you are heading to, and
nudges you toward the nearest passport stamp.

**Liquid Glass, properly.** On iOS 26 the headers, tab bar, chips and photo plates render
through the system `glassEffect`; below 26 the same surfaces are assembled by hand from a
material, the design's tint, and the two inset highlights that give glass a lit edge.
Plates that sit over a park's colour field always use the hand-built recipe — the system
effect brightens until white type stops reading.

**The real typefaces ship.** Cormorant Garamond, Lora and JetBrains Mono (all OFL) are
bundled as static instances generated from the variable originals. Two rounds of failure
are recorded in the tooling: Google's WOFF files converted by hand produced fonts CoreText
would open and iOS would reject (`GSFont: invalid font file`), and the variable fonts
default to Light. Cormorant also sets old-style figures by default — 11 read as two small
capital I's — so every heading now carries lining, tabular figures.

**Colour is computed, not eyeballed.** The design writes park identities, traffic lights
and dashboard ramps in OKLCH. Those numbers are kept as written and converted through
OKLab at runtime, so Arches is the red the designer chose.

**The field library.** `tools/extract-curated.mjs` lifts the design's own dataset — eight
parks with colours, August normals, gates, campgrounds, day plans and nearby stamps; the
four legs and ten days of the seed trip; the passport book — into `curated.json`. Panels
say it is curated. The live services from 1.9.x are still in the repo and are re-wired
onto these screens next; until then no panel claims to be today's measurement.


## 1.9.1 — First native pass

A SwiftUI port of the mobile design (`Waypost Mobile.dc.html` in the Claude Design
project), sharing the web app's datasets and sources but none of its code.

**Datasets are converted, not forked.** `tools/convert-data.mjs` imports the web repo's
`parks-data.js`, `airports.js` and `state-parks.js` and writes JSON into
`Waypost/Resources`. The six curated parks, the curated legs, the eight origin cities, the
full OurAirports table and all state parks come across verbatim, so the two apps cannot
disagree about what a park is. `state-parks.json` (426 KB) is only read once the user asks
for state parks.

**A refusal and an absence are now different states.** This was the one real fault found
while building. `NPSService.fetch` originally returned an empty array both when the
request failed and when NPS answered with nothing, and the proxy answers this app with
`403` (see below). The result: the Overview panel confidently printed *"NPS publishes no
timed-entry or reservation requirement for this park"* — a claim it had no basis for — and
the tab lit its live dot over a bundled record. The fetch now returns `nil` on failure and
`[]` on a genuine empty answer; `TripStore` records which panels a live source actually
fed (`campsAreLive`, `alertsAreLive`, `staysAreLive`, `npsDidNotAnswer`); badges read
*Live*, *Curated*, *None published* or *Source did not answer* accordingly.

**The app identifies itself to the proxy** with `Origin: app://waypost-ios` and
`X-Waypost-Client: ios` rather than borrowing the website's origin. The worker allowlists
browser origins only, so until `app://waypost-ios` is added to `ALLOWED_ORIGINS` the
NPS-backed panels stay blank and the trip header says why. Weather, climate normals, OSRM
routing, OpenStreetMap fuel and the map need no key and work today.

**Weather keeps the three-source model.** Open-Meteo's 16-day forecast, overlaid by NWS
inside its window, and — beyond the horizon — 10-year climate normals computed from the
ERA5 archive for the same calendar window (±3 days) at the park's own coordinates. UV is
absent from ERA5 and is derived from solar geometry, labelled `· modelled`.

**The route is drawn with MapKit** rather than the web app's d3 state outline: real roads,
stops annotated in visiting order, the way home dotted. This is the one place the port
deliberately diverges — the phone has a map, so it uses it.

**Airports are ranked, not curated.** Every US field with scheduled commercial service,
ranked by real distance; drive time is an estimate and is labelled as one. The hub takes
the "Best" badge only when it isn't much further than the closest field.

Panels named in the design but not built in this pass — Passport stamps, timed-entry
deadlines and calendar exports, the door-to-door fly-drive model, flight schedules, hotel
availability by night, print/share — each say what they are waiting on instead of
rendering an empty section.

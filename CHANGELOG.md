# Waypost for iOS — change log

Running record of every change to the iOS app, newest first.

Versions track the web repo (`../waypoint`): the same number means the two apps are built
from the same understanding of the data, not that they have the same features. Semver
lives in `VERSION`, is stamped into `project.yml` by `./sync-version.sh`, and is read back
out of the bundle for the nav badge.

Guiding rule, inherited from the web app: **never show an invented value.** If a source
cannot be reached or publishes nothing, the interface says so rather than substituting a
plausible-looking number.

Entries below carry a fourth number where one exists — `2.27.0.26` is `MARKETING_VERSION`
followed by `CURRENT_PROJECT_VERSION`, the pair the Profile badge reads out of the bundle
so a tester can say which build they were looking at.


## 2.27.0 — What the sources actually say

The longest run in the log, and most of it is the same argument applied in new places: the
app may show what a source published, or say it could not ask, and nothing in between.

**The profile stops inventing a person** (.14). Every install opened on "Miriam Halloran —
Trips synced by iCloud · 3 devices": a name nobody entered, a device count nobody has, and
a sync that does not exist — there is no account in this app and nothing leaves the phone.
It now counts what is actually held (trips, visited parks, saved parks, stored on this
iPhone; "nothing yet" on a clean install) and derives the monogram from the first parks on
the rail, falling back to a compass rose.

**Six parks stop getting hand-written facts** (.16). `parks.json` carries editorial for
arch, grte, cany, yell, zion and romo and for nobody else — a fee, hours and an August
temperature, written by hand, undated, confirmed by no source. Those six printed
"$30 / vehicle · 7 days · 73° in August" on Discover while the other fifty-six said "Not
published", and the park screen already preferred NPS, so one fee had two strings
depending which screen you opened. The privilege is taken away rather than extended.

**Parks visited with ParkHop** (.12), the rail on Profile. Visits are the union of three
real sources deduplicated by code — a trip whose dates have passed, a passport stamp, and
anything added by hand. Nothing is seeded, so a clean install shows an empty tile beside
the add control, in the rail rather than under it, and the empty state is the same shape
as the full one. A park added by hand carries no date and says so by saying nothing.

**No driving-day card without a trip** (.25). Today drew "Denver to Estes Park, with
charge stops" on a clean install, reading its leg from a curated fixture pinned to day
one — which would have shown forever, unrelated to any real date. Gated on a real trip in
`myTrips` being under way today, by the trip's own dates.

**Fuel, charging, restaurants and traffic on the driving day** (.13, .15, .26). The leg
sheet said "no traffic, no departure time — this is the road, not the day". Apple Maps
supplies both: points of interest sampled along the OSRM polyline the router was already
fetching and discarding, nearest of each kind kept and labelled with the mile it falls at,
charging first for an electric vehicle; and an MKDirections estimate with a departure date,
shown beside OSRM's rather than silently replacing it — OSRM has no traffic data at all.
Only inside the window the drive is real: from the evening before to the end of the day it
is driven, not `isDateInToday`, which showed nothing at eleven at night for a six a.m.
start. Sampling scales to the leg — a 72-mile drive was blank because the first sample sat
at mile 80, and a 2,275-mile leg fired eighty-four searches end to end.

**State parks get an address, a page and a photograph** (.17, .18, .19, .20). NPS covers
its own units and nothing else, so a state park read "Not published" and the screen had
nowhere to send anybody. `state-parks.json` had the answers on disk all along: `w`, the
park's own published page, for 2,299 of them, and `i`, a Wikimedia Commons filename, for
1,821 — both decoded on the way in and dropped before they reached `CuratedPark`, so the
app went and asked Apple Maps for a website it already had and drew a generated colour
tile over a photograph it could have built an address for. Both carried through, Apple Maps
kept as the fallback for the rows with neither. Of what `MKMapItem` does vend, the phone
number and the time zone are now shown (hours, ratings and photographs on the Maps place
card are licensed from Tripadvisor, Foursquare and Wikipedia and are not reachable through
MapKit) and there is a hand-off to Maps for the rest. Commons filenames are stale for some
parks; `ParkImage` draws the colour field beneath the photograph, so a 404 leaves what was
there before.

**Which campground counts come from Recreation.gov** (.21). The record is the park
service's, the "1 free tonight" chip beside it is not. The row carries the label only when
the campground has a Recreation.gov facility id, which is exactly when the chip can exist.

**Discover and the builder open on what is near** (.9, .11), ranked by distance from the
device, keeping the curated order when location is refused — both showed the same
hard-coded eight whether the phone was in Denver or in Maine, and Discover did not offer
the other fifty-four bundled parks until something was typed. The + on Trips now goes
straight to the builder instead of asking "which park?" first.

**Onboarding** (.22, .23, .24): Welcome and the identity choice over the Monument Valley
moonrise, the hero held in the flow rather than in either screen so moving between them
changes the text and not the background. Guest is a real state and the only path that
fully works — it needs no server and everything it stores is already local. Sign in with
Apple stays on screen and reports why it cannot run: the entitlement needs a paid
developer account, the same reason WeatherKit is off in `project.yml`. The app is gated on
an identity now, so a clean install sees these rather than going straight to Today.

**Chrome** (.9, .10, .12): sheet close discs struck from the same centre as the corner
they sit in, the builder footer sitting into the home indicator's clearance rather than
above it (a seventh row shows), and a larger profile monogram.


## 2.26.0 — NPS data actually arrives

Not the proxy, not the key, not the network — all three verified with curl against the
app's own backend. `ParkFacts` looked a code up by *name* and sent the park's full name as
the query. NPS matches on any word, so "Badlands National Park" asked for every unit
containing "National" or "Park" — 452 of them, alphabetically, and the ten rows requested
were Abraham Lincoln through Alibates. All sixty-two bundled parks failed this way. The
park service's own code now ships in the bundled data, matched against the live register
and verified 62/62 (Haleakalā by diacritic folding, Denali and Katmai across "& Preserve",
Sequoia and Kings Canyon both to `seki`), so resolution needs no network at all. The name
lookup stays for unbundled parks but asks properly, and the cache is cleared — a miss had
been remembered as "" so it would not repeat, which is correct behaviour applied to a
permanently wrong answer.

**An empty answer stops meaning "there are none"** (.7, .8). Three faults of one shape,
found by asking where else that bug lived. NPS returns `entranceFees: []` for a park that
charges nothing, and Congaree read "Not published" — nobody knows, about a park that is
simply free. Alerts turned a refused request into an empty array and the screen then hid
"Know before you go" entirely, so a park with a closure the app failed to fetch looked
exactly like a park with nothing to report — the one mistake `NPSService` documents as
unacceptable, made for the most safety-relevant field on the screen. And a Recreation.gov
join was parsed by splitting the whole URL on "/" and requiring digits, which works until
the link carries a query string. Fee and hours are stacked and labelled now, each saying
whether that particular value came from NPS, because the service can answer with hours and
no fee. Descriptions end on a whole sentence rather than a character count, which had cut
Congaree's hours on "Please review the par".


## 2.25.0 — A button answers a tap anywhere on it

Controls worked only where their label's glyphs were. Every control in the app is a
rounded surface much larger than its text, and the rest of it was dead — so a tap landed
on nothing and the second or third attempt happened to hit a letter. The fault is in
`LiquidGlass`: the pre-iOS-26 branches call `.background(…, in: shape)`, which makes the
shape hit-testable as a side effect, while the iOS 26 branch calls `.glassEffect(…, in:
shape)`, which does not. Interactive glass gets an explicit `contentShape`; surfaces that
are not controls get none, so a header cannot swallow taps meant for what sits on it.
Same shape in `DividedRow`, in `SelectedControl`'s inactive branch, and in the sheet,
builder and tab bindings, which read state only inside closures that run after the body
and so registered no Observation dependency — which is why a sheet opened on the second
tap. Search fields got it worst (a `TextField` is tappable only where its text is, and an
empty one is almost entirely empty) and now take a tap anywhere on the pill, simultaneous
so a tap on the text still places the caret where it was aimed. Back stopped being eaten
by `TabView` writing its own selection back at moments that are not user taps.

**The near-you brief reads against the park it is about** (.4): one line per park, in that
park's row under its measured figures, rather than a bullet list five rows above the
shortlist it corresponded to. **A build badge on Profile** (.2), `vX.Y.Z.a` read from the
bundle so it cannot drift from what shipped, selectable so it can be copied into a report.


## 2.24.0 — Set out from any city in the country

`curated.json` shipped six origin cities and the builder offered no other way to answer
"from where", so a trip from Dallas could not be expressed at all. A search field above
the list now brings down US cities from `MKLocalSearchCompleter` — completions keep pace
with typing and do not queue behind the park search on Nominatim's one-per-1.1-second
door — and the shipped six stay as shortcuts. Origins become `TripOrigin` (name, lat, lon)
throughout; the new `SavedTrip` fields are optional, so trips saved before this still
decode.


## 2.23.0 — A trip describes the trip that was planned

Three faults made a composed trip report something other than what was asked for. **The
origin** was read only in an else-if after Core Location, so a trip planned from Seattle
was routed from wherever the phone happened to be — and the note reported that city as
though it had been chosen. **The titles** resolved picks through `library.park`, which
knows only the eight codes in `curated.json`, while the picker offers the bundled sixty-two
and three thousand state parks — so every pick outside the eight resolved to nothing and
the trip was called " to ". **The weather** asked for `Date()` unconditionally, so a trip
next month read today's forecast; the date is threaded through the route now, falling back
to the ten-year climatology that had been written for dates past the forecast horizon and
called from nowhere.


## 2.22.0 — The app stops loading forever

Every location-dependent surface could spin indefinitely, and on a first launch all of
them did. `deviceFix()` raced Core Location against a sleeping task inside a
`withTaskGroup`, but a group waits for every child and `cancelAll()` never resumes a
`CheckedContinuation` — so the 8-second budget elapsed and the group then blocked on Core
Location anyway. `requestLocation()` was also issued while authorization was still
`.notDetermined`, which iOS discards, with no
`locationManagerDidChangeAuthorization` to reissue it. Rewritten around a single
continuation with a deadline task that resumes it, waiters held in an array so concurrent
callers share one fix, four `LocationService` instances collapsed into one. The network
layer is bounded too: `timeoutIntervalForResource` was unset, which is a seven-day default.


## 2.3.0 — Reachable

**The type scales now.** Every size in the app was fixed, which meant a reader who had
turned text up got the same 11pt labels as everyone else — the one genuinely un-Apple
thing left in it. All eight tokens run through `UIFontMetrics`, each mapped to the text
style it behaves like, each capped (1.4× for display, 1.6× for body) so a stat row still
fits its column at the largest setting. The design's sizes remain the baseline.

**Long-press does what it should.** Context menus on the Discover cards (open, save,
download the pack), the trip cards (open, share, remove) and the saved rows (open,
remove) — so the small × on a card is no longer the only way to act on it.

**Feedback moves to `sensoryFeedback`**: a light impact when a day's item is ticked,
selection when a park is saved, success when a stamp lands. The system decides what that
means on the device rather than the app hard-coding a generator.


## 2.2.0 — Motion

The screens were right and the movement between them was mine. This release hands the
navigation to the system and builds the design's own keyframes on top.

**Screens push on a real NavigationStack**, one per tab, so the interactive back-swipe,
the depth and the timing are iOS's. On top of that, a card now *becomes* the screen it
opens: `matchedTransitionSource` on the Today hero, the Discover cards and the trip cards,
`navigationTransition(.zoom:)` on the destination. A park's colour field is its identity,
so growing it into the header reads as the same object rather than a new page. Below iOS
18 the push slides, exactly as `wp-push` does.

**The design's keyframes, where the platform has no opinion.** `Design/Motion.swift`
holds them: `wp-panel` as a snappy spring with an 8pt rise, applied to every segment swap
— Today's three takes, the park's five sections, the trip's three; `wp-stamp` as the
spring its `cubic-bezier(0.3, 1.4, 0.5, 1)` overshoot always was; `wp-pulse` as a ring
that swells out of an uncollected stamp and fades, marking the one thing still to do.

**Numbers roll rather than cross-fade.** `contentTransition(.numericText())` on the day
heading, the tick count, the permit countdown and the passport total — they were already
tabular, so nothing shifts as the digits change.

**Cards lift as they scroll in**, through `scrollTransition` against real scroll position
rather than on appearance, so the effect holds when you scroll back up. The near-you brief
staggers its lines, and a landing tick uses SF Symbols' own bounce.


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

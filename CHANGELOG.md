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


## 2.29.0 — A photograph to open on, and a list the traveller writes

Two screens stop being catalogues the app assembled and start being things the reader
looks at and builds. Home is a photograph of a national park rather than a bordered card
on paper; a trip's third tab is the list somebody made rather than the campgrounds the
park service happens to run.

**Home is one photograph, edge to edge.** Every national park in the country, shuffled —
sixty-three, not a hand-picked five — holding for eight seconds while the picture drifts,
then cross-fading into the next. Five seconds felt like the screen was working at you; at
eight a photograph is something you look at. The park showing is named at the bottom in
display type and tapping the name opens it. Everything the old screen carried below the
hero — the driving day, the stamps within reach — is on the paper sheet the photograph
slides under when you read on.

Sixty-three layers cross-fading would be sixty-three views SwiftUI keeps laid out, and
sixty-three display-size photographs decoded is over a gigabyte of pixels. Three are
mounted — showing, previous, next — which is exactly what a cross-fade plus a prefetch
needs, and the decoded images are evicted back down to that window and re-read from disk
on the way back. `PhotoStore` now keeps two sizes rather than one: a 126×74 rail tile and
a full-bleed photograph are not the same request, and storing one size for both meant
either a soft home screen or eight oversized decodes in a horizontal rail. The size is
part of the cache key, so the two never overwrite each other, and the display size is a
little over the longest edge any current iPhone reports so nothing is upscaled.

The indicator is a window of seven dots centred on the one showing, with the outermost
pair shrunk while there is more playlist past them. Sixty-three dots is not an indicator,
it is a hairline of noise under the wordmark.

**The status bar follows the picture.** Home puts the window into the dark scheme so the
clock and the battery survive a cave mouth behind them, and only at the root of Today — a
park pushed out of it is a paper screen again. It is set at the shell rather than inside
the `TabView`, because a preference set on a tab page held at launch and was lost the
first time a reader came back from another tab.

**Stays is now My list.** The old third tab was a read-only catalogue of the park
service's campgrounds — a strictly worse view of a screen one tap away on the park itself.
What replaced it is built by pressing *add* on rows that were already there: a charger
before the climb, the last shop before the gate, the lodge actually booked, the permit
page, a note about the shuttle selling out by seven. Links unfurl through Apple's own
`LPMetadataProvider`, fetched once and kept on disk, so a Recreation.gov reservation reads
as the page rather than as an address, and reads offline for good.

The add control is drawn only where there is a trip behind the screen. The same charging
row appears on a park opened from home and on one opened from a trip; only the second
offers, because only the second has a list for a place to go on. A park opened from a trip
was opened *for* the day the trip reaches it, so what is added there files itself under
that day instead of landing in the undated pile and having to be moved by hand — which was
most of the work the list was meant to save. Undated is a real answer, not a gap: a
packing document for the whole week is not a Tuesday thing.

A place on the list is a waypoint by default, because somebody who added a charger meant
to stop at it; switching one off leaves it on the list and out of the route, which is the
difference between "I am not going" and "I do not need directions to it". *Drive it* and
*share* sit welded to the foot of the list rather than stacked full-width down the page,
and a drive with every stop switched off asks before opening an empty one. A trip that was
last read on the old third tab still decodes and simply opens on the new one.

**The trip shelf draws its maps once.** Every card carried a live `Map` that re-streamed
its basemap tiles on every appearance — scrolling the shelf, coming back to the tab,
relaunching — and came up blank on a road with no signal, which is exactly where somebody
is most likely to be looking at them. A route map is a picture of a drive that will not
change until the drive does, so it is rendered through `MKMapSnapshotter`, composited with
its own route line, and written to disk under the trip's id beside a fingerprint of the
stops and the plate size. Edit the trip and the fingerprint disagrees, the old picture is
deleted, and a new one takes its place. The road is deliberately not in the fingerprint:
it is fetched again on every launch and lands a moment after the card, so including it had
every trip re-rendering its map from the network twice per launch. Delete a trip and its
picture goes with it — that is the one file no fingerprint can ever invalidate.

**Weather on the route, as a sky rather than a number.** Legs and park days now carry a
symbol for what the sky is doing: nine states, not the forty-odd codes the WMO publishes,
because a reader glancing at a trip wants sun, cloud, water or ice and nine glyphs that
can be told apart at 19pt beat forty that cannot. A leg is weathered where it arrives; a
park is weathered once per day actually spent in it, because a two-day park averaged into
one glyph is a reading true of neither day. Nothing is drawn where a source said nothing —
a missing condition is "nobody told us", never "clear". Most trips are planned past
Open-Meteo's sixteen-day horizon and get ten years of the same calendar window instead,
drawn differently, because a typical August must not look like a forecast for Tuesday.

**Chargers, fuel and shops fold into one line.** Three categories at five rows apiece was
most of a park screen for something a reader mostly wants to know *exists*, sitting between
the alerts and the campgrounds, which are what the page is for. Shut, the section is one
line that still answers the question — how many, and how far the nearest is. The first
category with anything in it opens on arrival so the mechanism is demonstrated rather than
hinted at, and it waits for each category in turn rather than opening on whichever search
answered first. The chips carry a glyph rather than a word, and the word is the
accessibility label and the heading over the open list.

**A park's alerts are a list again.** The park service writes them at whatever length it
likes and a park in fire season posts five, so printed in full they were most of the
Overview — the reader scrolled past a paragraph about propane stoves to reach the entry
gates. The tag and the title triage the list; the body waits until it is asked for. The
severity colour never collapses.

**A day of a trip folds to a line.** The plan printed every day in full — the drive, the
detours, the park service's paragraph about each thing to do — so four days filled a screen
and a fortnight was fourteen of them. The *shape* of a trip, where the driving is and which
parks get two days, could not be seen at all. Folded, a fortnight fits on one screen.

Campgrounds now carry the point the park service publishes for them, so one can be a
waypoint in a drive rather than sending the reader to the park's centre, miles from the
site. `DESIGN.md` writes down the measurements the app already uses — colour, type, radii,
motion — so a new screen matches the ones beside it instead of inventing its own corner
radius.


## 2.28.0 — Fly when faster, meant literally

"Fly when faster" was a switch with nothing behind it. The builder stored the answer, the
review screen read it back, and every trip was routed by road regardless — the preference
reached no code that could act on it. `FlightCompare` is the missing half.

**It compares doors, not airports.** A 900-mile drive is fourteen hours of wheel time; the
flight that replaces it is an hour to the airport, most of two before the door closes, two in
the air, and the better part of another at the hire-car desk on the far side. Comparing gate to
gate against a whole day's drive is how an app talks somebody into a flight that saves them
nothing. The drive side of the comparison is the router's measured number, never modelled from
distance, because the answer is only as honest as that figure.

**Large hubs only.** Regional fields are excluded outright rather than ranked below the hubs.
Mammoth Yosemite and Cedar City are nearer to their parks than any hub is, and an earlier pass
named them for exactly that reason — but two flights a day at four times the fare is not the
flight anybody weighs against a drive. Nearly everyone flies to Las Vegas and drives to Zion,
to Salt Lake City and drives to Arches, and the extra hours in the hire car are counted rather
than avoided by naming an airport nobody uses. The hundred hubs are scanned directly, not
filtered out of a ranked list of every field: in a crowded corner of the country forty airports
can all be small ones, and the hub 300 miles out — the one actually flown to — never appears.

**It says no out loud.** A leg the switch declines to fly comes back with the reason, so the
screen says why rather than showing nothing and reading as broken, which is what the switch did
for its whole life until now. A travelling day that is flown is marked as one: the day is spent
in airports rather than on the road, which is a different day.

**Every number is an estimate and the copy says so.** No airline publishes schedules to an app
without a contract, so this cannot claim a flight exists on a given day. It says which airports
the leg would be flown between and what that would cost in hours, with an hour of slack on
every flight — no flight leaves at the minute somebody wants one and not every pair of hubs has
a nonstop, so the slack keeps the estimate on the conservative side of its own comparison.


## 2.27.0 — What the sources actually say

The longest run in the log, and most of it is the same argument applied in new places: the
app may show what a source published, or say it could not ask, and nothing in between.

### Builds .27 – .44

**The section rail is welded to the foot of the display** (.44). It used to ride the page and
hand itself over to a copy in the header on the way past the top, which meant the one control
the park screen is navigated by was somewhere off the top of it for most of a long section —
and in two places during the swap. Frozen, it is in one place always, and that place is the
end of the display a thumb actually reaches: a floating capsule of ink glass with the page
running past either side, the same material every button on the screen is made of. The header
loses its second copy of the rail and is 42 points shorter for it. The tab bar's items go from
62×46 to 68×52 for the same reason — the app's most-used control was the smallest target on
the screen, a couple of points over the 44pt floor and reached at the far end of a thumb's
stretch.

**The weather rail reaches sixty days either way** (.44). Forward of about a fortnight the
numbers stop being a forecast and become the same calendar week averaged over ten years, which
is the honest answer to "what is October like here" and which the source line under the tiles
names for whichever day is being read; backwards they are the archive of what the weather
actually did. The temperature scale gains a fourth band at the cold end — three could only say
how hot a day was, so a 38° morning at a trailhead and a perfect 70° afternoon were the same
green.

**Visited can be undone** (.44). It was a word in a pill that turned into a settled, untappable
state once the park was on the rail, so a mistaken tap could only be undone from the Profile
screen, if at all. It is a toggle now, and taking a park off the rail suppresses rather than
deletes: the rail has three sources and only one can be deleted from — a passport stamp is a
fact about where the phone stood and a past trip is a whole itinerary, and neither should be
quietly destroyed by "I have not been here". Also drawn at last: the park service's own
`directionsInfo`, fetched all along with nowhere to put it.

**How busy a park really is, measured** (.39). Busyness was inferred from the month — May
through September hard-coded as the busy season for every park in the catalogue, which is
Yellowstone's year and nobody else's. The park service has counted every visitor since 1979
and publishes the monthly totals, so `tools/build-visitation.mjs` pulls them and the app
ships the curve. There is no JSON API: the numbers live behind an SSRS report viewer, so it
takes three hops per park — the report page (an iframe wrapper), the iframe (which carries a
ReportSession and a ControlID), then the export handler with `Format=CSV`, which returns 6 KB
of exactly the table rather than 272 KB of nested viewer markup. Averaged over three complete
years, bundled rather than fetched, all 62 parks under both code schemes. What it corrects,
in the data: Big Bend peaks in March and empties in August, Hawai'i Volcanoes peaks in
January, Great Smoky Mountains peaks in October — all three read "busy season, arrive early"
in August before this.

**What is near a park, and what each day of a trip holds** (.43). Nearby read a written-down
list that existed for the eight parks in `curated.json` — one row for Yellowstone, nothing for
the other fifty-five; it now asks the park service for every unit it runs and joins the
state-park table already on the phone, with the closest handful driven through OSRM because
seventy miles over a mountain range and seventy miles down an interstate are not the same
afternoon. National parks are deliberately absent: a second one an hour away is a trip of its
own. Days said "day plans are written when the trip is composed online", which was true and
useless — nothing composed them. They are built from the leg geometry and the park service's
own lists, on two rules: a driving-day stop is only offered once the detour has been
*measured* against the same drive without it, and a park day's list keeps the park service's
own order, because NPS publishes no rating and ordering by anything invented would be worse
than ordering by nothing.

**Alerts get a severity** (.43). NPS publishes four categories and three tones carry them,
which is what a reader can tell apart on a row they are scrolling past: a danger and a park
closure both bear on whether the trip happens and read red, a caution reads amber, an
information notice reads green. A category the park service adds that this app has not been
taught reads amber rather than green — it used to sort and colour itself alongside
information, so a new serious category would have arrived looking like a car-park notice and
sorted below one. The tone is never the only signal; the tag carries the category's own word.

**NPS photographs, twice wrong** (.27, .31). The photo lookup sent the bundled slug
(`np-zion`) as a `parkCode`. NPS does not recognise it and fails *open* — ignoring the code
and returning the first fifty units alphabetically — so every national park in the app pulled
Abraham Lincoln Birthplace's three photographs and showed them. Then, with the right park
answering, the resolver hashed the park code to a random index, which reliably threw away the
marquee shot NPS puts first (Zion's Watchman, Grand Canyon from Mather Point) in favour of
carriage-road bike tours and fee signs. Take `images.first`.

**Real timed-entry and reservation information** (.28). The app called `/parks` and four
sub-endpoints and never `/feespasses`, which is where the park service keeps timed entry,
reservations and the free-park flag — so every screen showed a hard-coded "Entry reservations
are not listed here. Check with the park before you travel", whatever the park required.

**The trip builder stops guessing** (.35, .36, .37). The date field was a button cycling four
canned strings, which is exactly the "random date" it looked like; it is a real `DatePicker`
that disallows a past start. The date and origin bars were dark glass with default label
colour — black on near-black, invisible — and are light bars with dark text. And the 4–5 hour
window meant for the traffic estimate was gating the whole section, so fuel, charging and food
along the route vanished precisely when someone was planning the drive; the stops load
whenever the leg is opened and only traffic waits for the day.

**Every sample gets asked, and Maps gets the whole drive** (.38). Twenty-one concurrent
searches on a 600-mile leg had MapKit answering `loadingThrottled`, and those refusals were
discarded as `nil` — indistinguishable from an empty road — so a leg showed three stops at one
mile and claimed Apple Maps listed nothing along the route. A sliding window of four, backoff
retries on the refusals that are "not now" rather than "no", and a worded-search fallback for
the installs where the category request answers `GEOError -8`. Sample miles were wrong too:
the route arrives simplified, its vertices up to seventy miles apart, so samples piled onto
one point and the line ran short of the road. Interpolated along the segment, walked in
polyline miles, reported in road miles. And "Open in Maps" built a `?daddr=` URL carrying a
park *name* and no stops; ticked stops are handed over as waypoints in mile order.

**Find a state park by the city you are near** (.40). The table matched a park's own name or
its state and nothing else, so "Austin" found nothing though there are a dozen state parks
within an hour of it. `PlaceAnchor` geocodes the words once and ranks the on-device rows
around the point that comes back; an empty field ranks from the phone. A *state* is
deliberately not anchored — "Texas" geocodes to scrub near Brady, and the state filter already
answers that query. The table is deduplicated on the way in: the shipped file lists "Ray
Roberts Lake" and "Ray Roberts Lake State Park" as two parks in one county and "Lake
Dardanelle State Park" three times, which read as a mistake and gave two rows one `ForEach` id.

**State parks stop being the lesser catalogue** (.33, .34). Plain text rows beside the national
parks' photo cards; they render as the same `DiscoverCard` now, filled by the Commons
photograph where one is named and by a pinned monochrome map where none is.

**Near-you recommends what is actually near** (.32). The card ranked the eight shipped parks
with no distance limit, so it showed the same eight from anywhere in the country. Every
national park is measured and those within 120 miles kept, falling back to the nearest only
when none is in reach.

**The weather panel reads as one instrument** (.41). Six glass tiles, each drawing its number
by the nature of the reading rather than the metric — a level fills bottom-up, an index fills
along its own scale and takes that scale's colour at the cut, a speed swings a dial, the day's
light draws a band. Two figures fetched all along and never shown are drawn: the day's highest
hourly chance of rain, and the gust on the same track as the sustained wind. A tile with no
number shows a dash and stays empty, because a tile drawn at zero is a reading.

**A tab bar that ends where its items do** (.42). The iOS 26 system bar owns its geometry — it
spans the screen, and the legacy `UITabBar.appearance()` layout properties are read by the old
bar and ignored by the new one, which was measured rather than assumed. `CompactTabBar` is
drawn by hand as a sibling of the `TabView`, which keeps the selection, the per-tab stacks and
the zoom transitions; the selection pill morph and the scroll-down minimise come back by hand.
The tab glyphs stop being flattened into template images, because a system tab item accepts an
`Image` and nothing else.

**An AI Overview tab** (.30), written on the phone by Apple's on-device model under the same
rule as the nearby briefing: the model gets no facts of its own and the figures are printed by
the app beside the prose, never by the model. The page colour default moves from the olive
`#D1CFA5` to `#EFF2F0` (.29), the tint control still overriding it.

### Builds .9 – .26

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


## 2.21.0 — A trip from any park

The builder button was gated behind a designation check, so a national park screen offered no
way into trip planning even though it is the likeliest first stop. "Plan a trip here" shows on
every park screen.


## 2.20.0 — Back, and one navigation path per tab

All five `NavigationStack`s were bound to the same `$app.stack`. Five stacks driven by one
array: a park pushed from Discover was in the history of Today, Trips, Saved and Profile as
well, and popping it popped all of them. Each tab owns its path now and keeps it across
switches.


## 2.19.0 — Plan a trip from the park you are looking at

A state park's screen offered to save it and to download a pack it has no day plans, stamps or
curated content to fill — and no way to do the one thing somebody looking at one actually
wants. A third action opens the builder with that park picked, at step two, because the park
was the answer to step one.

**The shipped state parks open** (2.19.1). Three thousand state-park rows ship with the app
and tapping one produced a toast — "a name and a location is all any nationwide source
publishes" — and went nowhere. True of the row and untrue of the park: the row carries
coordinates, and coordinates are all the live sources need.


## 2.18.0 — Navigation controls stop reading as borrowed chrome

Back was 15pt with a 16pt UI title and the builder's Cancel 14.5, all sitting under a masthead
set in 44pt serif — system chrome from another app pasted onto the top of this one. Back and
Cancel are 19pt with a matching chevron and a 44-point target; the pushed title is the display
serif at 24.


## 2.17.0 — Campgrounds, availability and things to do, all live

NPS answers for more than the fee. `ParkFacts` fetches the park's campgrounds, its things to
do and its parking lots alongside the record and its alerts, concurrently, each absent rather
than fatal when it fails. Stay lists the park service's own campgrounds with site counts,
nightly fees and reservation notes; Plans lists what the service publishes beneath the curated
day plans.

**A trip can be built from any park** (2.17.1). `TripBuilder.results` filtered
`library.orderedParks` and nothing else, so the one screen where a park has to be chosen could
only offer the curated eight — a park found on Discover could be opened and saved and then not
planned around.


## 2.16.0 — NPS answers now

The service was never broken. The worker allowlists the website's origin, and the app
introduced itself as `app://waypost-ios`, which it answers 403 to. Every NPS call the app had
ever made had failed, and the empty panels were read as the API being down. The header was
never authentication — the key lives on the worker — so the app sends the site's own origin
and `X-Waypost-Client` still says which client is calling.


## 2.15.0 — Screen titles match the masthead

Trips, Discover, Saved, Profile and Find a park are Cormorant Garamond Bold at 44, the same as
ParkHop on the home screen. Doing it exposed the bug `HP_changes` lists first under Design:
`scaled()` rebuilt every font from a hard-coded `CormorantGaramond-SemiBold`, so `displayBold`
asked for the Bold cut, passed its own check that the Bold cut exists, and then drew SemiBold —
including the masthead the weight was cut for. Carries the P0 trust fixes from `HP_changes`.


## 2.14.0 — The page is #D1CFA5

One token: the page colour goes from near-white to the sage the design asked for. It needed one
split to stay that way — `WP.bg` was doing two jobs, the page and the pale type that sits on
ink, which were the same colour by coincidence rather than by intent.


## 2.13.0 — The home screen answers with your location

**The masthead is Cormorant Garamond at 700.** The weight did not exist as a static face — the
repository ships SemiBold only — so it was cut from Google's variable original with fontTools
and renamed.

**Trips shows where you have actually been** (2.13.1): the empty screen promised that ParkHop
"leaves blank whatever it cannot measure", which is a claim about the app rather than help with
the task, and "Behind you" listed two trips that never happened. **The find-a-park sheet
answers before it is asked** (2.13.2) — it opens on six national parks rather than a blank page
under a paragraph of explanation. **The close button matches the one that opened it** (2.13.3):
a 52-point light-glass `+` and a 34-point ink `×` were two ends of one gesture agreeing about
nothing; both are a single `GlassDisc`. **Stop telling people where the data is kept** (2.13.4)
— where a record came from is worth saying (NPS, Apple Maps, OpenStreetMap); which disc it is
sitting on is not the reader's problem.


## 2.12.0 — Every national park on the phone

The instinct was right and the number was ten times too big. Measured rather than guessed: a
Wikipedia original averages a megabyte — Delicate Arch is 1.8 MB — for a card the phone draws
393 points wide. Stored at a size the screen can actually show, all sixty-two national parks
come to twenty-five megabytes, not two hundred. `national-parks.json` is 9.6 KB and ships with
every park in it.

**Every screen, named, for feedback** (2.12.1, 2.12.2) — `docs/SCREENS.md` and all thirty-six
captures, including the halves below the fold.


## 2.11.0 — Parks on screen in about a second

The search ran its sources in order, so the wait was all of them added together: three
Nominatim calls one after another, then a request to a proxy that answers 403, and only then
the slow sweep. They run together now.


## 2.10.0 — A recommendation that actually changes

The home screen led with day five of the seed trip — the same park, the same photograph, every
launch, forever, however far you had travelled and whatever the weather was doing there. Four
things decide it now, and the card says which of them applied.

**Park WeatherKit, keep the code** (2.10.1). The entitlement requires a paid Apple Developer
Program membership; signed with a free personal team, Xcode cannot generate a provisioning
profile carrying it and the build fails before any of the code runs. Deleting a working
implementation for a billing reason is the wrong trade, so it is compiled out rather than
removed.


## 2.9.0 — What is actually around the park, from Apple Maps

The camper's questions — where do I charge, where do I fill up, where is the last shop before
the gate, where can I sleep — were answered from lists that existed for four of the eight
shipped parks and for nowhere else in the country. `PlacesService` asks Apple Maps instead.


## 2.8.0 — Suggestions while you type

Two letters in there was nothing on screen and nothing to pick from, and the field ran a search
that could take the better part of a minute. Typing "te" offers Tennessee, Texas and Grand
Teton before any request has been made — states match locally against the fifty names and their
postal codes, so they cost nothing.

**Say what kind of park it is** (2.8.1). Every result read as a national park. A search for
Utah returns five of those, ten national monuments, thirty-two state parks, three national
recreation areas and over a hundred wilderness areas, and the cards said none of it. The
designation is a field on the record rather than something inferred at the point of drawing.


## 2.7.0 — Results as they arrive

A state-wide Overpass query takes thirty to ninety seconds — Texas took ninety — and the whole
search waited on it before showing anything, so a search that was working looked like one that
had failed. The sources answer independently and publish as they land: Nominatim first at about
a second, NPS next, Overpass last. Apple Weather, and a sheet for routed legs.


## 2.6.0 — Live park search, and the leg from where you actually are

Two things were missing and they were the same thing: the screens read the eight-park library
that ships with the app, so every search answered with the same handful and no trip knew how
far away it started. `ParkDirectory` answers the four ways a person actually looks for a park —
by name, by state, by city, and near me.

**Search actually answers when you type** (2.6.1). Five faults, of which the middle one did
most of the damage: the search was started by an `onChange` on the Discover screen, so it
depended on which view was mounted — and the state-park side of the toggle never started one at
all. Typing searches from the property itself now, where nothing can miss it.


## 2.5.0 — Every button and tab on ink glass

The controls were a mix — light glass pills, hairline outlines, accent-tinted capsules, one
flat ink plate — and none read as the same kind of object. One thing now: ink glass carrying
white type, applied through `glassControl()` so a button and a selected tab agree.


## 2.4.0 — Real photographs on the park tiles

The design binds a photograph to every park card and the app drew only the colour field
underneath it. `ParkPhotos` resolves one per park and remembers the URL, asking NPS first
because those are the park service's own pictures and the ones the design was drawn against.

**The photograph runs to the top of the display** (2.4.1). A picture in a 196pt band below a
header bar read as a page about the park rather than an arrival at it. It bleeds to the very
top — under the status bar, around the island — and dissolves into the page, so the name below
sits on the same sheet.


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

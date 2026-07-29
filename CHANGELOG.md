# Waypost for iOS — change log

Running record of every change to the iOS app, newest first.

Versions track the web repo (`../waypoint`): the same number means the two apps are built
from the same understanding of the data, not that they have the same features. Semver
lives in `VERSION`, is stamped into `project.yml` by `./sync-version.sh`, and is read back
out of the bundle for the nav badge.

Guiding rule, inherited from the web app: **never show an invented value.** If a source
cannot be reached or publishes nothing, the interface says so rather than substituting a
plausible-looking number.


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

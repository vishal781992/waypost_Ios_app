# national-parks.json

Sixty-two rows, 9.6 KB, bundled: code, name, full name, state, coordinates, designation.

Built once, by hand, from two sources:

* **Wikidata** — the park list and coordinates
  (`SELECT ?item ?itemLabel ?coord WHERE { ?item wdt:P31 wd:Q34918903 }`).
  Seven parks carry no coordinate there — the Alaskan preserves and New River Gorge —
  and those were filled from the park service's own listings.
* **The US Census geocoder** — the state for each coordinate
  (`geocoding.geo.census.gov/geocoder/geographies/coordinates`, no key, no rate limit).
  Channel Islands is offshore, so the census layer has no answer; it is CA.

Park-and-preserve pairs (Denali, Katmai, Wrangell–St. Elias, Gates of the Arctic,
Glacier Bay) appear twice in Wikidata. One row each, and the preserve designation wins
because it is the current one. General Grant was folded into Kings Canyon in 1940 and is
not in the list.

Rebuild only when the park service adds a park, which happens about once every two years.

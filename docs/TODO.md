# Open work

Written 8 August 2026, at the end of the session that shipped v2.27.0.39.

Everything below is either not started or deliberately left; nothing here is broken in the
app as it stands.

---

## 1. Cell coverage along a drive

The goal: tell a traveller where the signal dies on the road between parks, so the offline
packs mean something specific rather than "you might need this".

### 1a. FCC account — needs you, not the agent

Account creation and credentials are yours to do.

1. [broadbandmap.fcc.gov](https://broadbandmap.fcc.gov) → **Sign In** → **Create an account**
   → hands off to the FCC User Registration System
   ([apps2.fcc.gov/fccUserReg](https://apps2.fcc.gov/fccUserReg/pages/createAccount.htm)).
   The username **is** an email address.
2. Sign in at [bdc.fcc.gov](https://bdc.fcc.gov/). Landing on a Consumer Challenges page is
   expected — it is the same system the filers use.
3. Click your username, top right → **Manage API Access** → **Generate**. One-time
   disclaimer on the first token.
4. Requests need **username + token together**. The token can be regenerated or revoked at
   any time, so a mistake here is cheap.

Store it out of git — `~/.waypost-fcc.env`, `chmod 600`, holding `FCC_API_USER` and
`FCC_API_TOKEN`. Not in the repo, and not pasted into a chat window.

Free, and free commercially: it is a US government work, so unlike the alternatives there is
no licence restriction on shipping it in a paid app. Rate limit is **10 requests/second**
burst per key, with `X-RateLimit-Limit` / `X-RateLimit-Remaining` headers.

**Watch the domain.** `broadbandmap.fcc.gov` is the official free one. `broadbandmap.com` is
an unaffiliated third party reselling the same data with paid tiers.

Rejected alternatives, and why:

- **Ookla Open Data** — real measured speeds rather than modelling, free to download, no key.
  But **CC BY-NC-SA 4.0**: non-commercial only, and ShareAlike infects derivatives. Unusable
  the moment ParkHop is paid or ad-supported.
- **OpenCelliD** — CC BY-SA, and the free API tier is reportedly ~50 calls/day. The bulk
  download is the only realistic path, and it gives tower positions, not coverage.
- **Mozilla Location Service** — retired in 2024. Ignore anything that suggests it.

### 1b. Decide the shape before fetching anything

Per carrier (Verizon / AT&T / T-Mobile separately) or a single "is there any 4G/5G here"
flag? Per carrier is far more useful — whether there is signal depends entirely on whose SIM
is in the phone — but it is 3–4× the data and needs a carrier preference somewhere in the
app, plus a sensible default when unset.

Also decide whether to keep the 3G / 4G LTE / 5G-NR tiers or collapse them.

This decides the file shape, so settle it first.

### 1c. Prove the data before trusting it

FCC mobile coverage is **carrier self-reported propagation modelling** and is known to be
optimistic. Check it against places whose real coverage is not in doubt before building
anything on it. The Denver → Carlsbad leg samples are already verified good coordinates:

| mile | lat | lon |
| ---: | --- | --- |
| 80 | 38.6654 | -104.7398 |
| 240 | 36.5987 | -104.5194 |
| 400 | 34.6753 | -105.1017 |
| 560 | 32.6437 | -104.4173 |

Mile 80 is near Pueblo, CO and should show strong coverage on every carrier; the remote New
Mexico stretches should not. Add a park known to have no service as a control.

If it turns out too optimistic to be useful, say so and stop. Telling somebody they will have
signal on a remote road when they will not is worse than saying nothing.

### 1d. Prebake

~63 national + ~3,003 state parks ≈ 3,100 point lookups, about five minutes under the rate
limit. Emit `Waypost/Resources/coverage.json`, keyed the way `visitation.json` is — **both**
the app's park code and the NPS code, because the two catalogues disagree (see the note at
the bottom of this file).

Write it as a checked-in script under `tools/`, not a one-off shell invocation: carriers
update their filings, so this needs regenerating.

Load it off the main thread, like `state-parks.json` — lazily, warmed by the detached task in
`AppState.init`.

### 1e. Show it

`LegStops.samples(along:everyMiles:roadMiles:)` already walks the leg polyline and returns
interpolated points labelled in true road miles. The same points can carry a coverage lookup,
giving "no signal, mile 240 to 320" on the driving-day sheet — next to the offline-pack
messaging, which is where that warning belongs.

**Unresolved, and it blocks the UI:** park coverage is not route coverage. The prebake covers
parks; the road between them is a different question, and arbitrary user routes cannot be
prebaked. Either bundle a coarse grid along the major corridors or accept a live call.
Resolve this before building the view.

Be honest about provenance in the `SourceLine`, as that sheet already is for OSRM and Apple
Maps: this is modelling, not measured signal.

---

## 2. Loose ends from the Explore merge

Discover stopped being a tab in v2.27.0.39. It is reached from the Today header now, and
`QuickSearchSheet` — which asked the same question in a smaller box — was deleted.

Two things still say otherwise:

- **The screen is still titled "Discover".** You tap *Explore* and land on *Discover*. Rename
  the header, and probably `DiscoverScreen.swift` with it, or rename the button back. Either
  is fine; disagreeing with itself is not.
- **`SavedScreen` empty state is now wrong:** *"Bookmark a park from Discover and it waits
  here for the next trip."* There is no Discover to bookmark from. One line.

---

## Two traps worth remembering

**The app has two park-code schemes.** The bundled catalogue calls it `np-grand-canyon`; the
eight curated parks call the same park `grca`. Keying bundled data on one of them silently
drops the other — this is exactly why the visitation chart was blank on the eight best-known
parks on the first attempt. `visitation.json` is written under both keys, and
`Visitation.profile(for:)` tries both. Anything bundled per-park should do the same.

**Sequoia and Kings Canyon share the NPS code `seki`,** so it cannot be a unique key. The NPS
stats system also rejects `seki` outright and wants `SEQU` / `KICA` separately — see
`STATS_CODE` in `tools/build-visitation.mjs`.

# changed.v.1

Screens after the changes you asked for. Same filenames as `docs/screens/`, so
`docs/screens/A1.1.png` and `docs/changed.v.1/A1.1.png` sit side by side.

| | Before | After |
|---|---|---|
| **A1.1** Today | [`screens/A1.1.png`](../screens/A1.1.png) | [`A1.1.png`](A1.1.png) |
| **A1.1.1** the `+` | — | [`A1.1.1.png`](A1.1.1.png) — new |
| **A1.1.2** the `+`, searched | — | [`A1.1.2.png`](A1.1.2.png) — new |
| **B1.1** Trips | [`screens/B1.1.png`](../screens/B1.1.png) | [`B1.1.png`](B1.1.png) |
| **B1.1.1** Trips, empty | [`screens/B1.1.1.png`](../screens/B1.1.1.png) | [`B1.1.1.png`](B1.1.1.png) |
| **B1.1.1.1** empty, nothing stamped | — | [`B1.1.1.1.png`](B1.1.1.1.png) — new |
| **B1.1.2** the `+` from Trips | — | [`B1.1.2.png`](B1.1.2.png) — new |

---

## What changed

### 1. The masthead is Cormorant Garamond, weight 700

**Before** — SF Pro Bold at 42 pt, tracking −0.8.
**After** — Cormorant Garamond Bold at 44 pt, tracking −0.4.

The weight did not exist as a static face; the repository shipped SemiBold only. This one
was cut from Google's variable original at `wght 700` with fontTools, renamed so its
PostScript name is `CormorantGaramond-Bold`, and added to `UIAppFonts`. It is used for
the app's own name and nothing else — a display serif this heavy stops being a heading
and becomes a logotype.

### 2. "Near Denver" — the user's actual location

**Before** — "Near Moab, UT within 355 miles". Moab is the gateway town of whichever park
happened to be in the hero, so the line described the park, not the reader.

**After** — "Near Denver within 255 miles", from the device fix. When the fix has no place
name — an IP lookup often answers with a township — it is reverse-geocoded to the nearest
town Apple Maps knows. With no fix at all it falls back to the featured park's gateway and
is still true.

The tiles under it changed with it: they are measured from you rather than from the park,
and they are drawn from all sixty-two national parks rather than the curated eight — which
is why Denver now shows Great Sand Dunes and Black Canyon of the Gunnison instead of Zion
and Grand Canyon.

### 3. The `+` searches by state, city or park

**Before** — the `+` started the trip builder. One button, one thing, and not the thing
somebody has just opened the app to do.

**After** — it opens **Find a park**: one field taking a state, a city or a park name,
with the same suggestions and the same live directory the Discover screen uses. Each row
carries the park's photograph, its state and its designation, and opens the park. Starting
a trip is still there, at the bottom, as one tap rather than the only tap.

**Reworked once more** after the first pass looked cramped and empty. The head starts
below the drag indicator rather than under it, the headline is Cormorant at 38 rather than
28, with a kicker over it and air around it, and the field is taller. More to the point,
an empty field is no longer an empty page: the sheet opens on the six national parks
nearest you, measured from the same fix the home screen uses, off the list on the phone —
so it answers before it is asked. See **A1.1.1**.

The `×` that closes it is the same control as the `+` that opened it — 52 points of light
glass with the lit crown, not the small ink disc it started as. Both are one `GlassDisc`
now, because two controls at opposite ends of the same gesture should not be able to drift
apart.

### 4. No more opening on Zion or Arches

**Before** — the hero showed whichever park the seed trip was in — Arches on day five —
and then swapped to the real recommendation a few seconds later. It read as the app
changing its mind in front of you.

**After** — there is no fallback park. Until the recommendation is worked out the hero is
a card of the same size and shape saying *Finding one — reading where you are and what the
weather is doing there*. Nothing moves when the answer lands. On a warm launch the answer
arrives fast enough that the waiting card is barely seen; on a cold one it is honest about
what it is doing.

### 5. The hero no longer repeats itself in the rail

Not asked for — found while checking the above. The same park carries different codes in
the curated library and the on-device list (`romo` and `np-rocky-mountain`), so Rocky
Mountain appeared as the hero and again as the first tile beneath it. Compared by name now.

---

## Two smaller things the check turned up

**Live results reuse the on-device park's code.** A park found through Apple Maps that is
already in the bundled list now takes that list's code, so it resolves to the photograph
already cached against it instead of being looked up again as a stranger.

**Search thumbnails are not blurred.** Seven points of blur reads as texture behind a name
on a 200-point tile and as a smear of colour on a 44-point one. At that size the
photograph has to be the photograph.

---

## How to reproduce

```
xcrun simctl launch --terminate-running-process <device> us.parkhop.waypost -wpTab today
xcrun simctl launch --terminate-running-process <device> us.parkhop.waypost -wpFind 1
xcrun simctl launch --terminate-running-process <device> us.parkhop.waypost -wpFind colorado
```

Simulator located at 39.7392, −104.9903 — Denver.


---

# B1.1.1 — Trips, empty

### 1. The claim came off

**Before** — "…works out the order, the mileage and which permit windows you have to be
awake for — and leaves blank whatever it cannot measure."
**After** — the sentence stops at "awake for".

### 2. "Behind you" is what you have actually stamped

**Before** — two hard-coded rows: *North Cascades & Olympic, October 2025, 2 parks · 8
days · 1,240 mi* and *Big Bend at New Year*. Neither trip ever happened. They were in the
design as filler and they were still in the app, on a screen whose whole message was that
you have not been anywhere yet.

**After** — the section lists the parks carrying a cancellation stamp, each with its
photograph, its state and its designation, opening the park when tapped. With no stamps
the heading is not drawn at all — see **B1.1.1.1**, where the screen ends after the
disclaimer rather than inventing a history.

### 3. The `+` searches

Same sheet as the home screen's — a state, a city or a park name — with "Plan a trip
instead" at the bottom. **B1.1.2**.

The two invented trips are gone from the code, not just from the view.

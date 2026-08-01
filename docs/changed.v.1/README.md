# changed.v.1 — A1.1

The home screen after the five changes you asked for. Same filenames as `docs/screens/`,
so `docs/screens/A1.1.png` and `docs/changed.v.1/A1.1.png` sit side by side.

| | Before | After |
|---|---|---|
| Today | [`screens/A1.1.png`](../screens/A1.1.png) | [`A1.1.png`](A1.1.png) |
| The `+` | — | [`A1.1.1.png`](A1.1.1.png) — new |
| The `+`, searched | — | [`A1.1.2.png`](A1.1.2.png) — new |

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

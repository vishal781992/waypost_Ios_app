# ParkHop — the app's own measurements

Everything here is already in the code. This file exists so it can be *found* without
reading five files first, and so a new screen matches the ones beside it instead of
inventing its own corner radius. Where a value lives in `WP`, use `WP` — not the literal.

Source of truth: [`Waypost/Design/Tokens.swift`](Waypost/Design/Tokens.swift),
[`Waypost/Design/Glass.swift`](Waypost/Design/Glass.swift),
[`Waypost/Design/Motion.swift`](Waypost/Design/Motion.swift).

---

## Colour

The palette is the Classical design system's, transcribed. **The app commits to light
mode** — the one exception is the home carousel, which needs the dark scheme for the status
bar over its photograph and sets it from `RootShell`, per tab.

| Token | Value | What it is |
|---|---|---|
| `WP.bg` | `#D1CFA5` via `PageTint` | The page. Read through `PageTint` so it can be tried live. |
| `WP.onInk` | `#F3F2F2` | What sits *on* ink — a card, a plate, a field. Not the same as `bg`. |
| `WP.surface` | `#EAE9E9` | A step down from `onInk`. |
| `WP.text` | `#201F1D` | Body ink. |
| `WP.ink` | `#2A2829` | The ink plate itself. |
| `WP.accent` | `#B68235` | The accent. |
| `WP.accent700` | `#7D5411` | Section titles, chevrons, back controls, meta figures. |
| `WP.accent800` | `#5A3B0A` | Text on an accent-tinted fill. |
| `WP.mark` | `#FF9932` | **The brand orange.** Round controls, the weather glyphs on a route. Deliberately outside the accent ramp — it is the mark's colour, and everything wearing it is something you press. |
| `WP.markDeep` | `#D9822B` | The mark, one step down, where two oranges must be told apart. |
| `WP.lime` | `#DBE64C` | Every filled control. **Never carries white type** — 12.1:1 against `text`, 1.4:1 against white. |
| `WP.book` | = `lime` | Booking and list pills: Recreation.gov, nps.gov, *Add*, *Drive it*. |
| `WP.tabSelection` | = `lime` | The selected tab's capsule. |
| `WP.divider` | `text @ 16%` | Every hairline. |
| `WP.danger` / `caution` / `notice` | OKLCH | Alert severity. Never the only signal — the category's word sits beside it. |

Neutrals run `WP.neutral100` (`#F8F4F4`) → `neutral900` (`#2D2B2B`).
Accents run `WP.accent100` (`#FFF3E4`) → `accent900` (`#3A270D`).

Colours are written in the design's own OKLCH where the design writes OKLCH —
`Color(oklch:_:_:)` converts at runtime so the phone shows the drawn colour, not a
hand-eyed hex. `Color(css:)` parses what the curated data carries verbatim.

**Never hardcode a hex that a token already names.** The one legitimate literal is a colour
that exists only on one screen — the carousel's scrims, say — and it should say so in a
comment.

---

## Type

San Francisco throughout, **except** two roles that take Cormorant Garamond: a park's name
standing over its own colour field, and a screen's title. The Classical system pairs
Cormorant with Lora; on a phone Lora reads unevenly, so the design's *sizes* are kept and
scaled for SF's larger x-height.

| Call | Face | Use |
|---|---|---|
| `WP.display(_:)` | Cormorant SemiBold | Screen titles, park names, the carousel's 52pt name. |
| `WP.displayBold(_:)` | Cormorant Bold | The wordmark alone. A display serif this heavy is a logotype, not a heading. |
| `WP.heading(_:)` | SF, ×0.86 | Headings transcribed from Cormorant sizes. |
| `WP.headingUI(_:)` | SF semibold, ×0.86 | Small working titles. |
| `WP.body(_:semibold:)` | SF | Everything else. |
| `WP.bodyItalic(_:)` | SF italic | Source lines, asides, "within 250 miles". |
| `WP.rowTitle(_:)` | SF semibold | The name at the head of a row. Default 17. |
| `WP.statValue(_:)` | SF semibold | A figure with a label. Pair with `.tnum()`. |
| `WP.mono(_:)` | SF Mono | Airport codes and fixed-width runs. |

**Every size scales with Dynamic Type** through `UIFontMetrics`, capped per style (1.4–1.6).
Do not write `.font(.system(size:))` for anything a reader reads — it will not scale. Bare
`.system` is fine for a glyph inside a control.

Numbers that sit in a column get `.tnum()`. Uppercase kickers get `.kickerStyle()` or
`.tracking(1.3–1.4)` at 9.5–11pt.

---

## Metrics

| Token | Value | Rule |
|---|---|---|
| `WP.gutter` | **20** | The page gutter on every screen. Horizontal insets are this unless there is a reason. |
| `WP.sheetCorner` | **62** | A sheet's corner — the phone's own display corner, so the two curves match. |
| `WP.headerTop` | 14 | Status-bar clearance a header adds. |
| `WP.tabBarHeight` | 62 | The floating bar: a 52pt item plus 5pt either side. |
| `WP.tabBarClearance` | 28 | Trailing margin on a pushed screen. |
| `WP.rootScrollBottom` | 100 | What a root screen's scroll must clear. |
| `WP.sheetCloseInset(for:)` | — | Where a round close control sits in a sheet corner. |

**Corner radii in use** — pick from these rather than inventing one:

- **62** — a presented sheet (`WP.sheetCorner`), always.
- **28** — a full-bleed hero card.
- **22** — a large card.
- **16** — the common card/plate radius; also a text field on a sheet.
- **12–14** — a small plate, a route map, a thumbnail.
- **10–11** — an inline card: a link preview, a note.
- **999 / `Capsule`** — every pill, chip and round-ended control.

Always `style: .continuous` on a `RoundedRectangle`. The one exception is
`RoundedRectangle.pill(height:)`, which is circular on purpose — at radius = height/2 a
squircle is visibly not a capsule.

**Touch targets are 44pt.** Ink can be smaller; the target grows around it via
`.frame(minHeight: 44)` + `.contentShape(...)`. Where 44 is geometrically impossible — the
carousel dots — say so in a comment and make the primary gesture the large one.

---

## Sheets

Every presented sheet takes the same four modifiers. Missing them is what makes a sheet
look like it came from another app:

```swift
.presentationDetents([...])
.presentationDragIndicator(.visible)
.presentationBackground(.clear)      // the sheet's own paper shows, not the system's
.presentationCornerRadius(WP.sheetCorner)
```

Content: `.padding(.horizontal, WP.gutter)`, and the sheet paints `WP.bg` itself.
Sheets are presented by `RootShell`, not by the screen that asked — so they do not inherit
that screen's environment. Anything they need is carried across explicitly
(`app.sheetTrip`, `\.planningTrip`).

---

## Glass

`liquidGlass(_:radius:)` with a `GlassStyle`: `.header`, `.tabBar`, `.pill`, `.onPhoto`,
`.sheet`, `.control`, `.tile`. Each carries its own tint, border, inner light and material.
Do not hand-roll a blurred fill — use the style, and add one if none fits.

`GlassDisc` is the round control: the mark's orange laid solid (not tinted through glass,
because a brand colour that changes with the wallpaper is not a brand colour), a specular
crown, a 0.5pt outline.

---

## Depth

`pressedDepth(_:radius:strength:)` with a `Depth`: `.raised` or `.recessed`. The light
source is above and never moves — what changes is the surface, so a raised control is lit
along its top edge and shaded along its bottom, and a recessed one is exactly the other way
round.

**Which way a control goes is not a style choice.** Press it, it is raised. Type into it or
fill it, it is recessed. Everything used to sit at the same height, so a search field and
the button beside it wore the same material and only the label said which was which.

| Control | Depth |
|---|---|
| `limeControl`, `glassControl`, `markControl` | `.raised` + `lift()` |
| A selected segment or chip | `.raised`, shorter shadow — it lifts out of its trough, not off the page |
| `searchFieldSurface`, a `SegmentedTrough` trough, `WPSwitch` track, `ProgressTrack` | `.recessed`, no shadow |

`lift()` is the shadow a raised control casts: **two** shadows, a soft 8pt ambient one and
a tight 1.5pt contact one. A single 8pt shadow reads as a glow around the control; it is
the near shadow that says the control has an edge and the page is right behind it.

`strength` scales the whole gradient. Dark glass takes about `0.5` — at full strength its
lit edge reads as a rim of chrome around every button.

The gradient is deliberately clear from about 40% to 78% of the height, where a centred
label sits, so the tint never falls across type. That is what lets it be an overlay on the
glass controls, where the material is applied to the content itself and there is no
background layer to slip underneath. On a solid fill, put it in the `background` anyway.

**The home carousel is exempt.** It sits over a full-bleed photograph and is the app's one
dark-scheme surface; a pressed control over a photograph reads as a sticker.

---

## Motion

| Token | Curve | Use |
|---|---|---|
| `Motion.panel` | `.snappy(0.28, extraBounce: 0.05)` | A section swapping in; a disclosure opening. |
| `Motion.navigation` | `.spring(0.38, damping: 0.88)` | Screens and sheets. |
| `Motion.counter` | `.snappy(0.32)` | A value ticking over. Pair with `.contentTransition(.numericText())`. |
| `Motion.stamp` | `.spring(0.42, damping: 0.52)` | A stamp landing. |
| `Motion.toast` | `.snappy(0.24)` | The toast. |

The app's own curve, where a duration is written by hand:
`.timingCurve(0.32, 0.72, 0, 1, duration:)`. The tab pill, the carousel dots and the push
transition all move on it.

`zoomSource(_:in:clip:)` / `zoomDestination(_:in:)` are the shared-element transition. There
is one. Do not write a second.

---

## Haptics

`Haptics.tap()` and `Haptics.success()` are the stock generators, and they are what almost
everything wants: a confirmation does not need a voice of its own.

`Haptics.vehicle(isElectric:)` is the exception, and the only haptic in the app that carries
meaning rather than confirming a tap landed. Gasoline gets `friction()` — six sharp
transients about 20ms apart with the intensity wandering, which reads as a rasp rather than
as six taps. Electric gets `smooth()` — one continuous event at low sharpness, shaped by an
intensity curve so it swells and falls away. A thing full of moving parts against a thing
with almost none.

Both are Core Haptics, because the stock impact styles are five weights of the same knock
and these two have to be told apart by feel. Devices without a Taptic Engine fall back to
`.rigid` and `.soft`. **The Simulator plays no haptics at all** — these can only be judged
on a real phone.

A haptic on a control is opt-in: `SegmentedTrough` takes a `haptic` closure and six of the
app's seven leave it nil. Buzzing on every segmented tap says only that the tap landed,
which the pill sliding across already said.

---

## Things that have bitten, and the rule that came out of each

- **A view that renders as empty is an `EmptyView`, and SwiftUI never runs `.task` on one.**
  Give a conditional view a real else-branch (`Color.clear.frame(width: 0, height: 0)`) or
  its fetch never fires. Cost this app every park photograph once, and the route weather
  glyphs once.
- **`preferredColorScheme` written inside a `TabView` page does not reliably reach the
  window.** Set it at `RootShell`, keyed on tab.
- **A `Binding` whose `get` closure reads state registers no Observation dependency.** Read
  the value in the body first, then close over it.
- **`swipeActions` only works inside a `List`.** In a `VStack`/`ScrollView` it compiles and
  does nothing. Use a visible control or a `Menu`.
- **`GeometryReader` reports intermediate sizes.** If a size is part of a cache key, let the
  layout settle (`try? await Task.sleep(...)` at the top of a `.task(id:)`, which cancels on
  change) or the cache thrashes.
- **NPS fails *open* on an unknown park code** — it answers with the first fifty units
  alphabetically. Always check the answer is for the park you asked about.
- **Never print a placeholder number.** `0°` for "no forecast" reads as a freezing day. Draw
  nothing, or say what is missing.

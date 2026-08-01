# ParkHop — every screen

Eighteen screens, one per section, each with a **name in bold**. Write your notes under
the screen you mean and I will know exactly what you are looking at — "T1 hero is too
tall", "K3 rows are the wrong order". Nothing else needs to be said.

Captured from v2.12.0 on iPhone 16 Pro, iOS 26.4, located in Denver.

Anything marked ⚠ is a known gap, not something to report.

---

## Today

### **T1 — Today**

The home screen. One recommendation, the parks near it, the driving day, stamps within
reach. Recalculated every launch from where you are, today's forecast at each candidate,
and which parks you have not been to.

![Today](screens/today.png)

**Feedback:**
-

---

## Trips

### **T2 — Trips**

Trips on the books and trips behind you. The map is Apple Maps, monochrome. The trash
disc removes a trip.

![Trips](screens/trips.png)

**Feedback:**
-

### **T3 — Trip · Route**

Parks in visiting order with the legs between them. The first row is the drive from where
you are standing, routed by OSRM. Tapping any leg opens its own sheet.

![Trip route](screens/trip-route.png)

**Feedback:**
-

### **T4 — Trip · Days**

Day by day. ⚠ Still reads the curated ten-day itinerary.

![Trip days](screens/trip-days.png)

**Feedback:**
-

### **T5 — Trip · Stays**

Where you sleep each night. ⚠ Curated; Recreation.gov blocks non-browser callers, so
there is no live availability.

![Trip stays](screens/trip-stays.png)

**Feedback:**
-

### **T6 — New trip**

Step one of three: pick parks in visiting order. ⚠ This search still reads the eight
curated parks, not the on-device list of sixty-two.

![New trip](screens/new-trip.png)

**Feedback:**
-

---

## Discover

### **D1 — Discover**

The catalogue with an empty field: the curated shelf, and the on-device brief above it.

![Discover](screens/discover.png)

**Feedback:**
-

### **D2 — Discover · suggestions**

Two letters in. States and parks match locally and appear on the keystroke; towns come
from Nominatim a moment later.

![Discover suggestions](screens/discover-suggestions.png)

**Feedback:**
-

### **D3 — Discover · results**

A state search. The line under the chips says how many and from which source — the
on-device list first, then Apple Maps, then OpenStreetMap filling in behind.

![Discover results](screens/discover-results.png)

**Feedback:**
-

### **D4 — Discover · state parks**

The other catalogue: 470 units on the phone, plus whatever OpenStreetMap finds around the
place you typed.

![State parks](screens/discover-state.png)

**Feedback:**
-

---

## Park

Five segments of one screen. **K6** is the same screen for a park that is not one of the
eight — worth comparing, because it shows what the app says when a source is silent.

### **K1 — Park · Overview**

Reservations, alerts, gates, airports, and charging, fuel and shops from Apple Maps.

![Park overview](screens/park-overview.png)

**Feedback:**
-

### **K2 — Park · Weather**

Today at the park, from the National Weather Service and Open-Meteo. ⚠ WeatherKit sits in
front of both and is switched off until the developer account is paid.

![Park weather](screens/park-weather.png)

**Feedback:**
-

### **K3 — Park · Stay**

In-park campgrounds and lodges, then campgrounds, RV parks, beds and food around the park
from Apple Maps. Tapping a row opens directions.

![Park stay](screens/park-stay.png)

**Feedback:**
-

### **K4 — Park · Plans**

Day plans written around the light and the crowds. ⚠ Curated, for the eight parks only.

![Park plans](screens/park-plans.png)

**Feedback:**
-

### **K5 — Park · Nearby**

Passport units within reach. ⚠ Curated.

![Park nearby](screens/park-nearby.png)

**Feedback:**
-

### **K6 — Park · from the live catalogue**

Guadalupe Mountains, opened from the on-device list rather than the curated eight. Every
field the source does not publish says so instead of guessing.

![Live park](screens/park-live.png)

**Feedback:**
-

---

## Saved and Profile

### **S1 — Saved**

Bookmarked parks and the passport book.

![Saved](screens/saved.png)

**Feedback:**
-

### **P1 — Profile**

Notifications, offline packs, travel defaults, and what the app is holding. The
photograph figure is measured off the disk; the pack figure is not.

![Profile](screens/profile.png)

**Feedback:**
-

---

## How these were captured

Taps cannot be synthesised on this simulator, so the app takes launch arguments to reach
a screen directly. Same arguments if you want to reproduce any of them:

```
xcrun simctl launch --terminate-running-process <device> us.parkhop.waypost <args>

-wpTab today|trips|discover|saved|me     a tab
-wpPark <code> -wpSeg overview|weather|stay|plan|near
-wpTrip <id>   -wpTripSeg route|days|stays
-wpSearch <term>          Discover, with the field focused and searched
-wpStateParks 1           Discover, on the state-park side
-wpBuilder 1              the new-trip sheet
```

Not captured: the four bottom sheets (alert, permit, leg, stamp), which need a tap on a
row to reach, and the zoom transition between a card and the park screen, which is motion
rather than a screen.

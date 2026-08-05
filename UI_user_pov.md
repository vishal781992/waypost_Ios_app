# Waypost/ParkHop UI Improvements — User Point of View

## Purpose
This document tells the implementation AI what users are likely to feel while using the current app, how to remove those pain points, and which code areas must change. It complements `HP_changes.md`: this file is the user-experience contract; `HP_changes.md` remains the technical/data-truth contract. Implement both together.

Do not “solve” a pain point with copy or visual polish while leaving false, simulated, stale, or hard-coded behavior underneath. A UI may claim `Live`, `Downloaded`, `Connected`, `Checked`, or `Available` only when the underlying service/platform state proves it. Bundled and cached data must show source and freshness and must never masquerade as current live data.

## User experience goal
A user should always be able to answer:
1. Where am I in the app?
2. What can I do next?
3. Is this information live, cached, bundled, modelled, or unavailable?
4. When was it last updated?
5. What happened after my action?
6. Can I retry, cancel, undo, or continue manually?
7. Will this information still be available without signal?

The dominant current risk is **uncertainty**. The app must replace uncertainty with provenance, clear states, recovery actions, and honest platform behavior.

## Priority definitions
- **P0 — Trust or safety blocker:** misleading behavior, privacy contradiction, or a flow that can leave the user stranded.
- **P1 — Core task blocker:** prevents discovering, planning, saving, or using a trip reliably.
- **P2 — Significant friction:** accessibility, navigation, readability, recovery, and consistency.
- **P3 — Delight/polish:** improvements after the task is correct and dependable.

## Required format for implementation work
For every item, the AI must report:
- User pain removed.
- Files and symbols changed.
- Before/after behavior.
- Dynamic source or platform API used.
- Loading/empty/partial/stale/offline/error handling.
- Accessibility and localization behavior.
- Tests and device/simulator scenarios run.

# Journey 1 — First launch, identity, privacy, and trust

## Pain point 1: “Is this Waypost or ParkHop?” — P1
**What the user feels:** Confusion before trust is established. The Home Screen name, project name, and in-app language can appear to describe different products.

**Why it happens:** `CFBundleDisplayName` is `ParkHop` while source/project documentation prominently says `Waypost`.

**Change:**
- Choose one customer-facing product name and one optional company/subtitle relationship.
- Apply it consistently to the app icon label, launch appearance, navigation titles, permission text, settings, privacy/support copy, README, screenshots, and App Store metadata.

**Change locations:** `Waypost/Info.plist`, `project.yml`, `Waypost/App/WaypostApp.swift`, Profile/About UI in `Waypost/Features/Profile/ProfileScreen.swift`, `README.md`, `docs/SCREENS.md`.

**Acceptance:** a user sees one product identity from installation through every in-app and system surface.

## Pain point 2: “Why does a new app already know things about me?” — P0
**What the user feels:** Seeded trips, completed tasks, saved parks, stamps, ready packs, and journal counts look like another person's data or fabricated personalization.

**Solution:**
- New production installs must begin with empty user-owned state.
- Put sample data only in previews, debug capture fixtures, and UI-test launch environments.
- Replace fake personalization with a short first-run setup and useful empty states.

**Change locations:**
- `Waypost/State/AppState.swift`: initial `day`, `doneItems`, `journalCount`, `packs`, `saved`, `stamps`, notification defaults, and seed trip behavior.
- `Waypost/App/CaptureHooks.swift`: make all fixture mutation debug/test-only.
- Empty states in `TodayScreen.swift`, `TripsScreen.swift`, and `SavedScreen.swift`.

**UX tips:** Never show an empty blank page. Explain the benefit, provide one primary action, and optionally one secondary action. Example: `No trips yet` + `Plan a trip` + `Browse parks`.

**Acceptance:** a clean release install shows no personal history, but each empty state provides a clear way forward.

## Pain point 3: “What happens to my location?” — P0
**What the user feels:** The permission request is difficult to trust because it says location is never sent anywhere, while app features depend on external providers. Denial can also lead to hidden IP geolocation.

**Solution:**
- Add a pre-permission screen explaining the value, data path, and choices.
- Offer `Use Current Location`, `Choose a City`, and `Not Now`.
- Never call IP geolocation after denial without separate explicit consent.
- Rewrite system permission copy and privacy details to match actual behavior.
- Show and allow changing the active origin/location on Today and trip planning screens.

**Change locations:** `Waypost/Info.plist`, `Waypost/Services/LocationService.swift`, `Waypost/Services/Recommender.swift`, `TodayScreen.swift`, `NewTripSheet.swift`, `ProfileScreen.swift`, and the privacy manifest required by `HP_changes.md`.

**UX tips:** Ask in context, not immediately on launch. Manual city selection must remain a first-class path, not an error fallback.

**Acceptance:** denial causes no third-party location request; the user can complete core browsing/planning without location permission.

# Journey 2 — Today and returning-user dashboard

## Pain point 4: “Why is this park recommended?” — P1
**What the user feels:** A single recommendation feels arbitrary or promotional when its reasoning is hidden.

**Solution:**
- Add a compact `Why this park` explanation using real factors: origin, distance, forecast, alerts, visit history, saved preferences, and data freshness.
- Provide `Change origin`, `See another`, and `Browse all` actions.
- If recommendation inputs are incomplete, state what is missing instead of pretending confidence.

**Change locations:** `Waypost/Services/Recommender.swift`, `NearbyBriefing.swift`, `Waypost/Features/Today/TodayScreen.swift`, and recommendation models currently held by `AppState.swift`.

**UX tips:** Limit the explanation to the top two or three factors. Let details expand on demand. Do not expose raw provider jargon in the main card.

**Acceptance:** a user can explain why the recommendation appeared and can change its inputs without hunting in Profile.

## Pain point 5: “Today does not feel like my actual day” — P0
**What the user feels:** Hard-coded day-five and curated trip content creates fake immediacy.

**Solution:** derive the dashboard from an injected current clock, actual active trip dates, current/manual origin, and user-owned completion history. If there is no active trip, show planning/nearby content rather than an invented trip day.

**Change locations:** `AppState.swift` (`day`, `today`, seed trip), `TodayScreen.swift`, `Waypost/Design/Clock.swift`, and trip persistence.

**Acceptance:** changing device/test date or active trip changes Today deterministically; no trip-specific content appears without an actual matching trip.

## Pain point 6: “I cannot tell what is still loading” — P2
**What the user feels:** Sections arrive from different services, causing cards to appear, disappear, or reorder without explanation.

**Solution:**
- Give recommendation, nearby, weather, and stamps independent load states.
- Use skeletons that preserve final geometry.
- Mark progressive sections with subtle `Updating…` text.
- Preserve scroll position and avoid reordering already visible items unless the user requests sorting.
- Keep successful sections visible when another source fails.

**Change locations:** `TodayScreen.swift`, `Recommender.swift`, `NearbyBriefing.swift`, feature state extracted from `AppState.swift`.

**Acceptance:** partial data is useful, loading is visible, and late responses do not make the interface jump under the user's finger.

# Journey 3 — Navigation and orientation

## Pain point 7: “Switching tabs loses where I was” — P1
**What the user feels:** Returning to a tab does not restore the park, trip, or scroll context the user was viewing.

**Solution:** give Today, Trips, Discover, Saved, and Profile independent navigation paths. Preserve paths when switching tabs and reset only after an explicit action such as tapping the selected tab again, if that behavior is intentionally implemented.

**Change location:** `Waypost/App/WaypostApp.swift`, especially `RootShell`, `selection`, `tabStack`, and the shared `$app.stack`; navigation state currently in `AppState.swift`.

**Acceptance:** open a park in Discover, switch to Saved, navigate there, and return to Discover; both tabs restore their own destinations.

## Pain point 8: “I do not know whether to go Back, close, or switch tabs” — P2
**What the user feels:** Push screens, two sheet channels, quick search, and the trip builder can create inconsistent dismissal behavior.

**Solution:**
- Define one navigation rule: tabs contain stacks; temporary tasks use sheets; destructive/choice confirmations use dialogs.
- Use consistent Close/Cancel placement and preserve interactive swipe dismissal unless unsaved work needs confirmation.
- Warn before dismissing a trip builder with unsaved changes.
- Restore focus to the initiating control after sheet dismissal.

**Change locations:** `WaypostApp.swift`, `QuickSearchSheet.swift`, `NewTripSheet.swift`, `DetailSheet.swift`, and routing/sheet state in `AppState.swift` or its replacement router.

## Pain point 9: “I missed the confirmation” — P2
**What the user feels:** A toast disappears before it can be read and may be inaccessible.

**Solution:**
- Use inline persistent status for downloads, errors, and configuration.
- Use toasts only for low-risk confirmation, with accessibility announcements and sufficient duration.
- Add Undo for reversible Save/Delete actions where appropriate.

**Change locations:** toast presentation in `WaypostApp.swift`, action methods and `show()` behavior in `AppState.swift`, affected screens.

# Journey 4 — Discover and search

## Pain point 10: “Search looks frozen” — P1
**What the user feels:** Some providers are slow enough that the app appears broken.

**Solution:**
- Show local catalogue results immediately.
- Display provider progress in user language, not implementation language.
- Enforce a short initial-result target and a finite overall deadline.
- Offer Retry and `Show on-device results only`.
- Cancel work as the query changes or the screen closes.

**Change locations:** `DiscoverScreen.swift`, `ParkDirectory.swift` (`search`, `run`, Nominatim and Overpass paths), `SearchSuggestions.swift`, `Nominatim.swift`.

**UX tips:** A user should see a useful local response in under roughly 300 ms when data is on-device. Slow live enrichment should never block local results.

**Acceptance:** the screen never spins indefinitely; users can continue with local/cached results while live providers update.

## Pain point 11: “Does no result mean no park or no internet?” — P0
**What the user feels:** Empty and failed states can look the same, making the directory untrustworthy.

**Solution:** present distinct states:
- `No matching parks found` only after a source validly answers.
- `Could not reach live sources` with cached/on-device alternatives.
- `Still searching other sources` for partial progress.
- `Search cancelled` only when useful to communicate.

**Change locations:** `ParkDirectory.finish`, `nominatim`, Overpass response handling, `DiscoverScreen.swift` empty/error UI.

**Acceptance:** tests and UI visibly distinguish valid empty, timeout, refusal, malformed response, cached fallback, and partial success.

## Pain point 12: “Results move while I am tapping” — P2
**What the user feels:** Progressive merging can reorder rows and create mistaps.

**Solution:** maintain stable IDs and stable ordering for already presented results. Append `More results` or update ranking only after the user requests it. Animate insertions without shifting the row under active touch.

**Change locations:** `ParkDirectory` ordering/deduplication and result rendering in `DiscoverScreen.swift`/`NearbyCard.swift`.

## Pain point 13: “Why are there duplicate parks?” — P1
**What the user feels:** NPS, Apple Maps, and OpenStreetMap may produce near-duplicate records, reducing confidence.

**Solution:** build a stable identity resolver using authoritative IDs, coordinates, designation, aliases, and normalized names. Preserve all source attribution on one merged record.

**Change locations:** `ParkDirectory.deduped`, `Curated.swift`, `LivePark.swift`, `NationalParks.swift`, and the future shared `ParkRepository` described in `HP_changes.md`.

## Pain point 14: “The source labels sound technical” — P2
**What the user feels:** Nominatim, Overpass, proxy, and provider details are not meaningful during normal planning.

**Solution:** use plain primary labels (`Official park data`, `Apple Maps`, `Community map`, `Saved on this iPhone`) and place technical/provider details in an expandable source sheet.

**Change locations:** source badges/lines in `DiscoverScreen.swift`, `ParkScreen.swift`, `DetailSheet.swift`, and source models.

## Pain point 15: “I found a park but cannot add it to a trip” — P0
**What the user feels:** Discover promises a broad catalogue while New Trip only accepts the curated subset. The core journey breaks.

**Solution:** use one stable park repository and identity model across Today, Discover, Park, Saved, and Trips. Add `Add to Trip` from Park and search results, and let New Trip search the same directory.

**Change locations:** `DiscoverScreen.swift`, `ParkScreen.swift`, `NewTripSheet.swift`, `AppState.TripBuilder.results`, `ParkDirectory.swift`, and models/repository introduced by `HP_changes.md`.

**Acceptance:** any supported discovered park can be opened, saved, and added to a trip without substitution or data loss.

# Journey 5 — Park details

## Pain point 16: “I have to search the screen for basic visit information” — P1
**What the user feels:** Important answers are distributed across Overview, Weather, Stay, Plan, and Nearby.

**Solution:** add a compact `Visit essentials` block near the masthead containing real, source-aware status for opening/alerts, reservation need, forecast summary, distance, and offline readiness. Each item deep-links or scrolls to detail.

**Change locations:** `Waypost/Features/Park/ParkScreen.swift`, park models, weather/alert/place state.

**UX tips:** Prioritize actionable risk over promotional content. A closure or severe alert should appear before a large hero image or descriptive tag line.

## Pain point 17: “The photo blocks useful information” — P2
**What the user feels:** The fixed 372-point hero is attractive but costly on a small phone.

**Solution:** make hero height responsive, consider collapsing it on scroll, and reduce it when alerts or active-trip information needs priority. Preserve visual identity without making users scroll before every task.

**Change location:** `ParkScreen.hero` and masthead layout.

## Pain point 18: “Text and controls are difficult outdoors” — P1
**What the user feels:** Small 10–12.5-point text, low opacity, narrow tracked uppercase labels, and 40-point buttons are hard to read/tap in sunlight or with reduced vision.

**Solution:**
- Raise metadata sizes and contrast.
- Use semantic colors rather than opacity for hierarchy.
- Make every control at least 44×44 points, preferably 48 for primary actions.
- Reflow weather grids to one column at accessibility sizes.
- Let meaningful text wrap rather than shrinking to 70%.

**Change locations:** `ParkScreen.swift`, `Waypost/Design/Tokens.swift`, `Glass.swift`, and reusable row/control components.

## Pain point 19: “No forecast might mean the app failed” — P1
**What the user feels:** Missing weather is ambiguous and there is no obvious retry.

**Solution:** replace the `asked` Boolean and throwaway `FailureLog()` with explicit loading/loaded/empty/stale/failed state. Show forecast horizon, source, update time, stale cache, and Retry.

**Change locations:** Park weather section in `ParkScreen.swift`, `WeatherService.swift`, `AppleWeather.swift`, shared error/state models.

## Pain point 20: “My units preference is ignored” — P1
**What the user feels:** Choosing metric but seeing miles, mph, or Fahrenheit makes settings feel fake.

**Solution:** centralize measurement formatting and either request preferred API units or convert domain measurements at presentation. Update every screen immediately when preference changes.

**Change locations:** `AppState.unitsMetric` or `SettingsStore`, `WeatherService.swift`, `PlacesService.swift`, Park/Today/Trip screens, route models and formatters.

## Pain point 21: “I cannot tell how current this information is” — P0
**What the user feels:** Closures, weather, availability, cached data, historical normals, and curated content can look equally current.

**Solution:** every operational section must carry a consistent source/freshness line such as `Official park data · updated 18 min ago`, `Historical average`, `Saved yesterday`, or `Unavailable`. Do not overload the main UI; use one consistent compact pattern and a detail sheet.

**Change locations:** source models in `Curated.swift`/`LivePark.swift`, service return types, `ParkScreen.swift`, `DetailSheet.swift`, shared components.

# Journey 6 — New trip planning

## Pain point 22: “Choosing dates feels like a demo” — P0
**What the user feels:** Cycling through hard-coded English date labels prevents real planning.

**Solution:** use a calendar/date-range picker with duration, past-date validation, calendar/time-zone handling, and locale formatting. Persist `Date`/time-zone domain values, never display strings.

**Change locations:** `AppState.TripBuilder.candidateStarts`, `startLabel`, `cycleStart`, `NewTripSheet.swift`, `SavedTrip` models/persistence.

## Pain point 23: “Origin selection is unclear or limited” — P1
**What the user feels:** The starting point may be guessed, approximate, or difficult to change.

**Solution:** provide current location, manual city/address/airport search, recent origins, and saved home. Clearly label approximate location and show the selected origin on review.

**Change locations:** `NewTripSheet.swift`, `LocationService.swift`, `SearchSuggestions.swift`/geocoding services, city/airport models and settings.

## Pain point 24: “Did the app preserve my order or optimize it?” — P1
**What the user feels:** The UI claims road-distance ordering but composition currently preserves the selected order.

**Solution:** present an explicit choice: `Keep my order` or `Optimize route`. If optimization changes order, preview before/after with time/distance impact and require confirmation.

**Change locations:** `AppState.TripBuilder`, `NewTripSheet.swift`, `TripRouting.swift`, future `TripComposer`.

## Pain point 25: “The progress looks real, but the work was not done” — P0
**What the user feels:** Routing, weather, campsite checks, and offline sizing appear verified when they are not. This can cause unsafe or costly decisions.

**Solution:** replace decorative steps/timers with actual asynchronous stages. Each stage reports pending/running/succeeded/failed/skipped and evidence. Allow cancel and retry. Never claim availability was checked if the provider refused it.

**Change locations:** `AppState.TripBuilder.composeSteps` and `compose()`, composition animation in `NewTripSheet.swift`, `TripRouting.swift`, `TravelServices.swift`, `WeatherService.swift`, offline manager.

**Acceptance:** progress advances only after real stage completion; partial trips clearly identify unavailable sections.

## Pain point 26: “I may lose my work by closing the builder” — P2
**What the user feels:** A long multi-step form needs draft protection.

**Solution:** autosave a versioned draft after meaningful edits, restore it intentionally, provide `Discard Draft`, and confirm interactive dismissal when unsaved changes exist.

**Change locations:** `NewTripSheet.swift`, trip builder state extracted from `AppState.swift`, trip persistence.

# Journey 7 — Trip list and trip detail

## Pain point 27: “The itinerary does not match what I planned” — P0
**What the user feels:** A curated fixed itinerary can appear for different parks/durations.

**Solution:** generate day sections from the actual selected parks, dates, durations, travel legs, opening constraints, and available activities. If dynamic day planning is not ready, label the section unavailable rather than showing an unrelated template.

**Change locations:** `TripDetailScreen.swift`, `TripPresentation.swift`, relevant logic in legacy `TripStore.swift`, curated day records in `AppState`/models.

## Pain point 28: “I cannot tell what is estimated” — P1
**What the user feels:** Route, weather, historical normals, budget, and availability can be interpreted as equally certain.

**Solution:** create a consistent confidence/provenance vocabulary: `Live`, `Updated`, `Historical average`, `Estimate`, `Curated guide`, `Not checked`, and `Unavailable`. Provide timestamp and source detail without cluttering every value.

**Change locations:** `TripDetailScreen.swift`, `TripPresentation.swift`, weather/routing/availability models and shared badges.

## Pain point 29: “My route may be old” — P1
**What the user feels:** There is no obvious last-routed time or refresh action.

**Solution:** show route age, allow section-level refresh, automatically suggest refresh near departure, and retain the previous route while updating. Do not overwrite a valid route with an error.

**Change locations:** `TripRouting.swift`, route cache/persistence, `TripDetailScreen.swift`.

## Pain point 30: “There is no departure-ready summary” — P1
**What the user feels:** Alerts, reservations, weather, lodging, charging/fuel, route freshness, and offline status are scattered.

**Solution:** add a dynamic pre-departure checklist generated from actual trip/source state. Each warning links to its resolution. Never hard-code completion.

**Change locations:** `TripDetailScreen.swift`, `TodayScreen.swift` for active-trip cards, notification/offline/routing/weather repositories.

## Pain point 31: “I cannot easily use the plan with other people/apps” — P2
**What the user feels:** Missing share/export/handoff makes the planner isolated.

**Solution tips:** after core truth is fixed, add shareable summaries, calendar export, Apple Maps handoff, printable/PDF field sheet, and deep links. Clearly define privacy before collaborative links.

**Change locations:** new share/export service, `TripDetailScreen.swift`, routing models, URL/deep-link routing in `WaypostApp.swift`.

# Journey 8 — Offline use

## Pain point 32: “It says downloaded, but I may still be stranded” — P0
**What the user feels:** Simulated packs create false confidence before entering a no-signal area.

**Solution:** implement real manifest-based packs with actual bytes, verification, expiry, cancellation, repair, and offline reads. Until complete, remove `Pack on device` and `works with no signal` claims.

**Change locations:** `AppState.startPack`, `packs`, `packProgress`, `packStorageMB`; `ParkScreen.actions`; `PhotoStore.swift`; service caches; new `OfflinePackManager` defined in `HP_changes.md`.

## Pain point 33: “What does the pack contain?” — P1
**What the user feels:** `Offline pack` is too vague for a safety-relevant feature.

**Solution:** show a pre-download manifest summary and post-download coverage:
- Park essentials
- Trip/route data
- Maps, if legally/technically supported
- Photos
- Weather snapshot with expiry
- Alerts snapshot with expiry
- Missing online-only sections

**UX tips:** Do not imply that old weather/alerts remain safe indefinitely. Keep static park facts separate from time-sensitive data.

## Pain point 34: “I cannot verify readiness before losing signal” — P1
**Solution:** add `Check offline readiness` and a test mode that performs reads without network. Report verified, stale, missing, and online-only sections. Surface this in Trip Detail and the pre-departure checklist.

**Change locations:** offline manager, `TripDetailScreen.swift`, `ParkScreen.swift`, `ProfileScreen.swift` storage UI.

## Pain point 35: “Storage numbers are not real” — P1
**Solution:** report actual file sizes and allow per-pack deletion, cache deletion, repair, and refresh. Warn about low disk space and expensive/constrained networks.

# Journey 9 — Saved parks and passport

## Pain point 36: “Saved, visited, stamped, and downloaded look like the same thing” — P2
**What the user feels:** Personal collection states are ambiguous.

**Solution:** visually and semantically separate:
- Saved for later
- Added to trip
- Visited
- Passport stamp earned/recorded
- Offline available

**Change locations:** `SavedScreen.swift`, Park actions, models/state in `AppState.swift` or new repositories, accessibility labels.

## Pain point 37: “What does a passport stamp prove?” — P1
**Solution:** define a truthful rule: explicit user record, verified location check-in with consent, or imported physical stamp. Explain it and never pre-award stamps. If verification is not implemented, call it `Mark visited`, not a verified stamp.

**Change locations:** `SavedScreen.swift`, Profile passport UI, stamp actions/models in `AppState.swift`, `DetailSheet.swift` stamp sheet.

## Pain point 38: “A saved park disappears when a provider fails” — P1
**Solution:** persist stable ID plus a minimal snapshot and source metadata. Rehydrate live details when available while keeping the saved record visible offline.

# Journey 10 — Profile, settings, and platform features

## Pain point 39: “Connected does not mean connected” — P0
**What the user feels:** A green/positive state can be based only on a URL prefix.

**Solution:** validate HTTPS URL syntax and perform a health request. Show `Not configured`, `Checking`, `Connected`, `Refused`, `Unreachable`, and `Invalid address`.

**Change location:** `ProxyConfig` in `Waypost/Services/Network.swift`, proxy settings UI in `ProfileScreen.swift`.

## Pain point 40: “Notification settings may do nothing” — P0
**Solution:** reconcile UI with `UNUserNotificationCenter` authorization and real scheduled requests. Explain denied system permission and link to Settings. Remove toggles that only persist local Booleans.

**Change locations:** notification flags in `AppState.swift`, notification UI in Profile/Today, new notification manager and app configuration.

## Pain point 41: “Live Activity says On, but nothing appears” — P0
**Solution:** integrate ActivityKit and display actual activity status/eligibility, or remove/disable the control. Do not use a local Boolean as platform status.

**Change locations:** `AppState.toggleLiveActivity`, Today controls, `project.yml`, entitlements/ActivityKit support.

## Pain point 42: “Add photo does not add a photo” — P0
**Solution:** use `PhotosPicker`/camera, persist a real local asset/file with metadata, show thumbnail and deletion, and handle permission/storage errors. Remove count-only behavior.

**Change locations:** `AppState.addJournalPhoto`, Today journal UI, new journal/photo persistence.

## Pain point 43: “I cannot control my local data” — P1
**Solution:** add a privacy/data section for provider disclosure, location choice, cache/offline storage, and deletion. Include `Delete cache`, `Delete offline packs`, `Delete trips and saved data`, and `Delete all local data` with clear consequences.

**Change locations:** `ProfileScreen.swift`, persistence repositories, `PhotoStore.swift`, offline manager, settings store.

# Journey 11 — Accessibility, appearance, and inclusion

## Pain point 44: “The app is uncomfortable at night” — P2
**Solution:** support semantic dark mode and remove forced `.preferredColorScheme(.light)`. Validate outdoor contrast in both modes.

**Change locations:** `WaypostApp.swift`, `Tokens.swift`, `PageTint.swift`, `Glass.swift`, all hard-coded colors.

## Pain point 45: “Large text breaks the layout” — P1
**Solution:** test all screens at accessibility sizes; reflow grids, allow wrapping, avoid aggressive caps/minimum scale factors, and preserve primary actions.

**Change locations:** `Tokens.swift`, Park weather/stat grids, cards and rows across Today/Trips/Discover/Saved/Profile/Sheets.

## Pain point 46: “VoiceOver does not explain custom UI” — P1
**Solution:** audit custom tab icons, glass buttons, segment rails, maps, source dots, weather values, cards, and dismissals. Add labels, values, hints, headings, selected traits, grouping, sort priority, and focus restoration.

**Change locations:** `WaypostApp.swift`, `Glass.swift`, `ParkScreen.swift`, every feature screen, map/row components.

## Pain point 47: “Animation or glass makes the app harder to use” — P2
**Solution:** honor Reduce Motion, Reduce Transparency, Increase Contrast, and Differentiate Without Color. Do not convey status only through movement/color.

**Change locations:** `Waypost/Design/Motion.swift`, `Glass.swift`, source/status components, toast and navigation transitions.

## Pain point 48: “The app does not fit my language or units” — P1
**Solution:** add String Catalogs, locale-aware dates/numbers/measurements, pluralization, pseudolocalization, RTL validation, and immediate metric/imperial updates.

**Change locations:** every feature screen and user-facing service error, `Info.plist`, shared formatters, models storing display strings.

## Pain point 49: “Portrait-only use is limiting” — P2
**Solution:** support landscape when practical, especially trip/route use, or explicitly validate/document the limitation. Do not assume one fixed width or height.

**Change locations:** `Waypost/Info.plist`, `project.yml`, fixed layouts in feature screens.

# Journey 12 — Reliability and recovery

## Pain point 50: “The app can load forever” — P0
**Solution:** fix `LocationService` continuation ownership and add real deadlines to every provider flow. Every spinner must terminate in loaded, partial, empty, cancelled, or failed state with a useful action.

**Change locations:** `LocationService.swift`, `ParkDirectory.swift`, shared HTTP layer in `Network.swift`, feature models.

## Pain point 51: “Errors tell me what broke, not what to do” — P1
**Solution:** user-facing errors must answer:
1. What did not load?
2. What content remains usable?
3. Is the result cached/stale?
4. Can I retry or continue manually?
5. Does this affect my trip or offline readiness?

Keep technical diagnostics in logs/source details, not the primary message.

**Change locations:** `FailureLog`/HTTP errors in `Network.swift`, Park/Discover/Today/Trip error UI, Profile connectivity UI.

## Pain point 52: “An update could silently erase my information” — P0
**Solution:** version persisted data, migrate old snapshots, retain recoverable backups on decode failure, and tell the user if recovery is needed. Never silently replace corrupt user data with seeded defaults.

**Change locations:** snapshot persistence in `AppState.swift`, legacy persistence in `TripStore.swift`, dataset/photo metadata decode paths, future repositories.

## Pain point 53: “I do not know whether my plans are backed up” — P2
**Solution tip:** clearly state `Stored on this iPhone` until an actual sync/export strategy exists. Add export before implying cloud safety. If CloudKit/account sync is introduced, design conflict resolution and privacy first.

# Cross-screen interaction standards

## Status vocabulary
Use one consistent vocabulary and visual treatment:
- **Live:** provider answered recently within policy.
- **Updated [relative time]:** cached but fresh.
- **Saved [relative time]:** available offline, possibly stale.
- **Historical average / Modelled:** not a forecast.
- **Curated guide:** editorial/bundled, versioned, not live.
- **Not checked:** operation was not attempted or provider unavailable.
- **Unavailable:** attempted and failed, with Retry when possible.

Do not use `Live` merely because a feature exists or a request was started.

## Action hierarchy
- One visually dominant primary action per screen/step.
- Secondary actions must not compete with safety-critical alerts.
- Destructive actions require confirmation or Undo.
- Disable only when the reason is visible; otherwise allow the tap and explain what is required.
- Long work must provide progress and Cancel.

## Loading behavior
- Preserve previous valid content while refreshing.
- Use skeletons matching final geometry.
- Avoid global spinners when only one section is loading.
- Do not clear a list before replacement data arrives.
- Never let late cancelled responses overwrite current state.

## Empty-state behavior
Every empty state must identify whether it is:
- New-user empty.
- Filter/search empty.
- Valid source empty.
- Offline without cache.
- Permission-limited.
- Error/unreachable.

Provide the most useful next action for that cause.

## Forms and keyboards
- Correct keyboard type, content type, capitalization, and submit action.
- Keep primary controls visible above the keyboard.
- Validate inline without erasing input.
- Preserve drafts across accidental dismissal/backgrounding.
- Move accessibility focus to the first error on submission.

## Maps
- Do not rely on pins/colors alone.
- Provide a list alternative.
- Expose route/source freshness.
- Preserve user pan/zoom unless they request recentering.
- Provide Apple Maps handoff for navigation; do not present a planning route as turn-by-turn guidance.

# Practical UI improvement tips
1. Prioritize `what can affect my visit today` over decorative content.
2. Use progressive disclosure: simple source/freshness line first, technical detail in a sheet.
3. Keep core actions reachable with one thumb and at least 44×44 points.
4. Design outdoor-first: stronger contrast, larger text, minimal glare, clear offline status.
5. Keep list identity and ordering stable as asynchronous results arrive.
6. Preserve successful content during refresh and partial failure.
7. Make manual input a valid path whenever permissions/services fail.
8. Explain why a disabled action is unavailable and what unlocks it.
9. Show timestamps in relative form with exact time in details.
10. Use haptics sparingly for successful, user-initiated state changes—not background updates.
11. Never replace a source error with an invented estimate.
12. Test tasks, not screenshots: `find a park, add it, plan it, download it, and use it offline`.

# Implementation order by user impact

## Phase 1 — Restore trust
1. Remove seeded personal data.
2. Correct location consent/privacy and hidden IP fallback.
3. Remove misleading offline/composition/notification/Live Activity/photo claims until real.
4. Fix indefinite location/loading states.
5. Correct product naming.

## Phase 2 — Unblock core journeys
1. One shared park identity/repository across Discover, Park, Saved, and Trips.
2. Real date/origin selection.
3. Real, cancellable trip composition with partial results.
4. Independent navigation path per tab.
5. Clear loading/empty/error/stale states and Retry.

## Phase 3 — Make plans dependable
1. Actual itinerary derived from the user's trip.
2. Route/weather/availability provenance and refresh.
3. Real offline packs and readiness verification.
4. Real notification/platform integrations.
5. Persistence migrations and recovery.

## Phase 4 — Make the app inclusive and polished
1. Dynamic Type and touch targets.
2. VoiceOver/control accessibility.
3. Dark mode, contrast, motion/transparency accommodations.
4. Localization, RTL, and complete unit formatting.
5. Sharing/export and other delight features.

# End-to-end acceptance scenarios
The AI must validate these user stories, not only isolated controls:

1. **Privacy-first new user:** clean install → decline location → no IP request → choose city → browse nearby parks.
2. **Discovery to trip:** search for a non-curated park → open → save → add to new trip → reopen successfully.
3. **Truthful failure:** disable network → search and open cached park → see source/age → unavailable live sections show Retry, not fake emptiness.
4. **Real planning:** choose arbitrary parks/date/origin → compose → stages call real clients → partial provider failure remains understandable → save trip.
5. **Navigation memory:** navigate deeply in two tabs → switch repeatedly → each tab restores its path and relevant scroll position where designed.
6. **Offline readiness:** download a real pack → verify manifest/files → disable network → open trip and park → clearly distinguish available, stale, and missing content.
7. **System integration:** deny notifications/Live Activities/photos → UI reflects actual denial and offers appropriate Settings/manual recovery; no false success toast.
8. **Accessibility:** complete Discover-to-Trip using VoiceOver and largest Dynamic Type; all controls remain reachable and understandable.
9. **Localization:** run pseudolocalized/RTL and metric configurations; no clipped critical text or mixed units.
10. **Upgrade safety:** install old persisted fixture → upgrade → trips/saves/settings migrate without silent reset.

# Final UX acceptance checklist
- [ ] A clean install feels empty but useful, never pre-personalized.
- [ ] The product name is consistent everywhere.
- [ ] Location use is understandable, optional where possible, and privacy copy is accurate.
- [ ] Every screen communicates what is loading, available, stale, offline, or failed.
- [ ] No fake timer, Boolean, seed, or static itinerary creates a success claim.
- [ ] Users can move from any discovered park into Save and Trip flows.
- [ ] Dates, origin, routes, weather, and itinerary respond to actual user selections.
- [ ] Tabs preserve independent navigation context.
- [ ] Park and trip screens prioritize alerts and visit essentials.
- [ ] Offline readiness corresponds to verified readable files.
- [ ] Settings reflect actual system behavior and affect the entire app.
- [ ] Touch targets, text, contrast, VoiceOver, motion, and Dynamic Type meet accessibility expectations.
- [ ] Errors provide recovery and preserve still-useful content.
- [ ] Persistence upgrades cannot silently replace user data with defaults.
- [ ] Tests cover the complete user stories above.

## AI completion report
When changing an item in this document, cite its pain-point number in the implementation summary and commit/PR description. Do not mark it complete based on a screenshot alone. Include the tested user journey, source/freshness behavior, accessibility result, failure/offline result, and remaining limitations.
---

# Implementation log

## Phase 1 — Reliability: the app can load forever (Pain point 50)

Partially advances Pain point 6 (independent load states) and Pain point 51 (errors offer recovery). Does **not** close either.

### User pain removed
Three of the app's location-dependent surfaces could spin indefinitely, and on a first
launch they always did. The Today hero never resolved, the Discover "Brief me" card span
forever, and "near me" search stayed on `Searching…` with no terminal state. Once the
Today hero stalled, recommendations were dead for the rest of the process.

### Root cause
`LocationService.deviceFix()` raced Core Location against a sleeping task inside
`withTaskGroup`. That cannot work: a task group waits for *every* child before returning,
and `cancelAll()` does not resume a `CheckedContinuation`. The 8-second budget elapsed,
computed `nil`, and then the group blocked forever on Core Location anyway. Compounding
it, `requestLocation()` was issued while authorization was still `.notDetermined` — iOS
discards that request, and with no `locationManagerDidChangeAuthorization` implementation
no callback ever arrived. The same task-group pattern was duplicated in `Recommender`
with a 4-second budget.

### Files and symbols changed
- `Waypost/Services/LocationService.swift` — `deviceFix()` rewritten to a single
  continuation with a `deadline` task that resumes it; `pending` changed from one slot to
  an array so concurrent callers share one fix instead of orphaning each other's
  continuations; `resume(_:)` now cancels the deadline and resumes all waiters; added
  `locationManagerDidChangeAuthorization(_:)` and `authorizationChanged()`; added
  `static let shared`.
- `Waypost/Services/Recommender.swift` — removed the duplicated `withTaskGroup` racer;
  calls `location.currentFix()` directly.
- `Waypost/Services/TripRouting.swift`, `NearbyBriefing.swift`, `ParkDirectory.swift` —
  `LocationService()` → `LocationService.shared` (was four managers, four prompts, four
  independent hangs).
- `Waypost/Services/Network.swift` — `timeoutIntervalForResource = 120` (was unset, i.e.
  the 7-day default); `HTTP.any(_ url:)` now sets `request.timeoutInterval = 15`, which
  a hand-built `URLRequest` otherwise overrode with its own 60-second default.

### Before / after
| Scenario | Before | After |
|---|---|---|
| First launch, permission granted | Today hero spins forever | Resolves after the grant |
| First launch, permission denied | Today hero spins forever | Resolves immediately |
| "Brief me" with location off | Infinite spinner | "Location is off, so there is nothing to measure from. Turn it on in Settings and try again." |
| Core Location silent | Never returns | Returns `nil` at 8s |
| Two callers at once | First continuation orphaned, hangs | Both share one fix |

### Platform APIs used
`CLLocationManager` with `locationManagerDidChangeAuthorization(_:)` gating
`requestLocation()`; `withCheckedContinuation` with a `Task.sleep` deadline;
`URLSessionConfiguration.timeoutIntervalForResource`.

### State handling
Terminal states only: every `deviceFix()` call now ends in a fix, `nil` at denial, or
`nil` at the 8-second deadline. The IP fallback remains gated behind
`allowsNetworkFallback` — a refusal still triggers no third-party lookup, so Pain point 3's
privacy contract is unchanged. `timeoutIntervalForResource` was set to 120s deliberately,
clear of the intentional 90-second Overpass budget, so state-wide sweeps are not cut short.

### Accessibility and localization
No changes. Both remain open — Journey 11 is untouched.

### Verified
iPhone 17 Pro simulator, iOS 26.4, Debug build. `xcodebuild` succeeds with no new
warnings. Scenarios run: clean install → grant → Today hero resolves; permission revoked
via `simctl privacy revoke` → relaunch → resolves with no alert and no spinner; Discover →
"Brief me" with location denied → named error state with recovery instruction.

### Remaining limitations
- No automated test covers the deadline path; verification was manual on simulator.
- The 8-second deadline is still a constant, not surfaced to the user, and there is no
  Retry affordance on the Today hero (Pain point 6 remains open).
- `ParkDirectory`'s Overpass fallback can still run three hosts × 90s; the swallowed
  `CancellationError` at `ParkDirectory.swift:468` is untouched and remains a slow-search
  cause, distinct from the hangs fixed here.
- `Recommender.choose` still guards on `pick == nil`, so a session gets one
  recommendation; a failed attempt no longer latches, but there is no explicit refresh.

## Phase 2 — The plan matches what was planned (Pain points 15, 27, 19)

Partially advances Pain points 21, 23 and 28. Does **not** close 22 or 23.

### User pain removed
Three separate failures made a composed trip describe something other than what the user
asked for: a trip planned from Seattle was routed from wherever the phone was, a trip
built around any park outside the curated eight was titled " to " with a blank review row,
and the weather panel answered for today no matter which day the trip fell on.

### Root causes
1. **Origin.** `TripRouting.route` asked Core Location first and read `originCity` only in
   the `else if` — the chosen origin was a fallback for a refused permission, not an
   instruction. `routeApproach` took no origin at all, so trip detail also drew a second
   "Getting there" leg measured from the device.
2. **Titles.** `TripBuilder.compose` and `reviewRows` resolved picks through
   `library.park`, which knows only the eight codes in `curated.json`. The picker offers
   the sixty-two bundled parks (`np-…`) and the state list (`sp-…`), so `parks` came back
   empty and the title was built from two empty strings.
3. **Weather.** `WeatherSection` called `WPDate.iso(Date())` unconditionally and the route
   carried no date, so a trip date could not reach it. Past ~16 days Open-Meteo returns an
   empty day; `normals(lat:lon:iso:)` existed to cover exactly that and was called from
   nowhere in the codebase.

### Files and symbols changed
- `Waypost/Services/TripRouting.swift` — `Phase.routed` carries `OriginSource`
  (`.chosen` / `.device` / `.approximate`) instead of a `precise` Bool; `route` prefers
  `originCity` and only falls back to the device.
- `Waypost/Features/Trips/TripDetailScreen.swift` — `routingNote` says which of the three
  it used; `routeApproach` is now called only for the seed trip; the park row no longer
  prints `0°` for a park with no published weather.
- `Waypost/State/AppState.swift` — `TripBuilder.resolvePark` closure, set by
  `startBuilder`, used by both `compose()` and `reviewRows`; `TripBuilder.title(parks:startLabel:)`
  replaces the inline title expression; trip `id` now includes `origin` so changing it
  cannot hit the previous route cache; `SavedTrip.startDate` parses the display label;
  `PushedScreen.park` and `openPark` carry `date`.
- `Waypost/Features/Park/ParkScreen.swift` — `ParkScreen` and `WeatherSection` take
  `date`; the `.task` is keyed on park *and* day; "August normal" / "Today at this park"
  replaced with the actual day.
- `Waypost/Services/WeatherService.swift` — `forecast` falls back to `normals`.
- `SavedScreen.swift`, `TripsScreen.swift`, `NewTripSheet.swift` — `library.park` →
  `app.park` at the four sites that render user-chosen codes.

### Before / after
| Scenario | Before | After |
|---|---|---|
| Trip from Seattle, phone in Denver | `Denver → Acadia` | `Seattle → Acadia`, home leg `Acadia → Seattle` |
| Routing note | "from your location — Denver" | "from Seattle, the origin this trip was planned from" |
| Trip around Acadia (`np-acadia`) | Title `" to "`, blank review row, `np-acadia` on chips | "Acadia in September", review row "Acadia" |
| Weather for 12 Sept 2026 | Today's forecast, labelled "today" | "September 12", 10-year average, labelled "from Open-Meteo archive" |
| Park with no published weather | `0°` in the trip row | omitted |

### Source and freshness behavior
`OriginSource` distinguishes a chosen origin from a device fix from a loose fix, and the
note names which. The weather panel states the day it is reporting and its source; beyond
the forecast horizon it says "Averaged from N years of M/D (±3 days) at this location"
rather than presenting climatology as a forecast.

### Accessibility and localization
No changes. `SavedTrip.startDate` parses with a fixed `en_US_POSIX` format because the
stored label is itself English — correct for the current data, and one more reason the
underlying string-dates problem (Pain point 22) still needs fixing.

### Verified
iPhone 17 Pro simulator, device location pinned to Denver via `simctl location`, location
permission granted. Built a trip around Acadia from a Seattle origin for 12 September
2026: title, review row, route line, map polyline, both routed legs, the routing note and
the weather panel all checked on screen.

### Remaining limitations
- **Pain point 23 is not closed.** The origin list is still the six cities in
  `curated.json` (`den, slc, las, phx, sea, chi`). There is no free-text or geocoded
  origin, so a trip from Dallas still cannot be planned at all — the reported bug was two
  faults, and only the substitution is fixed.
- **Pain point 22 is untouched.** Dates are still cycled hard-coded English strings;
  `startDate` recovers a `Date` from one rather than storing it properly.
- The route cache is keyed by trip id, which now includes origin, but there is still no
  explicit re-route action (Pain point 29).
- `WeatherSection` still has no retry affordance when both forecast and normals fail.

## Phase 2b — Any city in the country as an origin (Pain point 23)

### User pain removed
`curated.json` shipped six origin cities — Denver, Salt Lake City, Las Vegas, Phoenix,
Seattle, Chicago — and the builder offered no other way to answer "from where". A trip
from Dallas, or from anywhere else in the country, could not be expressed at all. Phase 2
stopped the app substituting the device's location for the chosen origin; this makes the
choice itself unrestricted.

### Change
A search field above the origin list. Two characters bring down up to six matching US
cities; picking one resolves it to coordinates and pins it above the shipped six, which
stay as one-tap shortcuts. Clearing the field does not clear the chosen city.

`MKLocalSearchCompleter` (iOS 9.3+, no key, no entitlement — works on a free developer
account) rather than Nominatim: completions keep pace with typing, and they do not queue
behind the park search on `NominatimGate`'s one-per-1.1-second door. Street addresses are
filtered out — a leading digit, or a second component that is not a US state code, is not
a city. Coordinates come from `MKLocalSearch.Response.boundingRegion.center`;
`mapItems.first?.placemark` says the same thing but is deprecated from iOS 26 and would
need an availability branch on the iOS 17 target.

### Files and symbols changed
- **New** `Waypost/Services/CitySearch.swift` — `CitySearch`, `CitySearch.Match`,
  `update(_:)`, `resolve(_:)`.
- `Waypost/State/AppState.swift` — new `TripOrigin` (name/lat/lon); `SavedTrip` gains
  `originName`/`originLat`/`originLon` and `resolvedOrigin(_:)`; `TripBuilder.pickedOrigin`
  and `resolvedOrigin`; `compose()` and `reviewRows` read the resolved origin.
- `Waypost/Services/TripRouting.swift` — `route(_:parks:origin:)` takes `TripOrigin?`
  rather than `CuratedCity?`.
- `Waypost/Features/Trips/NewTripSheet.swift` — `originField`, `originRow(…)`.
- `TripDetailScreen.swift`, `TripsScreen.swift` — three call sites read
  `trip.resolvedOrigin(app.library)`.

### Persistence
The three new `SavedTrip` fields are optional with `nil` defaults, so a snapshot written
before this change still decodes, and `resolvedOrigin` falls back to the `origin` code for
those trips. No migration and no silent reset — the failure mode Pain point 52 warns about.

### Before / after
| | Before | After |
|---|---|---|
| Origin choices | 6 cities from `curated.json` | any US city, plus the 6 as shortcuts |
| Planning from Dallas | impossible | `Dallas → Rocky Mountain`, 842 mi |
| Drive home | — | `Rocky Mountain → Dallas`, 859 mi via TX-354, Loop-335 |

### Accessibility
Rows are ≥44pt and carry `.isSelected` when chosen; the clear control has a label. Text
sizes follow the existing tokens, so the Dynamic Type work in Journey 11 still applies.

### Verified
iPhone 17 Pro simulator with the device location pinned to **Denver** throughout. Typed
"da" → `Dallas TX`, `Dayton OH`; picked Dallas; review read "Dallas, TX"; composed; both
routed legs and the routing note name Dallas, and Denver appears nowhere on the screen.

### Remaining limitations
- Matches need a network; there is no offline city list and no explicit error state when
  the completer fails, only an empty list under a "keep typing" line.
- The six shipped cities keep their airport codes; a searched city has none.
- Pain point 22 (hard-coded date strings) is still untouched.
- No recent-origins list and no saved home (the rest of Pain point 23's suggestion).

## Phase 3 — A button answers a tap anywhere on it (Pain points 18, 9)

Partially advances Pain point 6 and Pain point 7.

### User pain removed
"None of the buttons work on the first tap." They did work — but only where the label's
glyphs actually were. Every button in the app is a rounded surface much larger than its
text, and the rest of that surface was dead, so a tap landed on nothing and the second or
third attempt happened to hit a letter. Back had a separate fault that emptied the
navigation stack underneath it.

### Root causes
1. **`LiquidGlass` gave interactive glass no hit area on iOS 26.** The `onPhoto` and
   pre-iOS-26 branches call `.background(…, in: shape)`, which makes the shape hit-testable
   as a side effect. The iOS 26 branch calls `.glassEffect(…, in: shape)`, which does not.
   Every control in the app wears `glassControl` → `liquidGlass(interactive: true)`, so
   from iOS 26 every button was tappable only on its own text. This is the main fault.
2. **`DividedRow` had no `contentShape`.** `frame` and `padding` are layout, not
   hit-testing, so list rows answered only on their glyphs — the padding, the gap before
   the trailing chevron and the whole `Spacer` were dead.
3. **`SelectedControl`'s inactive branch had no background.** The active branch gets one
   from `glassControl`; the unselected one had nothing — and unselected is the only kind
   anyone taps.
4. **Sheets needed a second tap.** `app.sheet`, `app.builder` and `app.tab` were read only
   inside hand-built `Binding` `get` closures, which run after the body has finished and so
   register no Observation dependency. Setting one changed the value and nothing redrew;
   the sheet appeared later, when some other observed property re-evaluated the shell.
5. **`go()` emptied the navigation stack.** `TabView` writes its selection back through the
   binding at moments that are not user taps, each carrying the current tab, which took the
   "re-tap returns to root" branch and wiped a stack the user was standing in, mid
   view-update.
6. **A 426 KB decode on the main thread.** `state-parks.json` was decoded lazily on first
   access, from `AppState.park(_:)` during rendering and from the Discover list's `body` —
   between a finger going down and coming up, which cancels the gesture.

### Files and symbols changed
- `Waypost/Design/Glass.swift` — new `ControlHitArea` modifier applied by `LiquidGlass`
  when `interactive`; `contentShape` on `DividedRow` and on `SelectedControl`'s inactive
  branch.
- `Waypost/App/WaypostApp.swift` — `currentTab`, `currentSheet`, `openBuilder` hoisted into
  `body`; the `selection` computed property became a local binding over the hoisted read.
- `Waypost/State/AppState.swift` — `go(_:)` no longer clears the path; `Datasets.stateParks`
  warmed on a detached task at init.
- `Waypost/Features/Park/ParkScreen.swift` — `isLoadingFacts` and a spinner beside fee and
  hours.

### The loading indicator
`ParkFacts` already had a `loading` state that no screen showed: a park opened with its
bundled fee and hours and silently swapped them when the park service answered. There is
now a small `ProgressView` next to that row while the request is in flight, labelled for
VoiceOver. The other slow paths already report themselves — offline packs show a
percentage, search shows its phase, composition its stages, and the origin field spins
while a picked city is resolved.

### Before / after
Every case below was tested by tapping **away from the label**, on the part of the control
that used to be dead.

| Control | Before | After |
|---|---|---|
| "Save this park", far left edge | nothing | Saved |
| "Plan a trip here", far right edge | nothing | sheet opens |
| Discover "State" segment, padding | nothing | switches, 470 parks |
| State park row, gap before chevron | nothing | opens |
| Any sheet | opened on the second tap | opens on the first |
| Back after a spurious selection write-back | did nothing | returns |

### Deliberate regression
Tapping the tab you are already on no longer returns that tab to its root. That behaviour
is what read the spurious write-backs as re-taps and wiped live stacks. It is a
convenience; Back working every time is not.

### Accessibility
Hit areas now match the visible control, so the ≥44pt targets the design already draws are
real rather than nominal — the substance of Pain point 18's touch-target half. Text sizes
and contrast in that pain point are untouched.

### Verified
iPhone 17 Pro simulator, iOS 26.4. Each row of the table above was tapped once, at a point
outside the label, and screenshotted.

### Remaining limitations
- `.contextMenu` still sits on the Discover and Saved card buttons, which can still absorb
  a first touch inside a scroll view; not reproduced during this pass, so not changed.
- `panelTransition` still uses `.id()`, which tears down a subtree and cancels any press
  inside it when the segment changes.
- The Discover state list still filters 470 rows in `body` on every keystroke; the decode
  no longer blocks, but the filtering is not cached.
- Pain point 7 (per-tab navigation restoration) is only partly served: paths survive now,
  but scroll position is not restored.

## Phase 3b — The brief reads against the park it is about (Pain point 12, 16)

### User pain removed
The "Near you" card wrote one line per park as a bullet list above the shortlist, and the
shortlist repeated the same parks in the same order below it. Both were ranked, so the
bullets did correspond — but nothing on screen said so, and reading "why this park" meant
counting bullets, counting rows, and trusting the two lists matched. With four parks the
bullet for Yellowstone sat five rows above Yellowstone.

### Change
The headline stays at the top of the card. Each per-park line now renders inside its own
row, under that park's measured fact line, so the reason and the numbers it is a reading
of are in the same place. A park the model wrote nothing usable about simply has no line
and the row still reads. The stagger animation moved with the lines.

`validate(_:)` already rewrote each note's `park` to the candidate's own `name` before
storing it, so the row-to-note match is an exact string comparison rather than the fuzzy
`localizedCaseInsensitiveContains` used when parsing the model's output.

### Files and symbols changed
- `Waypost/Features/Discover/NearbyCard.swift` — `briefBody(_:)` became `headline(_:)` and
  no longer renders notes; `shortlist` became `shortlist(_ brief:)` and renders the
  matching note under each row; rows gained `.accessibilityElement(children: .combine)` so
  VoiceOver reads park, figures and reason as one element; footnote reworded from "the
  figures above" to "the figures beside each park".

### Verified — and what was not
The card's layout, rows, fact lines and footnote were checked on the iPhone 17 Pro
simulator. **The per-park lines themselves were not seen rendered**: Apple Intelligence
does not run on this simulator, so `NearbyBriefing` fails with
`FoundationModels.LanguageModelSession.GenerationError error -1` and the card takes its
`.failed` branch, which has no notes by design. The `.ready` path needs a device with
Apple Intelligence enabled. The change to that path is small and type-checked, but it is
untested at runtime and should be looked at on hardware before it is trusted.

### Remaining limitations
- Rows are taller when a note is present, so a four-park shortlist takes more vertical
  space than before; not a problem at the current cap of four, worth revisiting if it grows.
- The note is not truncated, so an unusually long sentence from the model will make one row
  much taller than its neighbours.

## Phase 3c — The search bar, and honest NPS status (Pain points 18, 11, 21)

### Search bar
Same fault as the buttons, in the control where it bites hardest. Every search field is a
`TextField` with a glass pill drawn around it — and the pill is not part of the field, so
only the text was tappable. An *empty* search field is almost entirely empty, so almost
all of it did nothing.

`searchFieldSurface(focus:)` in `Glass.swift` gives the pill a `contentShape` and a
`simultaneousGesture` that focuses the field. Simultaneous rather than `onTapGesture` so a
tap landing on the text still reaches the field and puts the caret where it was aimed.
Applied to all four fields: Discover, Quick Search, the trip builder's park search, and the
origin field.

### NPS status
A park whose bundled record carries nothing and whose NPS record never arrived read
`Not published · Not published`. That is a claim — it says the park publishes no fees and
no hours — when what actually happened is that the app failed to ask. Badlands, a national
park, read exactly that.

`ParkScreen.factsRow` now switches on `ParkFacts.State`:
- `.loading` → a spinner and "Pulling NPS data…"
- `.failed` → "Unable to pull NPS data — fees and hours are not available for this park
  right now."
- `.notCovered` **and** the designation contains "National" → the same unavailable line,
  because NPS answering "no such park" about a National anything means this app could not
  work out its code, not that the unit is absent from the register.
- otherwise → the fee and hours as before. A state park not being covered by NPS is simply
  true and says nothing here.

### Files and symbols changed
- `Waypost/Design/Glass.swift` — `searchFieldSurface(radius:focus:)`.
- `DiscoverScreen.swift`, `QuickSearchSheet.swift`, `NewTripSheet.swift` — applied; the
  builder gained `parkFieldFocused` and `originFocused`.
- `Waypost/Features/Park/ParkScreen.swift` — `isLoadingFacts` replaced by `factsRow` and
  `factsUnavailable`.

### Verified
iPhone 17 Pro simulator. The Discover field focused from a tap at the far right of the
pill, well clear of the placeholder. Badlands then showed "Unable to pull NPS data" in
place of "Not published · Not published".

### Remaining limitations
- **This labels the fault; it does not fix it.** Badlands still has no NPS data. The cause
  is Phase 4's: `isNPSCode` requires `^[a-z]{4}$` and every bundled park is an `np-…` slug,
  so no park matches directly and the name search behind it is doing all the work. The
  screen is now honest about failing rather than silently wrong, which is the smaller half
  of the problem.
- "Unable to pull NPS data" does not distinguish no proxy configured from a proxy that
  refused from a park that could not be matched. `ParkFacts.failed` carries the reason and
  it is still not shown anywhere.
- There is no Retry on that line.

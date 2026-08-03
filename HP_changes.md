# HP Changes — Dynamic, Production-Ready Waypost iOS

## Purpose
This document is the implementation contract for the AI agent improving the Waypost/ParkHop iOS app. Execute the work in dependency order, preserve the product's rule that a refusal is not the same as an empty result, and verify every completed phase. Do not mark an item complete because UI exists; complete means the underlying behavior, failure handling, persistence, accessibility, privacy, and tests work.

## Priority
- **P0:** release/trust blocker; complete first.
- **P1:** core product correctness and architecture.
- **P2:** accessibility, resilience, performance, and product quality.
- **P3:** optional polish after correctness.

## Non-negotiable dynamic-data contract
1. **No production feature may be wired to seed, demo, simulated, stale-by-default, or hard-coded operational data.** This includes current dates, trips, park availability, routes, weather, location, journal counts, downloads, alerts, recommendations, saved items, stamps, Live Activities, and notifications.
2. Bundled park catalogues and curated editorial copy may exist only as a **versioned offline/bootstrap source**. They must never be described as live. Every rendered datum must expose provenance and freshness internally.
3. Cached data is allowed only with `fetchedAt`, source, schema version, expiry/stale policy, and visible stale labeling when appropriate. Never silently display cached or bundled data as a current answer.
4. If a live source fails, show the cached answer with age and source when policy permits, or show a truthful unavailable/error state with Retry. Never invent, estimate, or substitute unrelated data.
5. All dates must derive from an injected clock and real user selections. All units and date/number strings must derive from locale-aware formatters. Do not persist localized display strings as domain values.
6. Search, routing, weather, availability, offline packs, notification status, photo status, and activity status must be backed by real services/platform APIs or explicitly shown as unavailable. Fake timers and Boolean-only integrations are forbidden.
7. Capture/demo states may exist only behind `#if DEBUG`, UI-test launch arguments, preview fixtures, or injected mock clients. They must be impossible to enter in release builds.
8. Preserve the existing source-truth invariant: **failed/refused**, **answered empty**, **live answer**, **cached answer**, and **bundled fallback** are distinct states.

A recommended shared representation is:

```swift
struct Sourced<Value: Sendable>: Sendable {
    let value: Value
    let source: DataSource
    let fetchedAt: Date
    let expiresAt: Date?
    let quality: DataQuality // live, cached, bundled
}

enum LoadState<Value> {
    case idle
    case loading(previous: Value?)
    case loaded(Value)
    case empty(source: DataSource, fetchedAt: Date)
    case failed(UserFacingError, cached: Value?)
}
```
## Definition of done for every change
- Production behavior uses real user input, platform state, live service output, or an explicitly labeled cache/offline source.
- Loading, success, answered-empty, partial, stale, offline, denied, cancelled, and failed states are handled.
- Requests are cancellable, bounded by deadlines, and do not update superseded screens.
- User-facing controls are accessible, localized, and at least 44×44 points.
- State survives relaunch when appropriate and has a versioned migration path.
- Privacy copy matches actual data collection and transmission.
- Unit/integration tests cover the behavior and failure modes; UI tests cover the major flow.
- The app builds without warnings under the configured Swift mode and is ready for stricter Swift 6 checking.

# Major product flows

## Flow 1 — Launch, consent, location, and Today recommendation
**Current references:**
- `Waypost/App/WaypostApp.swift` — app entry, `RootShell`, environment setup.
- `Waypost/App/CaptureHooks.swift` — capture/test launch states; restrict to debug/testing.
- `Waypost/State/AppState.swift` — hard-coded initial day, saved items, stamps, packs, journal count, notification flags, and current tab.
- `Waypost/Services/LocationService.swift` — Core Location request, timeout, and IP fallback.
- `Waypost/Services/Recommender.swift` — recommendation selection.
- `Waypost/Services/NearbyBriefing.swift` — nearby summary.
- `Waypost/Features/Today/TodayScreen.swift` and `QuickSearchSheet.swift` — presentation and capture entry.

**Required target flow:**
1. Launch with empty/restored user state, never production seed state.
2. Explain location use before the system prompt and offer `Use Current Location`, `Choose a City`, and `Not Now`.
3. When authorized, obtain one safely shared Core Location request with a real timeout.
4. When denied, do not call IP geolocation without separate informed consent. Default to manual city selection.
5. Resolve nearby parks and weather through injected services. Attach source and freshness to every result.
6. Render Today from current clock/date, approved location/manual origin, live or policy-valid cached data, and actual visit/saved history.
7. If sources partially fail, keep successful sections and identify unavailable sources. Provide Retry and origin change.
8. Persist consent choice and manual origin without persisting precise device coordinates unless strictly required and disclosed.

**P0 fixes:**
- Replace the single `pending: CheckedContinuation` in `LocationService` with an actor/single-flight request that safely supports concurrent callers, cancellation, authorization changes, timeout, and exactly-once continuation completion.
- Remove automatic `ipapi.co` / `ipwho.is` calls after denial; place them behind explicit consent or remove them.
- Replace inaccurate `NSLocationWhenInUseUsageDescription` in `Waypost/Info.plist` with copy that accurately describes processing and network transmission.
- Remove production defaults such as `day = 5`, pre-completed items, sample saved parks/stamps, ready packs, and journal counts from `AppState`. Move fixtures to debug-only factories.

**Acceptance:** denied location never triggers third-party geolocation; two concurrent callers both finish; timeout finishes; Today changes with date/location/data; no sample history appears for a new release user.

## Flow 2 — Discover and search
**Current references:**
- `Waypost/Features/Discover/DiscoverScreen.swift`
- `Waypost/Features/Discover/NearbyCard.swift`
- `Waypost/Services/ParkDirectory.swift`
- `Waypost/Services/SearchSuggestions.swift`
- `Waypost/Services/Nominatim.swift`
- `Waypost/Services/NPSService.swift`
- `Waypost/Models/NationalParks.swift`
- `Waypost/Resources/national-parks.json` and `state-parks.json`

**Required target flow:**
1. Debounce user input and cancel superseded work.
2. Publish on-device catalogue matches immediately as `Bundled catalogue`, then merge live Apple Maps/NPS/OpenStreetMap answers as they arrive.
3. Keep source status independently: pending, answered-empty, answered-with-data, failed, and timed out.
4. Deduplicate with stable park identity, not only normalized names. Preserve aliases and authoritative IDs.
5. Persist a bounded TTL/LRU cache with source, fetched time, query normalization, and schema version.
6. Show result provenance and whether more sources are still loading.
7. Provide a bounded overall deadline and Retry; never let one Overpass query block the experience for minutes.
8. Search results selected here must be usable in Park and New Trip without converting them to a curated placeholder.

**Specific fixes:**
- In `ParkDirectory.nominatim`, insert `.openStreetMap` into `answered` only after a valid response, including a valid empty response; do not mark a thrown request as answered.
- In `ParkDirectory.overpassPlaces`, replace three sequential 90-second attempts with a bounded overall deadline, sensible per-host budgets, cancellation, and first-success behavior. Preserve the difference between empty and failed responses.
- Replace the cache that clears all entries after 24 terms with bounded LRU/TTL eviction.
- Make Nominatim access respect usage policy, identification, rate limits, and request serialization.
- Ensure cancelled generations cannot publish late results.

**Acceptance:** an unavailable source cannot make an empty result look successful; a search has a finite deadline; cached results show age; a discovered non-curated park opens and can be added to a trip with stable identity.

## Flow 3 — Park details
**Current references:**
- `Waypost/Features/Park/ParkScreen.swift`
- `Waypost/Features/Sheets/DetailSheet.swift`
- `Waypost/Services/WeatherService.swift` and `AppleWeather.swift`
- `Waypost/Services/PlacesService.swift`
- `Waypost/Services/ParkPhotos.swift` and `PhotoStore.swift`
- `Waypost/Models/Curated.swift` and `LivePark.swift`

**Required target flow:**
1. Open a park from Today, Discover, Saved, or Trip using one stable park ID and repository model.
2. Render catalogue/editorial fields as curated/versioned and live fields with source/freshness.
3. Each segment owns an explicit state and Retry: Overview, Weather, Stay, Plan, Nearby.
4. Weather uses current user units and distinguishes forecast, historical normals/model, cached forecast, and unavailable.
5. Places load progressively based on visible sections rather than six unconditional requests.
6. Save state persists immediately and consistently from every entry point.
7. Offline CTA reflects actual pack state and actual stored resources.

**Specific fixes:**
- Replace `asked` and the throwaway `FailureLog()` in Park weather with an injected weather client and `LoadState`; expose Retry.
- Do not say `No forecast` when the request failed. Distinguish source refusal, answered-empty, stale cache, and no applicable forecast horizon.
- Wire `AppState.unitsMetric` (or its replacement settings store) to weather, wind, distance, and elevation formatting.
- Ensure remote photos are downsampled, cached with metadata/expiry, cancelled off-screen, and have meaningful accessibility treatment.
- Increase Save and Offline Pack controls from 40 points to at least 44 points.
- Adapt fixed hero/grid layouts for small displays and accessibility Dynamic Type.

**Acceptance:** every Park field has truthful provenance; failed weather can retry; units switch immediately; non-curated parks do not fall back to an unrelated curated record; offline status matches files actually available.

## Flow 4 — New trip creation and composition
**Current references:**
- `Waypost/Features/Trips/NewTripSheet.swift`
- `Waypost/State/AppState.swift` — `TripBuilder`, `composeSteps`, `compose()`.
- `Waypost/Services/TripRouting.swift`
- `Waypost/Services/TravelServices.swift`
- `Waypost/Services/WeatherService.swift`
- `Waypost/Resources/cities.json`, `airports.json`, and `legs.json`

**Required target flow:**
1. Select any park from the shared dynamic directory, not only `library.orderedParks`.
2. Store stable park identifiers and snapshots needed for offline display; rehydrate through the repository.
3. Use a real `Date`/date range picker and validated origin selected from current location or search.
4. Persist travel mode and vehicle choice through the settings/domain model.
5. Compose asynchronously through a `TripComposer` that performs only the operations the UI claims.
6. Route each leg with a real routing client; preserve source, response time, distance, duration, and cache state.
7. If optimization is enabled, compute order from route costs and explain that the order changed. Otherwise preserve user order.
8. Fetch relevant forecast or climate data for real dates; label climate normals/modelled values correctly.
9. Query availability only where a source legally and technically supports it. Never claim it was checked when unavailable.
10. Size a pack only from the manifest of resources that will actually be downloaded.
11. Show cancellable per-stage progress based on completed work, not timers. Return a partial/error result when some stages fail.

**Specific fixes:**
- Replace hard-coded `candidateStarts`, `startLabel`, and display-string dates with `Date` and locale-aware formatting.
- Replace `TripBuilder.results` over only curated parks with the shared park repository/directory.
- Replace synchronous `compose()` and decorative `composeSteps` with real async operations and typed stage results.
- Do not use `hashValue` for persistent trip IDs; use UUID or a stable explicit identifier.
- Remove hard-coded seed trips from production initialization.

**Acceptance:** changing parks/date/origin changes route and weather requests; cancelling composition stops work; no stage reports success without evidence; reopening a trip rehydrates all park identities; no itinerary is created from static `legs.json` unless that file is explicitly a labeled offline fallback.

## Flow 5 — Trips list and trip detail
**Current references:**
- `Waypost/Features/Trips/TripsScreen.swift`
- `Waypost/Features/Trips/TripDetailScreen.swift`
- `Waypost/State/TripPresentation.swift`
- `Waypost/State/TripStore.swift` — legacy parallel architecture and live caches.
- `Waypost/Services/TripRouting.swift` and `TravelServices.swift`

**Required target flow:**
1. Trips list is populated only by persisted user-created/imported trips, not seeded trips.
2. Trip Detail derives route, day plan, stays, and park information from the saved trip plus refreshable sourced records.
3. Refresh is explicit, cancellable, and incremental. Preserve valid cached sections if one provider fails.
4. Dynamic day plans are generated from selected parks, duration, hours, travel constraints, and real available activities; do not render a fixed ten-day curated itinerary for arbitrary trips.
5. Delete supports confirmation and correctly removes associated private/offline data where appropriate.
6. Empty state guides users to create a trip.

**Architecture decision:** migrate reusable logic from `TripStore` into focused repositories/services and then remove `TripStore`. Do not leave `AppState` and `TripStore` as two competing sources of truth or two persistence formats.

**Acceptance:** no trip appears for a new user; trip detail matches the created trip; route/day/stay sections report individual freshness/errors; deleting/relaunching is consistent.

## Flow 6 — Saved parks and passport
**Current references:**
- `Waypost/Features/Saved/SavedScreen.swift`
- `Waypost/State/AppState.swift` — `saved`, `stamps`, and `savedShowsPassport`.

**Required target flow:**
- Saved parks come only from user actions/imported user data.
- Passport stamps come from a real check-in/visit rule or explicit user action with documented semantics; never ship pre-awarded stamps.
- Handle removed or unavailable park records using persisted identity snapshots and repository rehydration.
- Saved/offline status is shared consistently across all screens.
- Provide empty, loading, stale, and failed states where repository lookups are needed.

## Flow 7 — Profile, settings, privacy, and data controls
**Current references:**
- `Waypost/Features/Profile/ProfileScreen.swift`
- `Waypost/State/AppState.swift` — notification flags, vehicle, units, pack storage.
- `Waypost/Services/Network.swift` — `ProxyConfig` and reachability.
- `Waypost/Info.plist` and `Waypost/Waypost.entitlements`.

**Required target flow:**
- Settings reflect actual system/platform status, not local Booleans.
- Unit choice updates all measurements.
- Notification rows show authorization state and manage real categories/schedules.
- Storage shows actual bytes on disk and offers per-pack/all-cache deletion.
- Privacy section explains providers, location behavior, cache retention, and deletion.
- `Delete Local Data` removes trips, saved parks, stamps, preferences where requested, cached photos, offline packs, and migrations safely.
- Proxy state is validated using HTTPS URL parsing plus a real health request; a string beginning with `http` is not `Connected`.

## Flow 8 — Offline packs
**Current references:**
- `AppState.startPack`, `packs`, `packProgress`, and `packStorageMB`.
- Park offline CTA in `ParkScreen.actions`.
- `PhotoStore`, bundled datasets, weather/routes/place caches.

**Required target flow:**
1. Generate a versioned manifest containing park identity, catalogue/editorial records, required images/maps or supported alternatives, planned-trip records, and cacheable source responses permitted for offline storage.
2. Calculate expected bytes from the manifest or server metadata.
3. Download with a real URLSession background/foreground strategy, cancellation, retry, integrity verification, and atomic commit.
4. Persist manifest, content hashes, source timestamps, expiry, and schema version.
5. Read from the pack when offline and label source/freshness.
6. Detect partial/corrupt/outdated packs and repair or remove them.
7. Use actual file sizes for storage reporting.
8. Respect Low Data Mode, network cost, low disk space, and app lifecycle.

Remove the simulated timer and the message `works with no signal` until this entire path is real.

## Flow 9 — Notifications, Live Activities, and journal photos
**Current references:**
- `AppState.toggleLiveActivity`, `addJournalPhoto`, and notification flags.
- Today and Profile controls that expose these states.
- `project.yml`, which currently defines only the app target.

**Required target flow:**
- Notifications: use `UNUserNotificationCenter`, request authorization in context, register categories, schedule/cancel real reminders, and reconcile settings with system authorization.
- Live Activities: use ActivityKit with real trip/day state; handle unsupported/denied/ended states. Add required target/configuration only if needed by the selected implementation.
- Journal: use `PhotosPicker` or camera flow, persist real asset/file references and metadata, support deletion, and handle permission/storage failures.
- If any integration is deferred, remove its actionable production UI or label it clearly as unavailable. Never increment a count or toggle a Boolean and call it integrated.

# Architecture and source ownership

## Replace the god object
Refactor `Waypost/State/AppState.swift` so it no longer owns every feature. A suitable target is:
- `AppRouter`: selected tab, one navigation path per tab, sheets, deep links.
- `SettingsStore`: units, vehicle, privacy choices, notification preferences.
- `ParkRepository`: bundled catalogue, live enrichment, stable identity, source-aware cache.
- `TripRepository`: versioned persistence and trip CRUD.
- `SavedRepository`: saved parks and visit/passport records.
- `TodayModel`, `DiscoverModel`, `ParkModel`, `TripBuilderModel`, `TripDetailModel`: feature-specific load state and orchestration.
- `OfflinePackManager`, `NotificationManager`, `LiveActivityManager`, `JournalStore`.
- `AppEnvironment`: protocol-backed clients, clock, persistence, logger, and connectivity.

Keep UI mutations on `@MainActor`; move decoding, ranking, deduplication, climate aggregation, file I/O, and cache operations to appropriate actors/nonisolated workers using `Sendable` values.

## Navigation
In `Waypost/App/WaypostApp.swift`, replace the shared `$app.stack` used by all five `NavigationStack`s with one path per tab. Switching tabs must preserve each tab's history. Keep system back gestures and deep-link routing. Add restoration tests.

## Dependency injection
Remove ad-hoc `FailureLog()` creation and avoid new concrete service instances inside views. Protocols should cover location, HTTP transport, weather, park search, routing, places, photos, persistence, clock, connectivity, notifications, activities, and pack storage. Production clients go in the app environment; deterministic mocks go only in tests/previews.

## Persistence
- Version all persisted records and write migrations from `waypost-app` and any retained `waypost-trip` data.
- Use `UserDefaults` only for small preferences. Use SwiftData or actor-managed versioned files for trips, sourced caches, packs, and journal metadata.
- Replace `try?` decode/write paths with logged, recoverable errors and safe migration behavior.
- Apply file protection as appropriate and exclude disposable caches from backup.
- Persist domain values, not localized labels.

# Networking, caching, and security

## `Waypost/Services/Network.swift`
- Add endpoint-specific request policies, deadlines, retries with capped exponential backoff/jitter, `Retry-After`, MIME/status/payload validation, and cancellation.
- Keep failed, valid-empty, malformed, and cancelled outcomes distinct.
- Replace fragmented `FailureLog` usage with privacy-redacted structured errors and `Logger`/OSLog.
- Restrict `safeURL` to HTTPS for remote community-maintained links; show destination domain where trust is uncertain.
- Replace global forever-running `NWPathMonitor` with an injected lifecycle-managed connectivity client.

## Proxy security
- `ProxyConfig.isConnected` must not use `base.hasPrefix("http")`.
- Parse with `URLComponents`; require HTTPS and a valid host; optionally allowlist production hosts.
- Report unconfigured, validating, healthy, refused, and unreachable separately.
- Do not treat `Origin`/`X-Waypost-Client` as authentication. API keys remain server-side and backend abuse controls must be documented.

## Performance budgets
- Do not issue ten climate archive requests per park without shared caching and concurrency limits. Batch date windows or provide server aggregation where possible.
- Coalesce duplicate requests and use single-flight tasks.
- Limit simultaneous MapKit/place searches and load visible content first.
- Downsample images before display and cap disk/memory caches.
- Add OSLog signposts for launch, search source latency, location, park load, routing, composition, and offline pack work.

# UI, accessibility, and localization

## Design files
- `Waypost/Design/Tokens.swift`: fix `scaled()` so `displayBold()` preserves `CormorantGaramond-Bold`; avoid hard-coded Semibold.
- `Waypost/Design/Glass.swift`: support Reduce Transparency and Increase Contrast.
- `Waypost/Design/Motion.swift`: support Reduce Motion and avoid essential information conveyed only through animation.
- `Waypost/Design/PageTint.swift`: use semantic colors that support both appearance modes and contrast settings.

## Appearance and layout
- Remove forced `.preferredColorScheme(.light)` in `WaypostApp.swift` after adding complete semantic dark tokens, or document and validate an explicit light-only product decision.
- Make every target at least 44×44 points.
- Replace tiny low-opacity metadata where contrast is insufficient.
- At accessibility Dynamic Type sizes, convert compact two-column grids to one column and allow meaningful values to wrap instead of shrinking to 70%.
- Validate small iPhones, Pro Max, landscape as an accessibility accommodation, and iPad if scope expands.

## Accessibility
For custom glass controls, tab images, segment rails, maps, weather grids, source badges, and status dots:
- Add labels, values, hints, selected traits, headings, and logical sort priority.
- Hide decorative images from VoiceOver and provide useful labels for informative photos.
- Never use color alone for state.
- Ensure actions are reachable by VoiceOver, Voice Control, Switch Control, and keyboard where applicable.
- Announce important async completion/failure; do not rely only on transient toasts.

## Localization and units
- Add String Catalogs (`.xcstrings`) for all user-facing text and accessibility strings.
- Use plural rules and pseudolocalization; verify right-to-left layout.
- Centralize `MeasurementFormatter`, date/time, number, and currency formatting.
- Wire metric preference through weather requests/presentation, wind, distance, elevation, and route summaries.
- Replace hard-coded English date strings throughout `AppState`, Trip screens, and sheets.

# Privacy and release configuration

## Required files/configuration
- Add `Waypost/PrivacyInfo.xcprivacy` with accurate required-reason API and collected-data declarations, then validate against current App Store requirements.
- Add `Waypost/Assets.xcassets` with AppIcon and semantic color assets.
- Correct product naming: `Waypost` vs `ParkHop` in `Info.plist`, target settings, UI, privacy copy, and documentation.
- Remove obsolete `armv7` from `UIRequiredDeviceCapabilities` for an iOS 17 app.
- Decide and document iPhone-only/portrait-only scope; support additional orientations where accessibility/product requirements demand it.
- Automate `CURRENT_PROJECT_VERSION`; do not leave every archive at build `1`.
- Keep `project.yml` canonical and verify generated project drift in CI.

# Tests and CI

## Test targets
Add unit and UI test targets to `project.yml`. At minimum include:
- `LocationServiceTests`: timeout, denial, authorization change, cancellation, simultaneous callers, no delegate callback.
- `ParkDirectoryTests`: per-source state, Nominatim failure, valid empty response, deduplication, stale generation, overall deadline, cache expiry/LRU.
- `PersistenceMigrationTests`: empty install, current snapshot, legacy `waypost-app`, retained `waypost-trip`, corrupt payload, interrupted write.
- `TripComposerTests`: real stage invocation, order preservation/optimization, cancellation, partial failure, no false success, stable IDs.
- `FormattingTests`: metric/imperial, locale, calendar, time zone, pluralization.
- `ProxyConfigTests`: HTTP rejection, malformed URL, host validation, health states.
- `OfflinePackTests`: manifest, byte count, cancel/resume, checksum failure, stale/corrupt pack, offline read.
- Feature-model tests for idle/loading/partial/empty/stale/failed transitions.
- Accessibility/UI tests for all major flows, empty/error/offline states, largest Dynamic Type, dark mode, and denied permissions.

Network tests must use URLProtocol/fake protocol clients and deterministic clocks. Do not make normal unit tests depend on public APIs. Add a separate opt-in contract test suite for provider schemas and policies.

## CI gates
1. Generate project with XcodeGen and fail on unexpected generated drift.
2. Validate bundled JSON schemas and uniqueness/stable IDs.
3. Build all targets with warnings treated as errors where practical.
4. Run unit tests and a focused UI smoke suite.
5. Run strict concurrency diagnostics and resolve current warnings in:
   - `Waypost/Services/SearchSuggestions.swift` — mutable `URLRequest` captured by concurrent closure.
   - `Waypost/Services/ParkDirectory.swift` — same captured request issue.
   - `Waypost/Services/PhotoStore.swift` — actor-isolated `ParkDirectory.userAgent` access and unnecessary `await`.
6. Validate String Catalog completeness and privacy manifest.
7. Run archive/export validation and verify AppIcon/build number.
8. Run `sync-version.sh --check` or the repository's canonical version check.

# Documentation and repository hygiene
- Update `README.md`; it currently describes the old Plan/Trip architecture and stale feature/resource status.
- Update `docs/SCREENS.md` as behavior changes; keep screenshot cases for loading, empty, partial, failed, stale, offline, denied, and accessibility modes.
- Update `CHANGELOG.md` by user-visible release, not by internal refactor detail.
- Ensure `build/`, `.DS_Store`, `xcuserdata/`, `Library/Preferences/`, and other machine-local artifacts are ignored and untracked.
- Keep `Waypost/App/CaptureHooks.swift` debug-only and ensure launch arguments cannot mutate release user state.

# Execution order

## Phase 0 — Baseline and truth audit
- Generate/build the project and record current warnings.
- Inventory every hard-coded production default and every UI claim of `live`, `downloaded`, `available`, `connected`, or `checked`.
- Add tests that reproduce the P0 location, search semantics, persistence, and false-feature behavior before refactoring.

## Phase 1 — P0 trust and release safety
- Fix location concurrency/timeout and consent behavior.
- Correct privacy strings and add the privacy manifest.
- Remove or disable false offline, Live Activity, notification, journal, and composition claims.
- Add AppIcon/assets and correct release configuration.

## Phase 2 — State and architecture
- Introduce environment/protocol clients, router, repositories, and feature models.
- Give each tab its own path.
- Migrate persistence and remove the parallel `TripStore` architecture after its useful logic is moved.
- Remove production seed data.

## Phase 3 — Dynamic core flows
- Complete dynamic Today, Discover, Park, New Trip, Trip Detail, Saved, and Profile flows.
- Implement source/freshness state and bounded caches.
- Implement real trip composition, or keep unavailable stages visibly disabled until implemented.

## Phase 4 — Real platform features
- Implement offline packs end-to-end.
- Implement notifications, ActivityKit, and real journal photos, each with system-state reconciliation.

## Phase 5 — Accessibility and internationalization
- Complete dark/semantic appearance, Dynamic Type reflow, contrast, VoiceOver, motion/transparency accommodations, String Catalogs, and unit formatting.

## Phase 6 — Hardening and release
- Resolve all build/concurrency warnings.
- Profile launch, search, photos, climate work, maps, and pack downloads.
- Complete CI, contract tests, archive validation, data deletion checks, privacy review, and documentation.

# Final acceptance checklist
- [ ] A clean install contains no sample trips, saves, stamps, completed tasks, packs, or journal entries.
- [ ] No production operation uses fake progress, fake completion, hard-coded current dates, or decorative Boolean-only integrations.
- [ ] Bundled/curated data is clearly labeled and versioned; it is never presented as live.
- [ ] Cached data contains source/time/expiry and is visibly stale when applicable.
- [ ] Every network-backed feature distinguishes failed, valid-empty, partial, cached, bundled, and live states.
- [ ] Location denial causes no hidden IP geolocation request; timeout/cancellation/concurrent callers are safe.
- [ ] Every tab preserves its own navigation history.
- [ ] Any discovered park can be saved, opened, and added to a trip with stable identity.
- [ ] Trip date/origin/parks dynamically determine real routing, weather, availability status, and pack manifest.
- [ ] Offline status corresponds to verified files actually readable with network disabled.
- [ ] Notification, Live Activity, and photo UI reflects actual platform state.
- [ ] Metric/imperial and locale changes update the entire app.
- [ ] Key screens pass largest Dynamic Type, VoiceOver, contrast, Reduce Motion, and Reduce Transparency checks.
- [ ] Persisted data migrates without silent reset and corrupt data has a recovery path.
- [ ] Proxy and external links require secure validated URLs.
- [ ] AppIcon, privacy manifest, accurate permission copy, automated build number, and archive validation are complete.
- [ ] Unit/UI tests and CI pass; no compiler or strict-concurrency warnings remain.

## Agent reporting requirements
For each phase, report:
1. Files and symbols changed.
2. Which static/simulated dependency was removed and what dynamic source replaced it.
3. Data provenance, cache, and failure behavior.
4. Privacy/accessibility impact.
5. Tests and exact validation commands run.
6. Remaining blocked provider/platform work; do not represent blocked work as complete.

Do not attempt all phases as one unreviewable rewrite. Keep each phase buildable and migratable, but do not stop at UI scaffolding or connect screens back to stale/static fixtures. Correctness and truthful behavior take priority over visual completion.

---

# Status — pass 1
_claude — 3 August 2026, against v2.14.x. One line per item: what was done, or why not yet._

This document is six phases of work and says itself not to attempt it as one
unreviewable rewrite. Pass 1 took Phase 0/1 — the trust and release blockers — plus the
two design bugs it names. Everything else is listed below as untouched, honestly.

## Done in this pass

| Item | Status | Note |
|---|---|---|
| Flow 1 · remove production seed state from `AppState` | **Done** | `day = 5`, `doneItems = ["a0"]`, `journalCount = 2`, ready packs, sample `saved`, five pre-awarded `stamps` and the seed trip are all gone; a clean install now has no history it did not earn. — claude |
| Flow 1 · no IP geolocation after denial | **Done** | `currentFix()` no longer falls through to `ipapi.co`/`ipwho.is` when Core Location is refused. The path survives behind `allowsNetworkFallback:` for a caller that has asked separately; nothing calls it with `true` today. — claude |
| Flow 1 · accurate `NSLocationWhenInUseUsageDescription` | **Done** | Was "never stored or sent anywhere", which was false — coordinates go to Apple Maps, OSRM and Open-Meteo. Now says so. — claude |
| Flow 7 · `ProxyConfig.isConnected` must not be `hasPrefix("http")` | **Done** | Parses with `URLComponents` and requires HTTPS plus a host. The old check accepted `httpfoo` and, worse, plaintext `http://`. — claude |
| Repo hygiene · `CaptureHooks` debug-only | **Done** | `applyLaunchArguments()` and `Capture.argument` are inside `#if DEBUG`; launch arguments cannot mutate release state. Release build verified. — claude |
| Release config · obsolete `armv7` | **Done** | `UIRequiredDeviceCapabilities` is `arm64`. — claude |
| Design · `scaled()` drops `CormorantGaramond-Bold` | **Done** | It rebuilt every font from a hard-coded SemiBold name, so `displayBold` passed its own availability check and then drew SemiBold — including the masthead the Bold cut was made for. The face is carried through now, and the fallback is a serif system font rather than the wrong weight. — claude |
| Trips kicker asserted a trip existed | **Done** | With the seed gone, "One trip on the books, one in the field" sat over "No trips yet". It counts now. — claude |
| Screen titles | **Done** | Trips, Discover, Saved, Profile and Find a park are `displayBold(44)`, matching the ParkHop masthead — the user's request, and it exposed the bug above. — claude |

## Not done — and not started

Everything below is untouched. Listing it so the gap is visible rather than implied.

| Area | Status |
|---|---|
| Flow 1 · consent screen before the system prompt; manual city origin | **Not started** — claude |
| Flow 1 · `LocationService` single-flight actor, concurrent callers, exactly-once continuation | **Not started** — the continuation is still a single stored optional. — claude |
| Flow 2 · per-source state, bounded deadlines, LRU/TTL cache, stable identity dedup | **Partly, by accident** — sources already publish independently and Overpass has host fallback, but the 90-second budgets, the clear-at-24 cache and name-based dedup are as described. — claude |
| Flow 3 · `LoadState` + Retry per park segment; units wired to weather; 44pt targets | **Not started** — claude |
| Flow 4 · real `Date` picker, `TripComposer`, UUID trip IDs, no `hashValue` | **Not started** — claude |
| Flow 5 · retire `TripStore`; dynamic day plans | **Not started** — `TripStore` and `TripPresentation` are still 1,175 unused lines. — claude |
| Flow 6 · saved/passport semantics | **Partly** — pre-awarded stamps are gone; the check-in rule that should award them does not exist. — claude |
| Flow 7 · real notification/system state, storage bytes, Delete Local Data | **Not started** — the notification toggles are still local Booleans. — claude |
| Flow 8 · offline packs end-to-end | **Not started** — the timer and the "works with no signal" copy are still there. — claude |
| Flow 9 · UNUserNotificationCenter, ActivityKit, PhotosPicker journal | **Not started** — claude |
| Architecture · split `AppState`, per-tab navigation paths, DI, versioned persistence | **Not started** — the single shared `stack` across five `NavigationStack`s is unchanged. — claude |
| Networking · retry/backoff, structured errors, injected connectivity | **Not started** — claude |
| Accessibility · Reduce Transparency/Motion, Dynamic Type reflow, VoiceOver, contrast | **Not started** — claude |
| Localization · String Catalogs, `MeasurementFormatter`, RTL | **Not started** — claude |
| Release · `PrivacyInfo.xcprivacy`, `Assets.xcassets`/AppIcon, Waypost vs ParkHop naming, build numbering | **Not started** — claude |
| Tests · every suite named in the document; CI gates | **Not started** — there is no test target. — claude |

## Honest note on scale

Pass 1 is roughly the P0 row of the execution order. The remaining phases are a
substantial rewrite — repositories, dependency injection, per-tab routing, a test target
that does not yet exist, and four platform integrations that are currently claims rather
than features. They want doing in reviewable slices, in the order this document already
sets out, not in one sweep. — claude

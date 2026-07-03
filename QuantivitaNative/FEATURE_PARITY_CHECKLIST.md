# Quantivita Flutter to Native iOS Feature Parity

This is the authoritative migration checklist. A feature is user-ready only after all applicable gates are met.

Status: `[x]` native implementation present, `[~]` partial, `[ ]` missing.
Gates: `T` automated tests, `L` live backend/MCP verification, `D` physical iPhone verification.

## 1. Authentication, privacy and onboarding

- [x] Sign in with Apple and persistent private account identity. `T`
- [x] Continue offline and restore cached account/dashboard. `T`
- [x] Apple Health permission onboarding.
- [x] Personal health profile reads HealthKit values and supports native editing/sync.
- [x] Account management, sign-out/reset and deletion UX. `T`

## 2. Native shell and appearance

- [x] Native tabs: Today, Trends, Log and You.
- [x] System/light/dark selection with true iOS system following.
- [x] Persistent modern accent-color presets and icon-led settings UI.
- [~] Modern material panels exist; full Flutter liquid-glass visual parity remains.
- [ ] Accessibility, Dynamic Type, localization and reduced-motion audit.

## 3. Recovery dashboard

- [x] Recovery/readiness, strain and sleep scoring engine. `T`
- [x] Missing-sleep neutral fallback prevents automatic bad recovery. `T`
- [x] Core daily score cards and explanations.
- [x] Configurable native dashboard composer and persisted widget selection.
- [~] Body Battery breakdown exists; complete Flutter factor/detail presentation remains.
- [ ] News/insight presentation and complete empty/loading states.

## 4. Apple Health and trends

- [x] HealthKit authorization and core health metrics. `T`
- [x] Workout history and activity detail.
- [~] Biomarker overview exists; individual metric trends/coaching pages remain incomplete.
- [~] Sleep summary exists and reports a single night (most-recent session, no two-night double-count); stages, quality factors and full detail page remain incomplete. `T`
- [~] Stress metrics exist; time filters, zones and graph parity remain incomplete.
- [ ] Health monitor ranges and personalized warning presentation.
- [ ] Nutrition, hydration and net-energy dashboard parity.

## 5. Progressa contextual workout data

- [x] Native Progressa OAuth callback and connection state. `T`
- [x] Refresh/sync uses cached data on server failure. `T`
- [x] Expired Progressa access tokens refresh server-side; unrecoverable sessions require reconnect without deleting cached links. `T`
- [x] Workout exercises, sets and detail data are decoded. `T`
- [x] Progressa data is visible only when explicitly linked to a HealthActivity. `T`
- [x] Unlinked Progressa workouts are never shown as standalone Quantivita activities. `T`
- [x] Link persistence and migration preserve existing linked data. `T`
- [x] Changes/deletions detach stale links correctly. `T`
- [x] UI test verifies there is no general Progressa workout list.
- [ ] Two-account live connection/sync/link verification. `L D`

## 6. Merge Lab and Strava

- [x] Select and preview multiple health activities.
- [x] Export merged workout back to Apple Health. `T`
- [x] Strava OAuth connection and `activity:write` validation. `T`
- [x] TCX generation, upload and processing polling. `T`
- [~] Native Merge Lab flow exists with a GPS route map preview; the merged workout is built with HKWorkoutBuilder (route/map attaches) and carries energy, the real heart-rate series, ambient weather temperature and the GPS route, with idle gaps paused so Workout Time is active time; complete Flutter wizard/review visuals remain.
- [ ] CSV/share-sheet export parity.
- [ ] Live Strava upload verification with production callback. `L D`

## 7. Sync, cache and MCP server

- [x] Protected local dashboard/workout cache.
- [x] Authenticated homeserver registration and snapshot sync.
- [x] MCP health summary and linked Progressa workout detail contracts exist. `T`
- [ ] Live MCP tool verification after final schema deployment. `L`
- [ ] Offline pending mutation/retry coordinator.
- [ ] Observability and crash reporting parity.

## 8. Release readiness

- [~] Unit and integration tests cover scoring, linking, OAuth and export contracts.
- [~] Critical Progressa-link UI invariant has UI tests; full user-journey suite remains.
- [ ] App icons, launch screen, privacy manifest and entitlements final audit.
- [ ] App Store metadata, screenshots and review notes.
- [ ] TestFlight smoke matrix and physical-device acceptance. `D`

## Current execution order

1. Finish native appearance and account/profile UX.
2. Complete dashboard composer and recovery/sleep/stress/biomarker detail pages.
3. Complete Merge Lab wizard, route preview and CSV/share export.
4. Live Progressa, Strava, homeserver and MCP verification.
5. Accessibility, UI automation and App Store release gates.

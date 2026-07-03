# Quantivita Native Full Migration Plan

## Release Strategy

`QuantivitaNative` is developed beside Flutter with the production bundle ID. Flutter remains the rollback build until every P0/P1 row below is complete and the physical-device gate passes. A successful compile is not parity.

## Execution Order

### Phase 0 - Contract freeze and inventory

- Freeze Flutter routes, persisted keys, HealthKit schema, score fixtures, server payloads and integration callbacks as executable fixtures.
- Record golden datasets for missing/short/overlapping sleep, mixed workout sources, routes and Progressa strength details.
- Status: inventory complete; executable fixtures pending.

### Phase 1 - Upgrade-safe identity and storage

- Import Flutter `accountId`, `syncToken` and Apple identity into Keychain exactly once without creating a second account.
- Migrate profile, dashboard preferences and cached summaries into versioned, account-isolated native storage.
- Preserve ownership of Progressa, Strava and MCP data across the upgrade.
- Status: Flutter account and sync-token import implemented; profile/preferences/cache migration and account-isolated cache remain P0.

### Phase 2 - HealthKit and scoring parity

- Port every read type, source/timezone rule, sleep de-duplication rule and missing-data semantic.
- Port baseline calibration, sleep score/need, recovery caps, strain, stress and body battery using shared golden Dart/Swift fixtures.
- Preserve HR samples, routes, elevation, weather, humidity, AQI, workout type and source metadata.
- Status: pending and P0; current native implementation is a subset.

### Phase 3 - Complete product surface

- Rebuild Today including configurable widgets, Body Battery, sleep, stress, nutrition/hydration and day navigation.
- Rebuild Trends and all biomarker, sleep and workout history/detail routes.
- Rebuild profile/personalization with validation and HealthKit/server synchronization.
- Status: pending and P0.

### Phase 4 - Workouts, Merge Lab and exports

- Add complete history paging/filtering, detail metadata and deterministic cross-source de-duplication.
- Merge with original activity type, HR/energy samples and copied GPS routes while retaining originals and preventing duplicate exports.
- Provide Apple Health export, CSV share, route-complete TCX share and direct Strava upload with terminal upload status.
- Status: selection and aggregate preview complete; fidelity, sharing and upload polling pending.

### Phase 5 - Integrations and offline resilience

- Complete Progressa paging, retry/backoff, stale timestamps and physical connect/sync/detail tests.
- Complete Strava OAuth, revoke, refresh, upload polling and Universal Links; keep secrets server-side.
- Preserve full homeserver/MCP payload parity and add account-isolated offline retry queues.
- Status: Progressa and Strava core implemented; hardening and physical gates pending.

### Phase 6 - Accessibility and release

- Add VoiceOver labels, accessibility identifiers, Dynamic Type, Reduce Motion and light/dark/system snapshots.
- Run upgrade-over-Flutter rehearsals, failure recovery, two-iOS-version device tests and TestFlight smoke tests.
- Retain Flutter as rollback until every release gate passes.
- Status: pending.

## Functional Parity

| Domain | Required native behavior | Status |
| --- | --- | --- |
| Auth | Apple Sign In, offline account, credential migration, auth errors, cold start | Partial |
| Permissions | Progressive HealthKit read/write consent and denied/partial states | Partial |
| Today | Recovery, body battery, sleep, metrics, stress, nutrition, configurable widgets, day workouts | Partial |
| Trends | HRV, RHR, respiration, SpO2, temperatures, stress filters, biomarker details/history | Partial |
| Workout log | 7/30/90/365 history, day navigation, Progressa sync, dedupe, cache and detail routes | Partial |
| Progressa | OAuth/deep link, status, refresh/disconnect, exercises, sets, reps, weight, RIR, side, warm-up, volume | Implemented; device gate pending |
| Merge Lab | Select 2+ events, elapsed/moving time, energy/distance, originals unchanged | Implemented |
| Merge exports | Apple Health, route/metadata copy, CSV, TCX share, direct Strava upload | Apple Health + Strava core; CSV/route parity pending |
| Strava | Server-side OAuth secret, state callback, encrypted refresh token, status/disconnect/upload | Implemented; live OAuth gate pending |
| Personalization | Profile age/DOB/sex/weight/height/body fat, validation, persistence and sync | Pending |
| Homeserver | Register, bearer ingest, cache fallback, observability and error codes | Partial |
| MCP | OAuth, search/fetch, summary/daily/workouts and full Progressa detail | Implemented; session hardening pending |
| Offline | Account-isolated protected cache, stale status, retries and no data loss | Partial |
| Accessibility | Dynamic Type, VoiceOver, contrast, Reduce Motion, small screens | Pending |

## HealthKit and Scoring

1. Read steps, active/basal/dietary energy, water/macros, HR/HRV/RHR, respiration, SpO2, body/wrist temperature, weight, height, body fat, sleep stages, profile and workouts.
2. De-duplicate overlapping sleep sources and retain missing-vs-zero semantics.
3. Port baseline calibration, sleep score/need, recovery, strain and body battery exactly with golden Dart/Swift fixtures.
4. Preserve workout HR, route, elevation, weather, humidity, AQI, distance and source UUID.
5. Write merged workouts only after explicit action; prevent duplicate exports.

## Integration Contracts

- Account IDs and existing sync credentials keep access after upgrade.
- Progressa callbacks require exact scheme/host/path and 256-bit state; codes are one-time and short-lived.
- Progressa workout JSON never drops exercise or set metadata.
- Progressa data is never a standalone Quantivita workout: it is visible only when `workout_health_metadata` explicitly links the Progressa workout to a matching HealthKit activity.
- Unlinked/deleted Progressa workouts produce no Quantivita list row; successful sync clears stale details, while failed sync retains and labels cached details.
- Missing sleep omits the contributor, reweights available signals and lowers confidence; real short sleep still caps recovery.
- Strava secrets and refresh tokens stay server-side and encrypted; the app receives no client secret.
- MCP `get_workout_details` accepts internal, external and `workout:` IDs.

## Test Program

- Swift unit: Codable, dates/timezones, merge math, TCX/CSV, scoring goldens, callback/state and cache isolation.
- Network contract: account, ingest, Progressa, Strava and MCP via injected `URLProtocol` fixtures.
- Server integration: link/exchange/replay, refresh retry, workout normalization, Strava token refresh/upload and account isolation.
- XCUITest: auth, permissions, four tabs, details, refresh, Progressa, Merge Lab and Strava.
- Accessibility snapshots: light/dark/system, Dynamic Type through AX sizes, VoiceOver labels and iPhone SE/current Pro.
- Physical device: real Apple ID, HealthKit, Progressa app-to-app, Strava OAuth/upload and merged HealthKit export.

## Release Gate

1. All P0/P1 rows complete; no placeholder or unreachable Flutter feature remains.
2. Native, Flutter-regression and both server suites pass.
3. Security review has no open P0/P1 finding.
4. Three consecutive end-to-end runs pass on two supported iOS versions and both Wi-Fi/mobile data.
5. Upgrade over the Flutter build preserves account, cache and integrations.
6. TestFlight smoke test passes before Flutter is retired.

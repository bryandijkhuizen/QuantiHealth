# Progressa Native Full Migration Plan

## Release Strategy

`ProgressaNative` is built beside Flutter with the production bundle identifier. Flutter remains the shipping fallback until every P0/P1 item, upgrade rehearsal, physical-device flow and TestFlight gate passes. Placeholder screens are release blockers.

## Execution Order

### Phase 0 - Contract freeze

- Inventory all reachable Flutter routes, Supabase tables/RPCs/functions, Hive boxes, preferences, deep links, notifications, StoreKit products, ads and Watch messages.
- Capture golden fixtures for workouts, exercise blocks/order, unilateral sets, health routes, feed posts, food, supplements and measurements.
- Status: inventory substantially complete; executable fixture catalogue pending.

### Phase 1 - Identity, onboarding and upgrade

- Preserve existing Supabase access/refresh session, user ID, provider and profile when replacing Flutter.
- Support email/password and Sign in with Apple, token refresh/revocation, useful errors, onboarding and account deletion.
- Migrate account-scoped Hive/preferences without exposing one user’s data to another.
- Status: native auth/profile/onboarding core implemented; Flutter session/data upgrade and deletion gate pending.

### Phase 2 - Workout engine and offline operation

- Full workout CRUD, routines, exercises, sets, RIR, side, warm-up, ordering, blocks, timers, notes, locations and history paging.
- Preserve optimistic/offline operations through an encrypted, ordered retry queue with conflict handling and idempotency.
- Keep Quantivita workout detail contracts stable throughout.
- Status: workout list/detail/basic CRUD and protected account cache implemented; routines, set/exercise editing, blocks/order and mutation queue pending.

### Phase 3 - Health, stats and measurements

- Port HealthKit import/export, cardio metadata, routes, permissions and de-duplication.
- Port strength/cardio statistics, personal records, charts, filters and all-set pagination.
- Port measurement CRUD/history/notes and unit conversion.
- Port WatchConnectivity and companion workout exchange.
- Status: all-set pagination, strength overview/current PRs, cardio metadata display and measurement list/add/note/delete with metric/imperial conversion are implemented. HealthKit/routes, charts/ranges, plateau/split and BMI remain P0.

### Phase 4 - Feed and social

- Port following/recent/popular feeds, text/rich/workout posts, comments, reactions, live workout snapshots and offline feed cache.
- Port user search, follow requests, followers/following, visibility, avatars and moderation/reporting paths.
- Port push/in-app notifications and preference controls.
- Status: pending and P0.

### Phase 5 - Food and supplements

- Port food diary, macro targets, Progressa food dataset, barcode scanning, recipes and serving/unit calculations.
- Port supplements, intake history, preferences and scheduled reminders.
- Preserve local drafts and pending writes across upgrade/offline use.
- Status: pending and P0.

### Phase 6 - Profile, monetization and services

- Port complete profile/settings, units, privacy, referrals, exports and destructive account deletion.
- Port StoreKit 2 subscriptions/restoration and server-side entitlement binding.
- Port Pro gates and ads without exposing paid users to ads or trusting local-only entitlement state.
- Status: pending and P0.

### Phase 7 - Accessibility and App Store release

- Add VoiceOver, Dynamic Type, contrast, Reduce Motion, localization readiness and small-screen/iPad behavior.
- Complete privacy manifest, nutrition/health disclosures, data deletion, export compliance, screenshots, metadata and review notes.
- Run upgrade-over-Flutter, rollback, offline recovery, two-iOS-version physical E2E and TestFlight smoke tests.
- Status: pending.

## Integration Contracts

- `progressa://quantivita-connect` accepts only the exact Quantivita callback and returns the original 256-bit state.
- Link codes are one-time, short-lived and atomically consumed in shared server storage.
- Quantivita receives complete exercises, sets, reps, weight, RIR, side, warm-up and volume without silent truncation.
- Quantivita receives only workouts with an explicit `workout_health_metadata` relation; Progressa remains the source of full details and unlinked workouts never cross the integration boundary.
- Supabase RLS remains the authorization boundary for every native REST/RPC operation.
- StoreKit entitlements are bound to the authenticated Progressa account and verified server-side.
- Health, social, food and offline caches are encrypted/protected and account-isolated.

## Automated Test Program

- Unit: auth/session migration, parsing, units, workout grouping/order, queues, charts, nutrition and entitlement gates.
- Contract: Supabase tables/RPCs/functions through injected URLProtocol fixtures and schema fixtures.
- Integration: Quantivita link/exchange/replay, workout details, offline replay, notifications and account deletion.
- XCUITest: auth/onboarding plus every tab’s create/read/update/delete workflow.
- Accessibility/snapshots: light/dark/system, Dynamic Type AX sizes, VoiceOver and supported devices.

## Release Gate

1. No placeholder, unreachable Flutter route or missing original feature remains.
2. Native, Flutter-regression, server and integration suites are green.
3. Security review has no open P0/P1 issue and privacy/account deletion are verified.
4. Three consecutive full E2E runs pass on two supported iOS versions and Wi-Fi/mobile data.
5. Installing native over Flutter preserves session, drafts, caches, integrations and paid entitlement; rollback remains possible.
6. Quantivita connect, sync, exercises/sets display, refresh and disconnect pass without 4xx/5xx or workaround.
7. TestFlight external smoke and App Store metadata/privacy review pass before Flutter retirement.

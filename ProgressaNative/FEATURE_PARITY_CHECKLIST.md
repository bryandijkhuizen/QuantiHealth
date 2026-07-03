# Progressa Flutter to Native iOS Feature Parity

This is the authoritative migration checklist. A feature is user-ready only after all applicable gates are met.

Status: `[x]` native implementation present, `[~]` partial, `[ ]` missing.
Gates: `T` automated tests, `L` verified against live backend, `D` verified on a physical iPhone.

## 1. Authentication and onboarding

- [x] Email/password sign-in. `T`
- [x] Sign in with Apple and nonce validation. `T`
- [x] Restore and refresh sessions from Keychain. `T`
- [x] Personal-details onboarding. `T`
- [x] Registration flow with confirmation redirect. `T`
- [x] Forgotten/reset-password and native deep-link recovery flow. `T`
- [x] Sign out.
- [x] Account deletion request.

## 2. App shell and home

- [x] Native tab shell: Feed, Workouts, Stats, Measurements, Me.
- [~] Home feed and own workout overview; Flutter news banner, combined dashboard and premium presentation remain.
- [ ] Notification badge and deep-link routing across every Flutter route.
- [ ] Changelog/news presentation.

## 3. Workouts

- [x] Cached workout list and pull-to-refresh. `T`
- [x] Lazy detail loading to avoid full-history timeouts. `T`
- [x] View title/date/source/location, exercises and sets. `T`
- [x] Preserve repeated and empty exercise blocks and server ordering. `T`
- [x] Legacy sets without valid block IDs remain visible and migration SQL exists. `T`
- [x] Instant workout creation: "Add workout" creates the workout immediately (no save-first form) and opens the workout detail screen, with an empty state prompting the first exercise. `T`
- [x] Create, rename and delete workouts. `T`
- [x] Add/search/create custom exercises.
- [x] Add/edit/delete sets: reps, weight, RIR, side and warm-up.
- [x] Two-step add-exercise wizard: search-first selection (no full-catalogue dump), then an editable per-set weight/reps table seeded from the previous workout's set structure (or last-used weight, or blank) before confirming. `T`
- [x] Sets are edited inline (weight/reps, autosaving) directly in the workout overview, not only via a modal.
- [x] Metric/imperial weight conversion.
- [x] Reorder and remove exercise blocks.
- [~] Offline cache; pending offline mutation queue/replay remains.
- [~] Last-used weight and previous set-structure suggestion exist; a dedicated exercise history/previous-logs list view remains.
- [ ] Workout insights and per-exercise insights.
- [ ] Workout share image/export.
- [ ] Publish workout as a rich social post.
- [ ] Full transactional graph mutation RPCs.

## 4. Exercises and routines

- [x] Visible built-in and user exercise catalogue.
- [x] Custom exercise creation.
- [~] My Exercises list/create plus rename, weight-type edit and delete; muscle-group editing remains. `T`
- [x] Routine list/create/rename/delete. `T`
- [x] Routine exercise add/remove/reorder. `T`
- [x] Routine set templates add/edit/delete. `T`
- [x] Start workout from routine with full-copy or reps-only. `T`
- [ ] Offline routine cache and pending mutations.

## 5. Apple Health, Watch and location

- [~] Apple Health permission flow exists; dedicated settings/status screen remains.
- [x] Import HealthKit workout sessions and persist health metadata. `T`
- [x] Link/unlink an existing workout to Health data. `T`
- [x] Heart rate, calories, duration, distance and GPS route map in imported/linked workout detail.
- [ ] Apple Watch workout draft transfer and pending-import flow.
- [ ] WatchConnectivity companion target and workout recording.
- [~] Route visualization: imported-workout and shared-post route maps render from HealthKit/snapshot GPS; foreground GPS workout recording (saves an HKWorkout + route to Apple Health, then imports) exists; background tracking remains. `T`

## 6. Social feed and posts

- [x] Following/recent/popular feed with offline cache. `T`
- [x] Create/edit/delete text posts. `T`
- [x] Visibility selection.
- [x] Like/unlike and own-like state. `T`
- [x] List/create/edit/delete post comments. `T`
- [x] Comment threads: parent rendering, reply composer (parent-linked) and comment likes. `T`
- [x] Feed and profile posts enrich author names/private avatars and render strength, cardio and non-fitness activity workout cards. `T`
- [x] Twitter-style post detail (post on top, comments below, reply composer) with a liker list. `T`
- [ ] Comment liker lists.
- [~] Rich workout post preview cards (strength + non-fitness health card with GPS route map) exist; dedicated friend snapshot viewer sheet remains.
- [ ] Repost/share workflow.
- [ ] Realtime feed/comment refresh.

## 7. People and profiles

- [x] User search and suggestions. `T`
- [x] Follow/request/unfollow state. `T`
- [x] Public profile summary and profile posts.
- [x] Followers/following lists with profile navigation. `T`
- [x] Private-avatar signed URL rendering in feed, search and profiles. `T`
- [x] Profile-photo choose, resize, upload, replace and remove. `T`
- [x] Edit name, handle, country, birthdate, height, sex, units and visibility.
- [ ] Avatar/profile live-backend and physical-device verification. `L D`

## 8. Statistics and plateaus

- [x] Strength overview and personal records. `T`
- [x] Cardio session overview. `T`
- [~] Progress charts/date ranges and detailed exercise progression remain.
- [~] Split analytics remains less detailed than Flutter.
- [ ] Plateau detection pages, preferences and deep links.
- [ ] Pro gates matching Flutter entitlements.

## 9. Measurements

- [x] Measurement list/add/delete and metric/imperial conversion. `T`
- [~] Notes supported; full detail history, interactive charts, BMI and range UI remain.

## 10. Food and nutrition

- [x] Daily diary totals and meal slots. `T`
- [x] Food search and serving quantities. `T`
- [x] Macro targets. `T`
- [~] Custom food create/edit and shared-dataset permissions remain.
- [ ] Barcode scanner and Open Food Facts fallback.
- [ ] Recipe create/edit and ingredient calculations.
- [ ] Goal recommendation flow and initial setup redirect.
- [ ] Full micronutrients and export parity.

## 11. Supplements

- [x] Supplement list and intake logging. `T`
- [x] Basic reminders using local notifications. `T`
- [~] Full detail/preferences/history UI remains.
- [ ] Export, deep-link reminder handling and server push parity.

## 12. Notifications and deep links

- [x] Notifications inbox, read state and follow-request handling. `T`
- [~] Pagination currently loads the latest 80; incremental paging remains.
- [ ] Push permission, APNs token registration and device cleanup.
- [x] Notification preferences for follows, likes and comments. `T`
- [ ] Plateau and supplement notification preferences.
- [ ] Push routing to posts, profiles, workouts and reminders.
- [ ] App badge synchronization.

## 13. Settings and account

- [x] Profile/account settings and deletion.
- [x] Unit preference.
- [x] Profile visibility.
- [x] Persisted system/light/dark and seven Flutter accent presets with modern native UI. `T`
- [ ] Apple Health settings.
- [x] Notification settings. `T`
- [ ] Changelog screen.
- [ ] Data export controls.

## 14. Premium, referrals and ads

- [ ] StoreKit purchase/restore and entitlement synchronization.
- [ ] Upgrade page and Pro feature gates.
- [ ] Referral code, share link and invite rewards.
- [ ] AdMob placements and consent behavior for free tier.

## 15. Reliability, privacy and release

- [x] Native backend configuration independent from Flutter.
- [x] Keychain session storage and protected workout cache.
- [x] Workout/session token refresh before expiry.
- [~] Offline read caches exist; complete sync queue/conflict handling remains.
- [ ] Realtime channel lifecycle and connectivity coordinator.
- [ ] Observability/crash reporting parity.
- [ ] Two-user RLS integration suite and live RLS migration deployment. `L`
- [ ] Complete UI test suite for critical journeys.
- [ ] Accessibility, localization and Dynamic Type audit.
- [ ] StoreKit/App Store privacy/metadata/screenshots/review notes.
- [ ] TestFlight smoke matrix and physical-device acceptance. `D`

## Current execution order

1. Finish profile avatars/posts/comments live contracts and tests.
2. Apple Health + Watch import/link flows.
3. Notifications inbox, push preferences and routing.
4. Complete food/recipes/scanner and supplements.
5. Complete stats/measurements/plateaus.
6. Premium/referrals/ads and remaining settings.
7. Offline sync/realtime hardening, UI automation and release gates.

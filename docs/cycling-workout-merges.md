# Cycling import and in-app activity combinations

Quantivita imports cycling power (watts), cadence (count/minute), and heart-rate measurements from HealthKit on iOS 17+. Existing users choose Settings → Review Apple Health permissions, then force-sync workout history. Permission denial or missing source data remains unavailable; measured zero watts/RPM remains zero. HealthKit only exposes the app that wrote a workout: an upstream Zwift/ROUVY provider is not guessed when Strava is the writer. Provider bundle ID, channel, writer name and available external/sync identifier are retained.

Normalized power is calculated before sample downsampling only with a complete, contiguous, unpaused one-second power series. It uses 30-second rolling means, their fourth powers, their mean and the fourth root ([TrainingPeaks algorithm](https://www.trainingpeaks.com/coach-blog/normalized-power-how-coaches-use/)). Sparse data remains unknown. Exported sample series retain up to 240 actual observations, including sample endpoints; they are not interpolated. Cycling units follow [Apple HealthKit](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/cyclingcadence).

## Canonical records

Raw imported records remain in the account data file. Combinations are stored separately in `<account>.merges.json`, atomically, under the same account authorization. Every read surface (REST, MCP, scoring and dashboard responses) projects the canonical records. Native raw HealthKit records remain separate from the canonical display state; both are cached in the existing account-scoped protected dashboard cache. An undo response includes restored records even if they fall outside the device's current HealthKit lookback.

Automatic deduplication requires the same provider-issued external identity, sport, and start within one minute. Timing resemblance alone is insufficient. Provenance from every copy is retained. An alias reimported after a manual merge remains hidden. Original records are never deleted by merge or undo, and no external provider API is called.

## Calculation and choices

- Disjoint segments: sum authoritative active durations, distance and energy. Elapsed time spans earliest start to latest end; gaps do not become active time.
- Pauses: pause/resume events identify active intervals. Shared active time is counted once.
- Partial overlap: the default preview cannot be confirmed. The user explicitly chooses either the first selected source as authoritative (duplicate reconciliation), or a union of active time with unknown distance, energy and averages. Incomplete pause timing blocks time-only reconciliation; selecting an authoritative source remains available.
- Samples: use duration-weighted measured intervals when every source supplies valid sample intervals; otherwise use available duration-weighted summaries, explicitly labelled as derived. Missing measurements are excluded. Maximums come from supplied maximum measurements. Normalized power for concatenated activities is unknown.
- Missing totals: REST/MCP records retain nulls. Aggregate responses provide missing measurement counts; totals are sums of available canonical measurements only.
- Different sports, unknown durations, strength sets and nested/reused combinations are rejected. Large gaps warn but do not block.
- Repeated creates and undo requests are idempotent; mutations of merge relations are serialized per account. Source resync recomputes the result and preserves membership. New overlap after resync is made conservative and visibly flagged for review.

## API

All routes require the account bearer token:

- GET `/api/users/:accountId/workout-merges`: canonical overrides and hidden source IDs.
- POST `/api/users/:accountId/workout-merges/preview`: `{workoutIds, strategy}` → sources, totals, warnings and `canMerge`.
- POST `/api/users/:accountId/workout-merges`: confirms the selection; strategy is `concatenate`, `duplicate` or `time_only`.
- POST `/api/users/:accountId/workout-merges/:mergeId/undo`: restores original visibility.

The native app supplies a preview and explicit confirmation, with undo in activity details. The API validates each mutation again.

## Validation / deliberate MVP limits

Server tests cover gap exclusion, overlaps, pauses, missing vs zero, source identity deduplication, aliases after reimport, weighted samples, account authorization, concurrent retries, immutable originals and undo. Native tests cover wire/cache preservation, display projection and normalized-power completeness.

FIT upload, training zones, 30/60/90-day cycling trends/index and sample-level overlap reconciliation remain P2. Real-device sensor/permission validation needs HealthKit records; simulator fixtures cannot reproduce a user's sensor history.

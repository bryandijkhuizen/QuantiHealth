# Quantivita iOS 0.4.0

- Export recorded HealthKit workout activities with active duration, optional
  measured distance, start/end and raw activity type for interval pace results.
- Request walking/running distance read access during Health authorization.
- Retain workout marker events and interval-related scalar metadata.
- Keep missing distance separate from measured zero; keep planned targets separate
  from actual results. Include the recorded workout end for partial final steps.

The dashboard shows per-block time, distance, min/km and km/h only when recorded
activities reliably match the Apple interval plan. It rejects a single whole-workout
activity, mismatched blocks and unavailable measurements instead of estimating them.

After installation, use Workouts → Force sync all workouts and grant distance read
access if prompted. Whether Apple exposes individual activities for Bryan's past
interval workouts must still be verified from the resulting device sync.

Validation: 10 focused native tests, full native GitHub CI, 28 dashboard/server tests
and a mobile UI test for measured pace/speed, missing data and overflow passed.

Quantivita CI and distribution select the supported macOS 15 / Xcode 26.3 runner
image. Native tests remain mandatory before uploading the signed archive.

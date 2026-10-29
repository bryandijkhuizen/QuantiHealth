# Quantivita iOS 0.2.0

- Sync measured running heart-rate and speed observations, recorded workout events,
  available running dynamics, GPS-derived complete kilometer splits and dated VO2max
  to the existing training dashboard.
- Keep uploads below the server's request limit and report failed force syncs correctly.
- Preserve existing HealthKit UUIDs, account isolation and backward-compatible caches.
- Run all native unit tests in GitHub CI and before TestFlight distribution.

After installing, open Workouts → Force sync all workouts and review the new Health
permissions to backfill available measurements. Missing source data remains missing.
GPS-derived splits are omitted for incomplete or ambiguous routes; GPS coordinates
are not uploaded to the dashboard.

Validation: all 57 native unit tests passed on GitHub, along with the server tests
and release-manifest validation. Physical-device comparison against Apple Fitness
remains necessary after installation.

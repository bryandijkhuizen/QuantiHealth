# Training dashboard: native HealthKit export

The native app keeps the existing account, sync token, workout UUIDs and ingest endpoint.
No second importer is required. This branch does not install an app on a physical iPhone.

## Exported measurements

Running workouts include optional workout-associated heart-rate and running-speed
observations (at most 240 evenly spaced real observations per series), lap/segment
and pause/resume events, and available HealthKit average running power, stride length,
ground-contact time and vertical oscillation. Cadence is calculated from a workout's
recorded step total and active duration only when that total exists.

Complete kilometer splits are calculated from GPS observations, with interpolated
boundary times. `splitMethod: gps-distance-active-time` distinguishes these derived
splits from native recorded laps. Poor accuracy, gaps over 30 seconds, implausible
speeds or an ambiguous pause boundary omit the splits. Incomplete final kilometers
are not exported. GPS coordinates themselves are never sent to the dashboard.

VO2max is exported as dated HealthKit measurements in daily rows (`vo2Max`,
`vo2MaxMeasuredAt`, `vo2MaxSource`). It is not estimated from heart rate. Historical
sync exports historical VO2max; routine refresh covers the last 30 days.

The server receives telemetry at the workout's top level; the local cache keeps it
in the optional `telemetry` field. Existing caches without it continue to decode.
Unavailable optional metrics are omitted. No interval classification is inferred
from average heart rate or fabricated split data.

## Upload reliability

Workout uploads are split into requests of at most 1,500,000 JSON bytes, below the
server's 2 MB limit. Repeated uploads retain the same IDs. A single oversized row
or oversized daily-data envelope produces an error rather than silent truncation.
The weight-history checkpoint advances only after all requests succeed. Force sync
does not replace an upload failure with a success message.

## Device verification after distribution

1. Distribute QuantivitaNative through the repository's TestFlight workflow.
2. Install the new build on the iPhone. Open Workouts → Force sync all workouts.
3. Grant the newly requested HealthKit read permissions. The phone must contain
   actual source measurements; permission alone does not create them.
4. Compare one long run and one interval session with Apple Fitness: duration,
   distance, recorded events, heart rate, speed, power and available splits.
5. Check dashboard data coverage and confirm that manually corrected categories
   survive another sync.

Simulator tests cannot verify real HealthKit permissions or Apple Watch data.
Source-specific absence of running-speed/step statistics can leave those fields
unavailable even when a route or distance total exists.

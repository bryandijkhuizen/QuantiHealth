# Training dashboard: native HealthKit export

The native app keeps the existing account, sync token, workout UUIDs and ingest endpoint.
No second importer is required. This branch does not install an app on a physical iPhone.

## Exported measurements

The app also exports `appleWorkoutActivities`: ended, recorded HealthKit activities
with UUID, start/end, active duration and an optional recorded walking/running
distance. Missing statistics stay nil; measured zero distance stays zero. Raw
activity-type codes are explicitly named `activityTypeRaw`, not Quantivita's enum.
Read authorization now includes walking/running distance for recorded block metrics.
`workoutEndTime` supports recognizing a partly completed final step. Workout marker
events are retained, with only interval/segment/lap/step/purpose metadata keys.

These recorded activities may represent the whole workout rather than individual
intervals. The dashboard must reject a single whole-workout activity or mismatched
plan/activity sequences, and must not synthesize block results from planned goals.
When separate activities match the plan order and goals, pace and km/h use the
recorded distance divided by active duration. Device data must confirm availability.

On iOS 17+, the app reads `HKWorkout.workoutPlan` through WorkoutKit. Custom running
plans export `appleWorkoutPlan` with source `healthkit-workout-plan`, plan UUID,
warmup/cooldown, blocks, iteration counts, and explicit work/recovery purposes.
Targets are normalized to seconds, meters or kcal; open targets stay unspecified.
These are planned goals, not measured results for each interval. Generic segment
events and kilometer splits do not establish a structured interval workout.

`appleWorkoutPlanStatus` reports available/noPlan/notCustom/readFailed/unsupportedOS.
The presence of an Intervals screen in Fitness has not yet been verified to yield
a non-nil public WorkoutKit plan for every historical Apple-created workout. Device
resync must confirm this; missing plans are never reconstructed from physiology.
Reference: https://developer.apple.com/documentation/healthkit/hkworkout/workoutplan

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

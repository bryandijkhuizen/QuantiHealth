# Deep Research Implementation Check

Source: `/Users/bryandijkh/Downloads/deep-research-report.md`

## Implemented

- Hybrid architecture:
  - Morning Recovery score.
  - Intraday Body Battery reserve.
  - Separate daily Strain score.
  - Dynamic sleep need and sleep performance.
- Body Battery transparency:
  - Tappable home hero.
  - Breakdown for recovery charge, sleep charge, activity drain, movement drain, strain drain, stress drain, and low-stress recharge.
- Confidence-aware recovery:
  - Recovery scoring already emits confidence from calibration status and available signals.
  - Body Battery detail sheet now shows recovery confidence.
- Sleep need:
  - Baseline 8h sleep need.
  - Extra sleep need from daily strain.
  - Sleep debt carryover from short sleep.
  - Sleep performance = actual sleep / calculated need.
- Strain:
  - Internal nonlinear load remains available.
  - User-facing UI uses `0-100%`, per current Quantivita product decision.
- Nutrition/hydration:
  - Not part of the original Garmin/WHOOP score model, but implemented as user-facing context.
  - Hydration target is dynamic from body mass, active kcal, and workout minutes.

## Already Partially Present

- Personal baselines:
  - Current baseline service uses today-derived fallback values.
  - The architecture is ready for rolling 28-day median/MAD once more local history is persisted.
- Recovery inputs:
  - HRV, RHR, sleep, strain balance, respiratory rate, and wrist temperature deviation are already used.
- Strain inputs:
  - Workout duration, active energy, average HR, workout type, resting HR, and max HR are already used.

## Not Yet Implemented

- True minute-level intraday reservoir:
  - Current Body Battery is recalculated from daily summary inputs.
  - The research report recommends minute-level state updates with recovery/stress/activity regimes.
- Signal Quality Index:
  - Recovery confidence exists, but no low-level PPG/HRV artifact confidence model exists yet.
- Motion-gated stress:
  - Current stress panel uses synthetic/static samples.
  - Report recommends classifying activity first, then recovery/stress only during low-motion windows.
- Rolling baseline persistence:
  - Need a local history store for 21-28 day median/MAD baselines.
- Sleep window selection:
  - Current HealthKit summary does not expose slow-wave HRV windows.
  - Report recommends stable deep-sleep or fallback still sleep windows.
- VO2max/EPOC normalization:
  - Not available yet from current HealthKit bridge.

## Next Technical Step

Persist daily snapshots locally, then replace same-day fallback baselines with rolling 28-day robust baselines and confidence-aware trend eligibility.

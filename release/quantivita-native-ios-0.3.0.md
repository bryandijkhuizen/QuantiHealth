# Quantivita iOS 0.3.0

- Read the public HealthKit-linked WorkoutKit plan on iOS 17 and later.
- Export custom running-plan warmup/cooldown, explicit Work/Recovery steps,
  repetitions and planned duration/distance/energy goals through the existing sync.
- Report whether the plan is available, absent, unsupported or unreadable.
- Keep plan targets separate from measured interval results and kilometer splits.

After installing, use Workouts → Force sync all workouts to refresh historical
records. The dashboard gives actual linked interval plans unconditional priority
for the training type and displays the planned steps.

Validation: native simulator build, 9 focused conversion/serialization tests and
full native GitHub CI passed; 26 dashboard/server tests and mobile browser checks
passed separately. Public plan availability for historical Apple-created workouts
must still be verified on the user's iPhone after resync.

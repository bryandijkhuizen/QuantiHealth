# Workout sessions and sequences

Apply `migrations/20261102_workout_sessions.sql` to the **Progressa** Supabase project before installing this feature build. It uses the existing nullable `start_time`/`end_time` columns and adds sequence metadata. Historical workouts keep both times unknown, so they do not become active. New manual workouts start immediately; Health imports store their recorded start and end. The unique partial index permits one active workout per account. Existing table RLS remains in force; the sequence RPC is security-invoker and checks ownership explicitly.

The sequence RPC creates all exercise blocks and order rows in one transaction. It does not create sets or count planned work as completed. A failure rolls everything back.

## Local database checks

Use a disposable PostgreSQL cluster, never production, for `tests/base_schema_fixture.sql`. This fixture represents the subset of the existing schema used here, and supplies a test `auth.uid()`. Apply the fixture, then the migration, then `tests/workout_sessions.sql` using `psql -v ON_ERROR_STOP=1`. The checks cover ordering, rounds, rollback, foreign-account access, invalid times and the one-active-workout constraint. Live schema/RLS compatibility must also be checked before rollout.

## App and signing

The new WidgetKit target is `ProgressaLiveActivity`, bundle ID `com.bryandijkh.progressa.liveactivity`. Register that identifier and provision its App Store profile through the existing signing bootstrap flow. The TestFlight workflow now passes extension identifiers to Match and supplies a separate export profile per target. The release requires the migration and the extension signing profile.

The app and extension currently use 2.1.0. Bump both Info.plist versions together when preparing the feature release. Fastlane updates build numbers for the project.

## Preview and verification

Xcode previews in `ProgressaLiveActivity.swift` cover the Lock Screen and expanded Dynamic Island. In a Debug build, launch the app with `--workout-preview` for a sample workout without an account or backend; this mode is read-only and excluded from Release builds. Normal logging starts/updates/ends Live Activities locally, and refreshes server state on return to the foreground. There is no cross-device push synchronization while the app is suspended. Verify Lock Screen, compact/minimal/expanded Island, Dynamic Type, disabled Live Activities and finish/delete/sign-out on a real device before distribution.

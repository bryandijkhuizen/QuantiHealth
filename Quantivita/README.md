# Quantivita

Quantivita is a local-first, data-driven health companion built with Flutter.

The first flow is a privacy-first onboarding for a BEVEL-like experience: sign in or local registration, Apple Health permission, then a dashboard with blurred placeholders until real health summaries are available.

## Product Direction

- Today dashboard with recovery, strain, sleep, stress, and activity.
- Apple Health as the primary source for wearable and phone health data.
- Local-first app data, synced through the user's private iCloud container.
- Sign in with Apple for privacy-friendly identity without requiring a hosted app database.
- Journal entries for mood, soreness, alcohol, caffeine, stress, illness, and notes.
- Explainable insights based on trends and correlations, not medical diagnosis.

## Technical Direction

- Flutter owns the interface and product flows.
- The codebase follows a lightweight MVC layout: `models/` for health-domain data, `controllers/` for state and actions, `views/` for screens, `services/` for platform/auth boundaries, `widgets/` for reusable UI, and `theme/` for design tokens.
- A native iOS Swift HealthKit bridge owns permission requests and checks whether recent Health data exists.
- A native iOS Core Data store mirrored with `NSPersistentCloudKitContainer` should own local app data and iCloud sync.
- Sign in with Apple should be used only for identity/account continuity, not as a storage layer.
- Raw Apple Health data should be read locally and cached as daily summaries only when needed.
- Privacy and security notes are tracked in `SECURITY.md`.

## Manual Apple Steps

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the Runner target and confirm bundle id `com.bryandijkh.quantivita`.
3. Enable the `HealthKit` capability.
4. Enable `iCloud` and select `CloudKit`.
5. Create or select the iCloud container `iCloud.com.bryandijkh.quantivita`.
6. Enable the `Sign in with Apple` capability.
7. Test on a physical iPhone with Apple Health data; the simulator is limited for this app.

## Next Build Steps

1. Add HealthKit summary reads for sleep, HRV, resting heart rate, workouts, steps, and active energy.
2. Add Core Data entities for journal entries, daily summaries, and sync metadata.
3. Mirror Core Data with CloudKit and expose sync status to Flutter.
4. Replace blurred placeholders with real local daily summaries only when data is present.
5. Persist onboarding, Apple Health status, and the Apple user identifier in the local store.

## Run On A Physical iPhone

Full Quantivita stack, including homeserver deploy and iPhone app run:

```sh
STRAVA_CLIENT_ID=<numeric-client-id> \
STRAVA_CLIENT_SECRET=<client-secret> \
./scripts/run_full_stack.sh
```

You can also put local settings in `.env`:

```sh
cp .env.example .env
```

Then fill in `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` and run:

```sh
./scripts/run_full_stack.sh
```

Use a different env file when needed:

```sh
QUANTIVITA_ENV_FILE=/path/to/quantivita.env ./scripts/run_full_stack.sh
```

Or pass credentials as flags:

```sh
./scripts/run_full_stack.sh \
  --strava-client-id <numeric-client-id> \
  --strava-client-secret <client-secret>
```

Deploy or update only the homeserver dashboard/API:

```sh
./scripts/deploy_homeserver.sh
```

Dashboard/API URL:

```sh
https://api.quantivita.bryandijkh.com
```

Dashboard login is tied to the Apple-linked account created by the iPhone app.
Open `Settings > App integrations`, sync `Quantivita API`, then use the shown
`qv_...` account id and sync token to sign in to the dashboard.

Run only the iPhone app with Quantivita API dart-defines:

```sh
STRAVA_CLIENT_ID=<numeric-client-id> \
STRAVA_CLIENT_SECRET=<client-secret> \
./scripts/run_app.sh
```

Equivalent flag form:

```sh
./scripts/run_app.sh \
  --strava-client-id <numeric-client-id> \
  --strava-client-secret <client-secret>
```

Override defaults when needed:

```sh
QUANTIVITA_ACCOUNT_ID=bryan \
QUANTIVITA_API_BASE_URL=https://api.quantivita.bryandijkh.com \
QUANTIVITA_DEVICE_ID=<IPHONE_DEVICE_ID> \
./scripts/run_app.sh
```

Verify app build and homeserver reachability:

```sh
./scripts/verify_quantivita.sh
```

Hot reload route:

```sh
./scripts/run_iphone.sh
```

This runs `flutter run`; press `r` for hot reload, `R` for hot restart, and `q`
to quit.

With an explicit device id:

```sh
./scripts/run_iphone.sh 00008150-001E439C2242401C
```

Profile launch without hot reload:

```sh
./scripts/run_iphone_profile.sh
```

Profile launch with live console logs:

```sh
./scripts/run_iphone_logs.sh
```

Manual hot reload route:

```sh
cd /Volumes/SSD/Projects/DataDrivenHealthCompanion
rtk flutter devices
rtk flutter run -d <IPHONE_DEVICE_ID>
```

If only one iPhone is connected and trusted:

```sh
rtk flutter run -d ios
```

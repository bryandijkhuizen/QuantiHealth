# Security Notes

This file is a practical engineering checklist aligned with ISO/IEC 27001-style controls. It is not a certification statement.

## Current Security Posture

- Data model: HealthKit authorization is implemented; dashboard metrics remain hidden behind placeholders until real summary reads are added.
- Storage model: planned local-first storage with Core Data and private CloudKit mirroring.
- Network model: Quantivita can sync to the private homeserver. Requests are scoped to `/api/users/:accountId` and require the account bearer sync token, or an HttpOnly signed session cookie for `/api/me/*`.
- Identity model: Sign in with Apple is present, but the app requests no email or full-name scopes.
- Secrets scan: no app secrets, API keys, passwords, or bearer tokens found in `lib/`, `ios/`, `android/`, `pubspec.yaml`, or `README.md`.
- Android network access: no `INTERNET` permission in `android/app/src/main/AndroidManifest.xml`; Flutter debug/profile manifests keep development-only internet permission.
- iOS sensitive capabilities: HealthKit, CloudKit, and Sign in with Apple entitlements are explicit in `ios/Runner/Runner.entitlements` and present in the debug app signature.

## ISO 27001-Aligned Engineering Controls

- Data minimization: request the narrowest Apple identity scope and avoid syncing raw HealthKit data.
- Access control: Apple Health permissions are requested after onboarding context and only for sleep, heart, activity, and workout read types.
- Cryptographic boundary: rely on iOS data protection, Keychain for future identifiers/tokens, and CloudKit private database transport/storage protections.
- Secure development: keep `flutter analyze` and `flutter test` green before builds.
- Supplier/dependency management: review direct dependencies before adding packages; current runtime dependency surface is intentionally small.
- Logging: never log HealthKit samples, Apple user identifiers, iCloud record identifiers, or journal notes in production.
- Ecosystem integrations: Progressa access tokens are accepted only through an authenticated Quantivita account route, stored server-side encrypted with AES-256-GCM, and exposed to clients only as a short fingerprint plus connection metadata. Progressa workout details are fetched through the Quantivita homeserver so the app never needs to expose the Progressa bearer token in dashboard payloads, CSV exports, or browser storage.
- Retention: provide delete-local-data and disconnect-iCloud flows before storing real user data.
- Incident readiness: document data categories and export/delete behavior before TestFlight.

## Dependency Review

Last checked with:

```sh
rtk flutter pub deps --style=compact
rtk flutter pub outdated
```

Direct runtime dependencies:

- `cupertino_icons`
- `sign_in_with_apple`

`sign_in_with_apple` has a newer major release available, but `7.0.1` is the newest version resolvable with the current Flutter/Dart constraints in this project. Re-check before a release build.

## Release Security Checklist

1. Confirm Apple Developer capabilities match `Runner.entitlements`.
2. Add HealthKit permission screens explaining every metric category.
3. Store Apple user identifiers in Keychain or an encrypted local store, not plain debug logs.
4. Add local data deletion and iCloud disconnect flows.
5. Add a privacy policy that states there is no custom hosted health database.
6. Run dependency checks before every TestFlight build.
7. Validate release builds on a physical device with production signing.

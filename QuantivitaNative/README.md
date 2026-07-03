# Quantivita Native

Parallel native SwiftUI migration target for iOS 16 and later. The Flutter app remains the production reference until the parity release gate is complete.

Generate the Xcode project:

```sh
rtk ruby Scripts/generate_project.rb
```

Build and test:

```sh
rtk xcodebuild -project QuantivitaNative.xcodeproj -scheme QuantivitaNativeTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The app keeps the production bundle identifier so HealthKit, Sign in with Apple, deep links and upgrade behavior can be validated. Do not install the Flutter and native builds side by side on the same device.

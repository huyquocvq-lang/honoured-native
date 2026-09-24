# Honoured Native

Native iOS and Android shells for the Honoured Lovable web app.

## Architecture

- iOS: SwiftUI + `WKWebView`
- Android: Kotlin + Android `WebView`
- Web app URL: injected from local environment config
- Native/web communication: whitelisted bridge protocol documented in `docs/bridge.md`
- Billing: RevenueCat backed by StoreKit 2 / Google Play Billing
- Trial state: Supabase-backed custom trial engine in the Lovable app

## Local environment config

All machine-specific values live in a single gitignored `.env` at the repository
root. Never commit real API keys.

```bash
cp .env.example .env
```

Then fill in:

```dotenv
HONOURED_WEB_APP_URL=https://honour-your-word.lovable.app
REVENUECAT_IOS_API_KEY=appl_xxxxxxxxxxxxxxxxx
REVENUECAT_ANDROID_API_KEY=goog_xxxxxxxxxxxxxxxxx
IOS_BUNDLE_ID=com.honoured.app
IOS_DEVELOPMENT_TEAM=XXXXXXXXXX
```

- **Android** reads `.env` directly at Gradle configuration time and exposes the
  values as `BuildConfig` fields. `android/local.properties` may override any
  key for that machine only — it is read after `.env` and wins per key, so
  overriding one value leaves the rest coming from `.env`:

  ```properties
  sdk.dir=/Users/you/Library/Android/sdk
  REVENUECAT_ANDROID_API_KEY=goog_machine_specific_key
  ```

  `local.properties` is gitignored too, and Android Studio manages `sdk.dir`
  in it.
- **iOS** cannot read `.env`, so `scripts/sync-env.sh` projects it into the
  gitignored `ios/Config.xcconfig`, which `ios/project.yml` applies to the
  target. `xcodegen generate` runs the script automatically via `preGenCommand`;
  run it by hand after editing `.env` without regenerating:

```bash
./scripts/sync-env.sh
```

`IOS_BUNDLE_ID` overrides the production bundle identifier declared in
`ios/project.yml`, so a throwaway App ID can be used for testing without
modifying tracked files. Leave it unset to build `com.honoured.app`.

## Repository layout

```text
honoured-native/
├── .env.example
├── scripts/
│   └── sync-env.sh
├── ios/
│   ├── project.yml          # XcodeGen spec; Honoured.xcodeproj is generated
│   ├── Honoured.storekit
│   ├── Honoured/            # app target, one folder per feature
│   │   ├── App/             # entry point, app delegate, AppConfig
│   │   ├── WebView/         # root view, WKWebView host, load state, WebKit tweaks
│   │   ├── Bridge/          # NativeBridge message handling, durable event store
│   │   ├── Auth/            # Keychain session store, Sign in with Apple
│   │   ├── Billing/         # RevenueCat
│   │   ├── Health/          # HealthKit reads, upload queue, background sync, goals
│   │   ├── Timer/           # Testament Timer
│   │   ├── Notifications/   # local notifications, completion sound
│   │   ├── LiveActivities/  # ActivityKit and bridge glue; Core/ is the engine
│   │   ├── Debug/           # BridgeStub test page (Debug builds only)
│   │   └── Info.plist, Honoured.entitlements, PrivacyInfo.xcprivacy, Assets.xcassets
│   ├── HonouredShared/      # content state and deep links shared with the widget
│   ├── HonouredWidgets/     # Widget Extension that renders the Live Activities
│   └── HonouredTests/       # unit tests (fake ActivityKit, Health, timer, clock)
├── android/
│   └── app/src/main/java/com/honoured/app/
│       ├── MainActivity.kt  # WebView shell
│       ├── AppConfig.kt
│       ├── bridge/          # NativeBridge message handling
│       └── billing/         # RevenueCat
└── docs/
    ├── bridge.md
    └── billing.md
```

## iOS development

The iOS project is defined with XcodeGen.

```bash
cp .env.example .env   # then fill in the values
brew install xcodegen
cd ios
xcodegen generate      # also regenerates Config.xcconfig from .env
open Honoured.xcodeproj
```

Before real billing tests:

1. Select the Apple development team.
2. Confirm the final App Store bundle identifier.
3. Set `REVENUECAT_IOS_API_KEY` in `.env` and run `./scripts/sync-env.sh`.
   Leave `REVENUECAT_ENTITLEMENT_ID` empty unless you are testing against an
   entitlement in your own RevenueCat project; see `docs/billing.md`.
4. Enable the In-App Purchase capability.

RevenueCat iOS is integrated with Swift Package Manager.

### Live Activities

Contract Live Activities need iOS 16.2; the app still runs on iOS 16.0 and
reports the feature as unsupported there (ActivityKit is weak-linked). The
`HonouredWidgets` extension is embedded in the app and built with it:

- Its bundle identifier is the app's plus `.widgets` (for example
  `com.honoured.app.widgets`), so the App ID behind `IOS_BUNDLE_ID` needs a
  matching extension App ID. Automatic signing creates it for the team in
  `IOS_DEVELOPMENT_TEAM`; with manual signing, create it and a profile first.
- The app declares `NSSupportsLiveActivities` and the `honoured://` URL scheme
  that a tapped card opens. No App Group, push notification or
  frequent-update capability is needed.
- The app and the extension read their version from `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` in `ios/project.yml`; bump them there.

The protocol is in `docs/bridge.md` (*v2 — Live Activities*). The plan, its
limits and the validation record are in `docs/live-activities-plan.vi.md`.

### Google Sign-In

Native shows Google's own UI and returns an ID token; the web app verifies it
with Supabase (`docs/bridge.md`, *Google Sign-In*). Public client IDs come from
`.env`, never a client secret:

```dotenv
GOOGLE_WEB_CLIENT_ID=123-web.apps.googleusercontent.com   # token audience, both platforms
GOOGLE_IOS_CLIENT_ID=123-ios.apps.googleusercontent.com   # iOS client for the signed bundle id
```

- `scripts/sync-env.sh` writes both to `ios/Config.xcconfig` and derives the
  callback URL scheme (the reversed iOS client ID), which `Info.plist`
  registers next to `honoured://`. Missing or malformed values leave the
  feature off (`configured: false`); nothing crashes.
- GoogleSignIn-iOS is pinned to 10.0.0 in `ios/project.yml` (the first release
  that accepts a custom nonce) and linked into the app target only.
- Google Cloud needs, in the same project and environment: the Web client, an
  iOS client for the real bundle id, and an Android client for
  `com.honoured.app` with the SHA-1 of every signing key (debug, and the Play
  App Signing certificate for store builds).
- Supabase's Google provider must accept the Web and iOS client IDs, keep
  nonce checks on, and have **Manual linking** enabled for "Link Google".

Debug builds can fake Google's UI with `-HonouredFakeGoogle success|slow|cancel|error|network`
together with `-HonouredBridgeStub`; the `google` and `google-reload` scenarios
use it (see Tests below).

### Tests

The `HonouredTests` unit tests run on a simulator without a host app:

```bash
cd ios
xcodebuild -project Honoured.xcodeproj -scheme Honoured \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Honoured-sim \
  CODE_SIGNING_ALLOWED=NO test
```

Set `TEST_RUNNER_HONOURED_RENDER_DIR=/some/folder` to also write the rendered
card variants as PNG files.

A Debug build started with `-HonouredBridgeStub` loads a test page instead of
the web app (see `ios/Honoured/Debug/BridgeStub.swift`). `-HonouredBridgeScenario`
runs one of its scripted checks, for example `google` (with
`-HonouredFakeGoogle success`), `google-reload` (with `-HonouredFakeGoogle slow`),
`live-activities-multiple`,
`live-activities-focus-race`, `live-activities-health`, `live-activities-timer`,
`live-activities-account`, `live-activities-deeplink` or
`live-activities-restore-setup` followed by `live-activities-restore-check`;
add `-HonouredStubExitWhenDone` to quit when it finishes. Build with ad-hoc
signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`) to run it:

```bash
xcrun simctl launch --console-pty booted <bundle id> \
  -HonouredBridgeStub -HonouredStubExitWhenDone \
  -HonouredBridgeScenario live-activities-multiple
```

The stub signs in with a fake session and fake Health totals, never reaches
Supabase, and is compiled out of Release builds.

## Android development

Open the `android` directory in Android Studio and let Gradle sync the project.

Current requirements:

- Android Studio with JDK 17
- compileSdk / targetSdk 35
- minSdk 26

Before running, create the root `.env` as described above.

Command-line build (no Android Studio required, JDK 17 on `JAVA_HOME`):

```bash
cp .env.example .env   # then fill in the values
cd android
./gradlew assembleDebug
```

Unit tests and lint:

```bash
./gradlew testDebugUnitTest lintDebug
```

Google Sign-In uses Credential Manager and reads only `GOOGLE_WEB_CLIENT_ID`.
It runs over an origin-scoped `WebMessageListener` (`window.HonouredAuth`),
installed before the first page load; a WebView without
`WEB_MESSAGE_LISTENER` reports the feature unsupported. The legacy
`HonouredNative` interface keeps serving billing and refuses the auth
messages. No Firebase or `google-services.json` is involved.

## Foundation bridge

### iOS web call

```js
window.webkit?.messageHandlers?.honouredNative?.postMessage({
  bridgeVersion: 1,
  type: 'APP_READY',
  payload: {}
})
```

### Android web call

```js
window.HonouredNative?.postMessage(JSON.stringify({
  bridgeVersion: 1,
  type: 'APP_READY',
  payload: {}
}))
```

Native events are delivered to the web app with:

```js
window.addEventListener('honoured:native', event => {
  console.log(event.detail)
})
```

## Current status

Implemented:

- iOS SwiftUI shell + `WKWebView`
- Android Kotlin shell + WebView
- shared bridge version 1
- RevenueCat SDK integration on both platforms
- `CHECK_ACCESS`
- `START_PURCHASE`
- `RESTORE_PURCHASES`
- `IDENTIFY_USER`
- Lovable native billing bridge
- Supabase trial engine
- RevenueCat/Supabase user identity binding
- local environment config for web URL and RevenueCat keys

Still required for real billing tests:

- real RevenueCat public SDK keys
- RevenueCat entitlement/offering/package configuration
- verified StoreKit product in App Store Connect
- verified Google Play subscription product
- sandbox/internal-track billing tests
- release signing and store submission

See `docs/billing.md` for RevenueCat dashboard requirements and bridge details.

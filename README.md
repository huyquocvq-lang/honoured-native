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
│   ├── project.yml
│   ├── Honoured.storekit
│   └── Honoured/
├── android/
│   └── app/
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
4. Enable the In-App Purchase capability.

RevenueCat iOS is integrated with Swift Package Manager.

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

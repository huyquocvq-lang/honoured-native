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

Do not commit real API keys or environment-specific URLs.

### iOS

```bash
cd ios
cp Config.xcconfig.example Config.xcconfig
```

Then set:

```text
HONOURED_WEB_APP_URL = https://honour-your-word.lovable.app
REVENUECAT_IOS_API_KEY = appl_xxxxxxxxxxxxxxxxx
```

`ios/Config.xcconfig` is gitignored and injected into `Info.plist` through Xcode build settings.

### Android

```bash
cd android
cp local.properties.example local.properties
```

Then set:

```properties
HONOURED_WEB_APP_URL=https://honour-your-word.lovable.app
REVENUECAT_ANDROID_API_KEY=goog_xxxxxxxxxxxxxxxxx
```

`android/local.properties` is gitignored and injected into `BuildConfig`.

## Repository layout

```text
honoured-native/
├── ios/
│   ├── Config.xcconfig.example
│   ├── project.yml
│   └── Honoured/
├── android/
│   ├── local.properties.example
│   └── app/
└── docs/
    ├── bridge.md
    └── billing.md
```

## iOS development

The iOS project is defined with XcodeGen.

```bash
cd ios
cp Config.xcconfig.example Config.xcconfig
brew install xcodegen
xcodegen generate
open Honoured.xcodeproj
```

Before real billing tests:

1. Select the Apple development team.
2. Confirm the final App Store bundle identifier.
3. Set `REVENUECAT_IOS_API_KEY` in `Config.xcconfig`.
4. Enable the In-App Purchase capability.

RevenueCat iOS is integrated with Swift Package Manager.

## Android development

Open the `android` directory in Android Studio and let Gradle sync the project.

Current requirements:

- Android Studio with JDK 17
- compileSdk / targetSdk 35
- minSdk 26

Before running, copy `local.properties.example` to `local.properties` and set the local values.

Command-line build (no Android Studio required, JDK 17 on `JAVA_HOME`):

```bash
cd android
cp local.properties.example local.properties
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

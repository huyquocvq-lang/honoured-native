# Honoured Native

Native iOS and Android shells for the Honoured Lovable web app.

## Architecture

- iOS: SwiftUI + `WKWebView`
- Android: Kotlin + Android `WebView`
- Web app: `https://honour-your-word.lovable.app`
- Native/web communication: whitelisted bridge protocol documented in `docs/bridge.md`
- Billing: RevenueCat backed by StoreKit 2 / Google Play Billing
- Trial state: Supabase-backed custom trial engine (next step)

## Repository layout

```text
honoured-native/
├── ios/
│   ├── project.yml
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
cd ios
brew install xcodegen
xcodegen generate
open Honoured.xcodeproj
```

Before real billing tests:

1. Select the Apple development team.
2. Confirm the final App Store bundle identifier.
3. Set `REVENUECAT_IOS_API_KEY` in the target build settings.
4. Enable the In-App Purchase capability.

RevenueCat iOS is integrated with Swift Package Manager.

## Android development

Open the `android` directory in Android Studio and let Gradle sync the project.

Current requirements:

- Android Studio with JDK 17
- compileSdk / targetSdk 35
- minSdk 26

Configure the RevenueCat public Android SDK key as a Gradle property:

```properties
REVENUECAT_ANDROID_API_KEY=goog_xxxxxxxxxxxxxxxxx
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

Step 1 foundation is implemented:

- iOS SwiftUI shell + `WKWebView`
- Android Kotlin shell + WebView
- external link handling
- back navigation
- shared bridge version 1

Step 2 RevenueCat foundation is implemented in source:

- RevenueCat dependency on iOS and Android
- SDK configuration hooks
- `pro` entitlement check
- `CHECK_ACCESS`
- `START_PURCHASE`
- `RESTORE_PURCHASES`
- purchase success/cancel/failure bridge events
- restore success/failure bridge events
- safe not-configured state when API keys are missing

Still required:

- set real RevenueCat public SDK keys
- configure RevenueCat project / entitlement / offering / packages
- verify final StoreKit 2 product in App Store Connect
- verify Google Play subscription product
- Supabase trial/session enforcement
- Lovable paywall/session bridge wiring
- sandbox billing tests
- release signing / store submission

See `docs/billing.md` for RevenueCat dashboard requirements and bridge details.

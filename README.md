# Honoured Native

Native iOS and Android shells for the Honoured Lovable web app.

## Architecture

- iOS: SwiftUI + `WKWebView`
- Android: Kotlin + Android `WebView`
- Web app: `https://honour-your-word.lovable.app`
- Native/web communication: whitelisted bridge protocol documented in `docs/bridge.md`
- Billing: RevenueCat + StoreKit 2 / Google Play Billing (next implementation step)
- Trial state: Supabase-backed custom trial engine (planned step)

## Repository layout

```text
honoured-native/
├── ios/
│   ├── project.yml
│   └── Honoured/
├── android/
│   └── app/
└── docs/
    └── bridge.md
```

## iOS development

The iOS project is defined with XcodeGen so the project file does not need to be manually maintained.

```bash
cd ios
brew install xcodegen
xcodegen generate
open Honoured.xcodeproj
```

Select a development team and replace `com.honoured.app` with the final App Store bundle identifier before signing/submission.

## Android development

Open the `android` directory in Android Studio and let Gradle sync the project.

Current requirements:

- Android Studio with JDK 17
- compileSdk / targetSdk 35
- minSdk 26

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

- iOS SwiftUI shell
- iOS `WKWebView`
- Android Kotlin shell
- Android WebView
- external link handling
- back navigation support
- shared bridge version 1 contract
- billing/session message placeholders ready for subsequent steps

Not implemented yet:

- RevenueCat
- StoreKit 2 purchase flow
- Google Play Billing purchase flow
- restore purchases
- Supabase trial/session enforcement
- Lovable paywall bridge wiring
- release signing / store submission

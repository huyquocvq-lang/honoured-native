# Billing architecture

Honoured uses RevenueCat as the subscription state layer while Apple StoreKit 2 and Google Play Billing remain the underlying stores.

## RevenueCat contract

- Entitlement ID: `honoured_plus`. Both shells read it from
  `REVENUECAT_ENTITLEMENT_ID` (`.env`, or `android/local.properties` for
  Android only) and fall back to `honoured_plus` when it is unset, so a
  developer build can check an entitlement in a personal RevenueCat project
  without editing tracked source. The web app and `has_entitlement()` in the
  database are hardcoded to `honoured_plus`: under any other identifier the
  RevenueCat webhook writes no `subscriptions` row, so paid state holds only
  through the native `ACCESS_STATUS` path and not server-side. iOS reads the
  value from `Info.plist`, so `./scripts/sync-env.sh` has to run after
  changing it; both platforms print a warning while the override is set, and
  it must be cleared before archiving a store build.
- Current offering: required
- Purchase packages: the web app passes the exact RevenueCat identifiers `$rc_monthly` or `$rc_annual`. Native rejects an unknown identifier instead of silently purchasing a different package. The first package is used only for legacy callers that omit the identifier entirely.
- Subscription source of truth: RevenueCat `CustomerInfo`

## Bridge messages

### Check access

Web -> native:

```json
{"type":"CHECK_ACCESS","payload":{}}
```

Native -> web:

```json
{"type":"ACCESS_STATUS","payload":{"isSubscribed":true,"entitlement":"honoured_plus","source":"revenuecat"}}
```

### Purchase

Web -> native:

```json
{"type":"START_PURCHASE","payload":{"packageIdentifier":"$rc_monthly"}}
```

`packageIdentifier` is optional. If omitted, native selects the first package from RevenueCat's current offering.

Native emits one of:

- `PURCHASE_SUCCESS`
- `PURCHASE_CANCELLED`
- `PURCHASE_FAILED`

A successful purchase is immediately followed by `ACCESS_STATUS`.

### Restore

Web -> native:

```json
{"type":"RESTORE_PURCHASES","payload":{}}
```

Native emits `RESTORE_SUCCESS` or `RESTORE_FAILED`. A successful restore is immediately followed by `ACCESS_STATUS`.

## iOS configuration

The XcodeGen project includes RevenueCat through Swift Package Manager. Set `REVENUECAT_IOS_API_KEY` for the Honoured target before building a store-connected app.

The key is injected into `Info.plist` as `RevenueCatAPIKey` and read at runtime. An empty key leaves billing disabled and returns `source = revenuecat_not_configured` instead of crashing.

The App Store target must also have the In-App Purchase capability enabled before sandbox/store testing.

Two schemes are generated. **Honoured** attaches `Honoured.storekit`, so products
and payments are served locally from that file: it exercises the app's own flow
but proves nothing about App Store Connect, and RevenueCat cannot validate the
receipts it produces. **Honoured (Store Sandbox)** attaches no StoreKit
configuration, so a run on a real device goes through the real sandbox exactly
as a TestFlight build does — with a Sandbox Apple ID signed in under Settings →
Developer — while still being a Debug build, so `Purchases.logLevel = .debug`
prints the underlying StoreKit error that the web app's failure dialog hides.

## Android configuration

Set the Gradle property before building:

```properties
REVENUECAT_ANDROID_API_KEY=goog_xxxxxxxxxxxxxxxxx
```

For local development this can live in the user's Gradle properties rather than committed source. The value is exposed as a generated `BuildConfig` field.

## Required store and RevenueCat setup

App Store Connect (once, by the account holder):

1. Sign the Paid Apps agreement under Agreements, Tax, and Banking. Until it is signed, sandbox returns no products.
2. Create one subscription group with two auto-renewable subscriptions (monthly, annual) under the **same bundle ID the build uses**. Fill in the metadata so each product is at least *Ready to Submit*.

RevenueCat dashboard:

3. Add the Apple app using that bundle ID, and the Google Play app using the Android application ID.
4. Configure each platform's public SDK key in the native build.
5. Products: import from App Store Connect (requires the In-App Purchase key uploaded to RevenueCat) or add the exact product IDs by hand.
6. Create entitlement `honoured_plus` and attach both products.
7. Offerings: in the offering marked *Current*, attach the monthly product to package `$rc_monthly` and the annual product to `$rc_annual`.

If step 7 is missing, `Purchases.offerings()` fails before the purchase sheet with
"You have configured the SDK with an App Store API key, but there are no App Store products registered in the RevenueCat dashboard for your offerings", and the web app shows it verbatim as *Payment failed*.

A build signed under a different bundle ID or team (e.g. a developer's own `HONOURED_BUNDLE_ID`) can never fetch the client's products: StoreKit only returns products for the running app's bundle ID. Purchase testing needs a build under the store bundle ID — a TestFlight build or team membership — plus a Sandbox Apple ID on the device.
6. Attach the product(s) to `honoured_plus`.
7. Create a current Offering and add at least one Package.

Custom Honoured trial/session limits are intentionally not stored in RevenueCat; they will be implemented in the Supabase trial-engine step.
Do not configure a separate App Store or Play introductory free trial; the Supabase 7-day/12-session policy is the single trial system.

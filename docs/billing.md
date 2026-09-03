# Billing architecture

Honoured uses RevenueCat as the subscription state layer while Apple StoreKit 2 and Google Play Billing remain the underlying stores.

## RevenueCat contract

- Entitlement ID: `pro`
- Current offering: required
- Purchase package: the bridge may pass `payload.packageIdentifier`; otherwise the first package in the current offering is used.
- Subscription source of truth: RevenueCat `CustomerInfo`

## Bridge messages

### Check access

Web -> native:

```json
{"type":"CHECK_ACCESS","payload":{}}
```

Native -> web:

```json
{"type":"ACCESS_STATUS","payload":{"isSubscribed":true,"entitlement":"pro","source":"revenuecat"}}
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

## Android configuration

Set the Gradle property before building:

```properties
REVENUECAT_ANDROID_API_KEY=goog_xxxxxxxxxxxxxxxxx
```

For local development this can live in the user's Gradle properties rather than committed source. The value is exposed as a generated `BuildConfig` field.

## Required RevenueCat dashboard setup

1. Add the Apple app using the final iOS bundle ID.
2. Add the Google Play app using the final Android application ID.
3. Configure each platform's public SDK key in the native build.
4. Create entitlement `pro`.
5. Import/link the store subscription product(s).
6. Attach the product(s) to `pro`.
7. Create a current Offering and add at least one Package.

Custom Honoured trial/session limits are intentionally not stored in RevenueCat; they will be implemented in the Supabase trial-engine step.

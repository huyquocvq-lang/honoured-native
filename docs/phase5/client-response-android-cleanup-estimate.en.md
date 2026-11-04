# Client response - Android and cleanup assessment

Hi,

Thank you. I have now reviewed both the updated Android scope and the History + Icon cleanup milestone against the current Honoured repository and the latest Android, Health Connect, Google Play and Samsung documentation.

## Architecture and reuse

I can confirm that Honoured is not React Native. The iOS app is a Swift/SwiftUI shell with a WKWebView loading the React/Lovable application. Android already has a Kotlin WebView shell loading the same application.

This gives us substantial reuse:

- Home, Contract, Icon, Journal, History and Settings remain shared React/Lovable screens.
- Supabase data, authentication, contract rules, Icon rules, signatures, revisions and history remain shared.
- The Android shell, Google Sign-In, microphone handling and the core RevenueCat purchase/restore bridge already exist.
- The main Android-specific work is Health Connect/phone tracking, background execution, notifications, deadline reconciliation, native capability bridging, real-device QA and Play compliance.

I have excluded any duplicated charge for rebuilding shared screens or business rules natively.

## Cleanup milestone

The cleanup scope is clear and technically appropriate. I recommend completing it before freezing the Android parity baseline, because the same Lovable UI will then be reused automatically on Android.

My estimate is **12 hours total**:

- Seven-day History default, selected-date mode and date-boundary handling: 3 hours
- Horizontal month swipe while preserving arrows, vertical scroll and date taps: 2.5 hours
- Active Icon collapse/expand and independent action-link alignment: 2.5 hours
- Automated regression tests and mobile browser/WebView QA: 3 hours
- Integration review and minor regression buffer: 1 hour

No database migration or deletion of old history is required.

## Android step tracking answer

Honoured does **not** need to depend exclusively on Android's `TYPE_STEP_COUNTER` sensor.

My recommended source model is:

1. **Automatic** - read aggregate steps from Health Connect. This can include phone data, Samsung Health, a connected watch or another approved provider, while Health Connect handles source priority and overlap.
2. **Phone** - use Health Connect's on-device phone steps where supported, otherwise use the native `TYPE_STEP_COUNTER` when the device exposes it.
3. If neither phone source is available, show Phone tracking as unavailable rather than returning a false zero.

I do not recommend building Honoured's own raw-accelerometer step algorithm in this milestone. Android restricts continuous accelerometer events while an app is in the background, so it would require a foreground service, use more battery and introduce substantial device-specific accuracy work.

`TYPE_STEP_COUNTER` remains the preferred low-power direct sensor when available. It can continue counting while the device processor is suspended, but Android still requires the correct permission and app/service lifecycle. Health Connect's newer built-in phone step tracking also uses `TYPE_STEP_COUNTER` internally. Health Connect can nevertheless receive steps from Samsung Health or another provider even when Honoured is not reading that sensor directly.

For locked-screen behaviour, I propose two distinct modes:

- **Passive tracking:** Health Connect/Samsung Health records the data and Honoured reconciles it when Android permits background work or when the app next runs. This is reliable for totals but does not support a universal near-realtime notification promise.
- **User-started active tracking:** where the feasibility prototype supports it, Honoured runs an Android health foreground service with a persistent notification and evaluates the direct phone count for faster goal recognition while the screen is locked.

I agree with the scope document that we should aim for recognition within five minutes where technically feasible, but not guarantee it universally before measuring Pixel and Samsung hardware under screen lock, Doze, Battery Saver, swipe-away, reboot and permission changes. A Force-stopped app cannot be claimed to continue processing.

## Samsung Galaxy A06 5G

The Galaxy A06 5G is a useful Samsung test device and I am comfortable using it for this project, with one qualification.

Samsung's official specification confirms that it has an accelerometer, gyro and other motion sensors, and Samsung Health can derive steps from the phone's acceleration sensor and synchronize step records to Health Connect. However, Samsung's public specification does not explicitly confirm that this exact model exposes Android's `TYPE_STEP_COUNTER` to third-party applications.

Therefore:

- it should be suitable for testing Samsung Health + Health Connect, locked-screen behaviour and Samsung battery restrictions;
- it should not be the only Android test device;
- after purchase I will run a small sensor/Health Connect probe immediately to confirm `TYPE_STEP_COUNTER`, `TYPE_STEP_DETECTOR`, Health Connect Extension support and background-read capability;
- I recommend purchasing it with a return window if possible;
- the final reliability matrix should also include a real Google Pixel device as the Android reference implementation.

## Android estimate

After auditing the current source rather than relying only on the scope headings, I propose **188 hours for Android plus 12 hours for the cleanup milestone, for a fixed 200-hour combined plan**. The tracking proof of concept is included and is not charged a second time.

The increase is not for rebuilding the shared UI. The source audit found that Android currently contains the WebView shell, Google Sign-In and RevenueCat foundation, but has no Health Connect or sensor implementation, native Supabase background session, durable health queue, WorkManager/foreground-service pipeline, FCM token/service, boot recovery, notification permission flow or Android contract/timer tracking engine. The existing Android test suite contains 11 tests focused on Google authentication/support; the new state, sync and background paths need their own coverage.

| Work package | Hours |
|---|---:|
| Foundation, release and lifecycle | 15 |
| Secure bridge and native Supabase session | 18 |
| Health Connect and direct phone tracking | 42 |
| Durable health sync and backend data integrity | 22 |
| Contract/timer/background/notification engine | 29 |
| FCM and backend push parity | 15 |
| Lovable/WebView parity | 11 |
| Account and Google Play/RevenueCat hardening | 6 |
| Device QA, compliance and Play launch | 30 |
| **Android total** | **188** |

The 188-hour Android estimate breaks down as follows:

| Detailed work item | Hours |
|---|---:|
| Frozen baseline/capability audit | 2 |
| Build flavors, signing and production release configuration | 3 |
| App Links, cold-start routing and lifecycle/process restoration | 7 |
| Permission/capability coordinator and foundation tests | 3 |
| Origin-scoped health/tracking bridge | 4 |
| Encrypted native Supabase session storage | 4 |
| Serialized token refresh/rotation handling | 4 |
| Persisted native event queue | 3 |
| Account cleanup and bridge/session tests | 3 |
| Pixel/Samsung tracking feasibility prototype | 10 |
| Health Connect availability, permissions and disclosure | 5 |
| Approved metric mapping | 5 |
| Aggregate/source attribution/deduplication | 6 |
| Direct `TYPE_STEP_COUNTER` implementation | 5 |
| Automatic/Phone source choice and fallback | 4 |
| Day/reset/timezone queries, estimates and tracking tests | 7 |
| Durable offline queue and retry/split/drop logic | 5 |
| Authenticated native Supabase client | 5 |
| Daily ledger/history recomputation | 4 |
| Android record identity/schema compatibility | 4 |
| Late/deleted records, account cleanup and sync tests | 4 |
| Android tracked-contract state engine | 6 |
| Testament timer engine | 5 |
| Health foreground service and ongoing notification | 5 |
| Notification channels/status/settings/local delivery | 3 |
| Goal completion and deadline/recovery logic | 6 |
| Engine/background tests | 4 |
| Firebase Messaging client and token lifecycle | 4 |
| Backend token-provider migration and rollback | 3 |
| Server FCM routing/error classification | 4 |
| Android push payload/deep links and integration tests | 5 |
| Lovable adapter, Health UI and WebView parity/tests | 11 |
| Production account and Play/RevenueCat E2E | 6 |
| Test plan/evidence and risk-based automation | 6 |
| Real Pixel reliability matrix | 4 |
| Real Galaxy A06 5G reliability matrix | 4 |
| Android API compatibility regression | 3 |
| Privacy and accessibility basics | 2 |
| Play declarations, signed AAB and internal test | 4 |
| Submission and one in-scope response | 2 |
| Included seven-day defect allowance | 5 |
| **Android total** | **188** |

The largest combined block is the 108 hours for tracking, durable synchronization, background contract/timer behaviour and Android push delivery. The current backend push path is APNs-specific, so Android scheduled reminders require an FCM client plus backend provider routing rather than only a local UI change. Native background health upload also requires a secure Supabase session and refresh path that Android does not currently have.

To hold the combined plan at 200 hours, the health scope is frozen to steps, walking distance and approved calorie behaviour. QA is risk-based, real-device tracking focuses on a Pixel and Galaxy A06 5G, other API levels primarily use emulators, and the included defect allowance is five hours. The scope excludes a raw-accelerometer pedometer, Wear OS, proprietary wearable SDKs and full parity with all nine iOS Health metrics. Later feature changes require change control.

The cleanup milestone is 12 hours, making the combined total **200 hours**.

## Proposed delivery milestones

### Milestone 1 - History and Icon cleanup: 12 hours

- Complete the 12-hour History/Icon cleanup.

### Milestone 2 - Android foundation, native session and web parity: 44 hours

- Freeze the accepted iOS/Lovable/Supabase reference.
- Harden Android lifecycle, deep links, permissions, release configuration and capability bridge.
- Add the secure native Supabase session/refresh and persistent event queue required by background work.
- Verify account sign-in and all shared Contract/Icon/Journal/History flows on a physical Android device.

### Milestone 3 - Tracking feasibility and core tracking: 42 hours

- Run the Pixel/Samsung sensor and locked-screen feasibility gate.
- Integrate Health Connect and direct Phone tracking.
- Implement source selection and prevent double counting.

### Milestone 4 - Durable synchronization and background engine: 51 hours

- Implement durable offline health synchronization and backend-compatible Android record identity.
- Implement the Android tracked-contract and timer state engine.
- Add Android foreground tracking where justified by the prototype.
- Reconcile late-arriving evidence, deadline state, reboot, timezone and offline recovery.
- Deliver median, P90, worst-case delay, missed-notification and battery-impact evidence.

### Milestone 5 - FCM, billing, QA and Play release: 51 hours

- Add FCM token registration and account-safe token lifecycle.
- Extend the APNs-specific backend schema and sender with provider-aware FCM routing.
- Deliver scheduled reminders, completion notifications and Android deep links.
- Complete Google Play/RevenueCat test purchase, cancellation, restore and entitlement tests.
- Run the documented Android parity checklist.
- Test real Pixel and Samsung devices and relevant Android API behaviours.
- Complete Health apps, Health Connect, privacy and Data safety declarations.
- Produce the signed AAB, closed/internal test release and Play submission.
- Include a seven-calendar-day, up-to-five-hour defect-fix window for reproducible issues against the frozen scope.

## Scope assumptions and exclusions

The estimate assumes:

- the cleanup build, accepted iOS build, Lovable deployment and Supabase migrations are frozen before Android parity work;
- the existing shared web/backend implementation is reused;
- weekday-specific Icon targets and prospective signed amendments are included after final Jimmy acceptance of the current implementation;
- a real Galaxy A06 5G and a real Pixel are available for the tracking reliability matrix;
- Play Console, Google OAuth, Supabase and RevenueCat access/configuration are available when required.

The estimate excludes proprietary Garmin/Samsung wearable integrations, a Wear OS app, a new raw-accelerometer pedometer, new Android Word Tracker integrations, a native UI rewrite, extensive tablet redesign, guaranteed sub-five-minute delivery, tracking after Force stop, marketing and ongoing post-launch maintenance.

The full implementation plan will preserve source timestamps, immutable signed records and existing account data. Any result inferred from batched sensor data will be distinguished from directly observed evidence; if a deadline crossing cannot be determined safely, the contract remains pending until reconciliation rather than being guessed.

Thank you.

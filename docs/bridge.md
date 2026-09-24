# Honoured Native Bridge v2

The native shell hosts `https://honour-your-word.lovable.app` inside a WebView and exposes a small, whitelisted message bridge. v2 adds HealthKit, timers, notifications, auth session hand-off, Sign in with Apple and, on iOS 16.2+, Live Activities for tracked contracts. Every v1 message keeps working unchanged.

Native reports its version in `NATIVE_READY`. The web app must feature-detect on `bridgeVersion` and only send v2 messages when it is `>= 2`.

## Transport

**Web → Native.** Post a JSON object to the `honouredNative` handler:

```js
window.webkit.messageHandlers.honouredNative.postMessage({
  bridgeVersion: 2,
  type: 'START_TIMER',
  payload: { requestId: 'r-42', activityId: 'act_9', activityName: 'Meditation', durationSeconds: 900 }
})
```

**Native → Web.** Native dispatches a `honoured:native` browser event:

```js
window.addEventListener('honoured:native', event => {
  const { bridgeVersion, type, payload } = event.detail
})
```

**Request IDs.** If a message carries `payload.requestId`, every reply to it echoes the same `requestId`. Events without a `requestId` are unsolicited broadcasts. The web app uses this to tell a reply apart from a broadcast so that answering a request can never trigger another.

**Errors.** Any message can be answered with `ERROR { message, code? }`. Feature-specific failures use their own event (`PURCHASE_FAILED`, `APPLE_SIGN_IN_FAILED`, …) and always carry `message`.

**Event queue.** Some events originate while the WebView is not ready — a notification tapped on cold start, a goal reached during a background sync, a session refreshed in the background. Native buffers these and flushes them in order right after it has replied to the **first message the web app sends after a page load** (`APP_READY` if the web sends it, otherwise whatever comes first — today that is `IDENTIFY_USER`). Any inbound message counts because it proves the bridge module is running. The buffer is bounded (last 50). Events the user would notice losing — `NOTIFICATION_OPENED`, `GOAL_REACHED`, `TIMER_COMPLETED`, `LIVE_ACTIVITY_OPENED` — are also persisted on disk, so they survive an app relaunch and a background launch that never created a WebView; they are delivered exactly once, merged by time with the in-memory buffer. Everything else (including anything carrying a token) survives a reload only. Both buffers are cleared when the session is cleared or a different user signs in.

**Integration notes for `src/lib/native-bridge.ts`.**

- Bump `BRIDGE_VERSION` to `2` and add the v2 types to `OutboundType`.
- `request()` resolves on the first event whose type is in `expected` or is `ERROR`. Every v2 request below names exactly one success reply type, so the existing helper works unchanged.
- The default 8 s timeout is too short for anything that shows system UI. Use a long timeout (the existing `PURCHASE_TIMEOUT_MS` is fine) for `REQUEST_HEALTH_PERMISSION` and `SIGN_IN_WITH_APPLE`; the user may sit on the sheet.
- Broadcasts need a persistent `onNativeEvent` listener registered once at app start, not a per-call `request()`. Attach it before the first outbound message so nothing flushed from the queue is missed.
- Send `APP_READY` from that same startup path. It is not required for the queue any more, but it gets `NATIVE_READY` back with `bridgeVersion`, which is the cleanest way to feature-detect.

All platform-specific capabilities must be invoked through an explicit message type. Do not expose a generic native method executor to the WebView.

---

## v1 — foundation and billing (unchanged)

| Web → Native | Reply |
|---|---|
| `APP_READY` | `NATIVE_READY { platform, bridgeVersion, capabilities?, liveActivityBridgeSessionId? }` then any queued events |
| `GET_PLATFORM_INFO` | `PLATFORM_INFO { platform, bridgeVersion, capabilities?, liveActivityBridgeSessionId? }` |
| `IDENTIFY_USER { userId }` | `IDENTIFY_SUCCESS` or `IDENTIFY_FAILED { message }`, followed by `ACCESS_STATUS` when a verdict is available |
| `LOGOUT_USER` | `LOGOUT_SUCCESS` then `ACCESS_STATUS { isSubscribed: false, source: "logout" }` |
| `CHECK_ACCESS { userId }` | `ACCESS_STATUS { isSubscribed, entitlement?, source }` |
| `START_PURCHASE { userId, packageIdentifier? }` | `PURCHASE_SUCCESS` / `PURCHASE_CANCELLED` / `PURCHASE_FAILED`, success followed by `ACCESS_STATUS` |
| `RESTORE_PURCHASES { userId }` | `RESTORE_SUCCESS` / `RESTORE_FAILED`, success followed by `ACCESS_STATUS` |
| `START_SESSION` | `ERROR` — trial sessions are enforced by Supabase RPC from the web app |

See `docs/billing.md` for RevenueCat details. The iOS shell adds `capabilities` and `liveActivityBridgeSessionId` to `NATIVE_READY` and `PLATFORM_INFO` (see *v2 — Live Activities*); the other fields are unchanged.

---

## v2 — auth session

Native writes HealthKit data to Supabase under row-level security, so it needs the signed-in user's session. The web app owns the session while it is in the foreground; native only refreshes on its own when it wakes in the background and the WebView is not running.

| Web → Native | Reply |
|---|---|
| `SET_AUTH_SESSION { userId, accessToken, refreshToken, expiresAt }` | `AUTH_SESSION_ACCEPTED { userId, liveActivityBridgeSessionId }` |
| `CLEAR_AUTH_SESSION` | `AUTH_SESSION_CLEARED { liveActivityBridgeSessionId }` |

| Native → Web (broadcast) | When |
|---|---|
| `AUTH_SESSION_UPDATED { accessToken, refreshToken, expiresAt }` | Native refreshed the token in the background. Web must call `supabase.auth.setSession()` with these values. |
| `AUTH_SESSION_INVALID { reason }` | Refresh failed. Web should re-authenticate and send a fresh `SET_AUTH_SESSION`. |

Rules:

- Web sends `SET_AUTH_SESSION` on `SIGNED_IN`, `TOKEN_REFRESHED` and `INITIAL_SESSION` from supabase-js, including for anonymous users. This is the only way native learns who to sync for.
- `expiresAt` is a positive, finite Unix-seconds number.
- Native stores the pair in the Keychain and never logs it.
- Receiving a session for a different `userId` clears the previous user's
  offline queue, HealthKit anchors and goal settings before the new session is
  stored. Every queued batch is also bound to its originating user as a second
  account-isolation check.
- Native refreshes only when the app is not active (background task, HealthKit observer wake). Supabase's refresh-token reuse window covers the rare overlap with a foreground refresh.
- `CLEAR_AUTH_SESSION` wipes the Keychain entry, the offline sync queue and all HealthKit anchors, so a different user signing in on the same device starts from a clean read.
- Native needs `SupabaseURL` and `SupabaseAnonKey` in `Info.plist`, injected through `Config.xcconfig` the same way as `RevenueCatAPIKey`.

---

## v2 — HealthKit

### Metric identifiers

These names are used in bridge payloads and in the `health_samples.metric` / `health_daily.metric` columns. Native converts to the canonical unit before sending anything.

| Metric | HealthKit type | Unit | Daily aggregate |
|---|---|---|---|
| `steps` | `HKQuantityTypeIdentifier.stepCount` | count | sum |
| `distance_walking_running` | `.distanceWalkingRunning` | meters | sum |
| `distance_cycling` | `.distanceCycling` | meters | sum |
| `distance_swimming` | `.distanceSwimming` | meters | sum |
| `active_energy` | `.activeEnergyBurned` | kcal | sum |
| `basal_energy` | `.basalEnergyBurned` | kcal | sum |
| `heart_rate` | `.heartRate` | bpm | average |
| `exercise_minutes` | `.appleExerciseTime` | minutes | sum |
| `sleep` | `HKCategoryTypeIdentifier.sleepAnalysis` | minutes | sum of `asleep*` values |

Notes:

- Distance is split by activity type because a cycling goal must not be satisfied by walking. The web app picks the right metric per activity (Run/Walk/Hike → `distance_walking_running`, Cycle → `distance_cycling`, Swim → `distance_swimming`) and converts meters to km/mi for display.
- `active_energy` and `basal_energy` are both read so the UI can show either "active" or "total" once Open Item #1 is answered. Until then the web app should treat "Calories" as `active_energy`.
- `sleep` only counts `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM`. `inBed` and `awake` are ignored. A night is attributed to the day the sleep **ended**. On an iPhone with no watch or sleep app this will usually be empty — the web app hides the metric when `HEALTH_METRICS` returns `null` for it.
- `heart_rate` is the average over the requested range, never a sum.

### Permission and status

| Web → Native | Reply |
|---|---|
| `REQUEST_HEALTH_PERMISSION { metrics?: [...] }` | `HEALTH_PERMISSION_STATUS` — shows the system sheet for the given metrics (all nine if omitted) |
| `GET_HEALTH_STATUS` | `HEALTH_PERMISSION_STATUS` — no UI |

```json
{
  "type": "HEALTH_PERMISSION_STATUS",
  "payload": {
    "available": true,
    "perMetric": {
      "steps": "determined",
      "sleep": "determined",
      "heart_rate": "notDetermined"
    }
  }
}
```

`available` is `false` on devices without HealthKit (iPad). Per-metric values:

- `notDetermined` — the user has not been asked about this metric yet. Calling `REQUEST_HEALTH_PERMISSION` will show the sheet.
- `determined` — the user has decided. **iOS does not reveal which way.** A declined metric returns exactly what a granted metric with no data returns: `null`. Do not build a "permission denied" screen on this value; show "no data yet" and offer a link to Settings → Health → Data Access.
- `unknown` — HealthKit could not report status (rare, transient).

`REQUEST_HEALTH_PERMISSION` with an unknown metric name replies `ERROR { code: "unknown_metric" }` so typos surface during integration rather than as silently missing data.

### Reading

| Web → Native | Reply |
|---|---|
| `QUERY_HEALTH_METRICS { metrics: [...], from, to }` | `HEALTH_METRICS` |

`from` / `to` are ISO 8601 with offset. Reads straight from HealthKit, so this is the fast path for "today so far". For the seven-day trend the web app reads `health_daily` from Supabase instead of querying seven ranges.

```json
{
  "type": "HEALTH_METRICS",
  "payload": {
    "from": "2026-09-14T04:00:00+07:00",
    "to": "2026-09-14T21:12:03+07:00",
    "metrics": {
      "steps": { "value": 8214, "unit": "count" },
      "distance_walking_running": { "value": 6180, "unit": "meters" },
      "sleep": null
    }
  }
}
```

A metric is `null` when it is unauthorized or has no samples in the range.

### Goals and day boundary

Native detects goal completion in the background, so it must know the targets and where a "day" starts.

| Web → Native | Reply |
|---|---|
| `SET_GOALS { goals: [{ activityId, activityName, metric, target, unit }] }` | `GOALS_ACCEPTED { count }` |
| `SET_DAY_RESET_HOUR { hour }` | `DAY_RESET_HOUR_ACCEPTED` |

- Web sends `SET_GOALS` with the full list every time the day's contract changes. Native replaces, never merges. An empty list clears all goals.
- `target` is in the metric's canonical unit (meters, kcal, minutes, count). The web app converts from km/mi before sending.
- `hour` is 0–23 in the device's local time zone and is the user's daily reset hour from Settings. It defines `health_daily.day` and the window for "reached today". Default is 0 if never sent.

| Native → Web (broadcast) | When |
|---|---|
| `GOAL_REACHED { activityId, metric, value, target, reachedAt, notified }` | A goal crossed its target. `notified` is `true` if native posted a local notification because the app was not active. Fired at most once per activity per day. Queued if the WebView is not ready. |
| `HEALTH_DATA_UPDATED { syncedAt, metrics: [...] }` | A background sync finished. Web should re-query anything it displays. |

Web owns contract state. `GOAL_REACHED` is per slot; the web app records the slot as reached for that health day (`honoured.goalsReached.v1`) and marks the contract honoured only once **every Health-mapped slot** of the contract has been reached — the same rule `trackedProgress()` and the standing-contract rollover already use. Slots that are not Health-mapped never block. The in-app celebration runs when the contract is honoured and `notified` is `false`; a partial slot only updates the measured line on the contract card. Native needs no change for this: it keeps firing once per activity per day.

How native decides:

- Goals are checked against today's source-deduplicated totals (the same numbers as `health_daily`) right after `SET_GOALS`, after `SET_DAY_RESET_HOUR` changes the hour, and after every collection pass that read new samples — including background wakes, before HealthKit's completion handler is acknowledged.
- "Once per activity per day" is a persisted marker keyed by `activityId` and the health day. Re-sending `SET_GOALS` with the same activity, or raising/lowering its target, never repeats the announcement for that day. A new `activityId` on the same metric is announced on its own.
- `ACTIVITY_COMPLETED` sets the same marker, so a contract the web app already marked honoured (timer, manual) is never announced or notified by native that day, even if its metric later crosses the target.
- The notification (`goal-<activityId>-<day>`) is posted only when the app is not active and permission is granted; `value` and `target` are in the metric's canonical unit. In the foreground only the event is sent.
- Changing the reset hour discards the markers, because the day boundaries moved. The evaluation that follows runs while the app is active, so any goal still met is re-announced in-app with `notified: false` and never as a notification.
- No goal for an activity today means no announcement — native never falls back to a previous day's list.

### Background sync

Native does not need anything from the web app to sync in the background, but the web app should know what to expect:

- Observer queries for all nine metrics are registered when the process launches. Hourly background delivery is enabled on `SET_AUTH_SESSION`, after `REQUEST_HEALTH_PERMISSION` completes, and at launch when a stored session exists; `CLEAR_AUTH_SESSION` disables it again.
- Each wake reads new samples through the anchored queries, writes the batch to the offline queue, then acknowledges HealthKit. Only after that does native attempt **one** upload. If the upload fails, the batch stays queued and is retried on the next wake, on reconnect, or when the app comes to the foreground — so a slow or offline network never blocks HealthKit from waking the app again.
- `.hourly` is a ceiling, not a schedule. iOS decides when to wake the app; a wake that arrives while the device is locked before first unlock is deferred until protected data is available.
- A `BGAppRefreshTask` (`<bundle id>.healthsync`, earliest one hour out) is scheduled whenever native holds a session — at launch, on `SET_AUTH_SESSION`, after each run and every time the app goes to the background — and cancelled on `CLEAR_AUTH_SESSION`. It runs the same collect-then-drain pass as an observer wake and is the fallback when HealthKit delivery does not fire. It is also best-effort; iOS may skip it entirely for days on a rarely used device.
- `HEALTH_DATA_UPDATED` is broadcast after a batch is uploaded, whether the sync ran in the foreground or the background. It is queued if the WebView is not ready.
- The simulator does not deliver background HealthKit updates. Only a signed build on a device with the background-delivery entitlement exercises this path.

---

## v2 — Testament Timer

Timers must survive backgrounding, so native owns the countdown and the completion notification. The web app renders the countdown but takes its clock from `endsAt`.

| Web → Native | Reply |
|---|---|
| `START_TIMER { activityId, activityName, durationSeconds, trackingContext? }` | `TIMER_STARTED { activityId, endsAt, liveActivityStatus?, liveActivityReason? }` |
| `CANCEL_TIMER { activityId, reason?, trackingContext? }` | `TIMER_CANCELLED { activityId, reason }` |
| `GET_TIMER_STATE` | `TIMER_STATE { active, activityId?, endsAt? }` |

| Native → Web (broadcast) | When |
|---|---|
| `TIMER_COMPLETED { activityId, completedAt, notified }` | The countdown reached `endsAt`. `notified` is `true` only when the banner was actually delivered or tapped, so `false` always means the web app still owes an in-app completion. |

Rules:

- One timer at a time. `START_TIMER` while one is running cancels the previous one and **broadcasts** `TIMER_CANCELLED { activityId }` for it (no `requestId`) before replying `TIMER_STARTED`, so the persistent listener sees the old timer go away and `request()` still resolves on `TIMER_STARTED`.
- `trackingContext` and `reason` belong to Live Activities; see *Timer, completion and account messages* under *v2 — Live Activities*.
- The 33-minute cap is enforced by the web app; native accepts any finite `durationSeconds > 0`. Missing `activityId`, `activityName` or a non-positive duration replies `ERROR { code: "invalid_timer" }`.
- `CANCEL_TIMER` is idempotent: with no timer running it still replies `TIMER_CANCELLED`. If a *different* activity's timer is running it replies `ERROR { code: "timer_not_active" }` and leaves that timer alone.
- `endsAt` is ISO 8601. The web app must derive its display from it rather than from its own `setInterval`, which stops when the app is backgrounded.
- Web calls `GET_TIMER_STATE` after every `NATIVE_READY` so a reload mid-timer picks the countdown back up. The timer is persisted natively, so it also survives an app relaunch; a timer that expired while the app was not running completes on the next launch and `TIMER_COMPLETED` is delivered from the durable event queue before `TIMER_STATE { active: false }`.
- Native schedules a local notification at `endsAt` with identifier `timer-<activityId>`. When the app returns to the foreground before `endsAt`, the notification stays scheduled. When the app is active at `endsAt`, native cancels the notification and emits `TIMER_COMPLETED { notified: false }` so the web app runs the in-app celebration instead.
- `notified: true` means the banner really reached the person: either they tapped it, or it is still sitting in Notification Center when the app next reconciles. Authorisation alone is not enough — a Focus mode or a permission withdrawn mid-timer leaves nothing on screen — so a granted permission with no delivered banner still reports `notified: false` and the web app must celebrate in-app.
- The first `START_TIMER` ever triggers the notification permission prompt (after the reply). While that prompt — or any other system alert — is up the app counts as inactive, so a timer expiring underneath it completes on dismissal rather than in-app.

---

## v2 — completion, sound and notifications

| Web → Native | Reply |
|---|---|
| `ACTIVITY_COMPLETED { activityId, source, scope?, contractId?, healthDay?, completedAt? }` | `ACTIVITY_COMPLETION_ACCEPTED` |
| `SET_SOUND_ENABLED { enabled }` | `SOUND_STATE { enabled }` |
| `GET_NOTIFICATION_STATUS` | `NOTIFICATION_STATUS { authorized, undetermined }` |
| `OPEN_NOTIFICATION_SETTINGS` | `NOTIFICATION_STATUS { authorized, undetermined, opened }` |

- `source` is `"timer"`, `"healthkit"` or `"manual"`. Web sends this whenever a contract is marked honoured from its side, so native can mark `(activityId, today)` as celebrated and skip its own background notification for it. The optional fields tell a Live Activity that the contract, or one slot, is done; see *v2 — Live Activities*.
- `enabled` mirrors the "Completion sound" setting, default `false`. It decides whether the timer and goal notifications carry the gong sound. The in-app gong is played by the web app; native only sets the audio session to `.ambient` so the hardware silent switch is respected.
- `enabled` must be a JSON boolean; a number or string replies `ERROR { code: "invalid_sound_state" }`. Native persists it, so send it on every change and once after `NATIVE_READY` so a reinstalled shell catches up with the account's setting.
- `SOUND_STATE` also carries `gongBundled`: `false` means the approved gong asset is not in this build and an enabled setting falls back to the system default sound. Off means no sound and no vibration on the notification.
- Toggling while a timer is counting down re-registers the pending notification with the new sound; `endsAt` does not change.
- **Web-side gong must use Web Audio (`AudioContext`), not an `<audio>` element.** WebKit picks the iOS audio session category from what the page plays: Web Audio keeps the ambient category native set at launch, an audible `<audio>`/`<video>` element switches the session to playback, which ignores the silent switch. Create or resume the `AudioContext` in the tap that starts the timer (iOS requires a user gesture) and reuse it at completion.

| Native → Web (broadcast) | When |
|---|---|
| `NOTIFICATION_OPENED { kind, activityId }` | The user tapped a notification. `kind` is `"timer"` or `"goal"`. Queued on cold start and delivered after `NATIVE_READY`. The web app navigates to that activity. |

Native asks for notification permission the first time `START_TIMER` or `SET_GOALS` with a non-empty list arrives, not at launch. The request is made after the reply to that message has gone out, so the web app's request timeout is not affected by how long the user looks at the sheet. Native never re-prompts: once the user has decided, a later denial can only be changed in Settings → Notifications.

`GET_NOTIFICATION_STATUS` and `OPEN_NOTIFICATION_SETTINGS` exist so a declined permission is not a dead end. `authorized` says whether banners can be shown; `undetermined` says the person has not been asked yet, so the next timer or goal list will prompt. Both `false` means they declined: the only way back is `OPEN_NOTIFICATION_SETTINGS`, which opens this app's page in iOS Settings and replies with `opened: false` if the system refused to open it. The reply carries the status read before leaving the app, so the web app should ask again on the next `NATIVE_READY` rather than assume the person changed the switch. Nothing here reveals more than iOS allows, and neither message prompts.

Both are iOS-only, like the Testament Timer and goal notifications; the Android shell implements neither and replies `ERROR { code: "not_implemented" }`.

Notifications that fire while the app is in the foreground are not shown. The owning feature emits its bridge event (`TIMER_COMPLETED` / `GOAL_REACHED` with `notified: false`) and the web app runs the in-app celebration.

---

## v2 — Sign in with Apple

| Web → Native | Reply |
|---|---|
| `SIGN_IN_WITH_APPLE` | `APPLE_SIGN_IN_SUCCESS` or `APPLE_SIGN_IN_FAILED { code, message }` |

```json
{
  "type": "APPLE_SIGN_IN_SUCCESS",
  "payload": {
    "identityToken": "eyJ…",
    "rawNonce": "b3f9…",
    "authorizationCode": "c1d2…",
    "user": { "id": "001234.abcd…", "email": "…", "fullName": "…" }
  }
}
```

- `email` and `fullName` are only present on the very first authorization for this Apple ID; store them then or never. Absent keys mean "not provided" — native never sends empty strings. `authorizationCode` is present whenever Apple returns one.
- `code` in the failure event is `"cancelled"` (the person dismissed the sheet) or `"failed"` (anything else, including a device with no Apple Account signed in, or a second `SIGN_IN_WITH_APPLE` sent while the sheet is already up — one request at a time). `message` is Apple's localized description and is safe to show.
- Native generates a 32-byte random nonce (64 hex characters), sends its SHA-256 hex digest to Apple and returns the raw value as `rawNonce`. The web app passes `identityToken` and `rawNonce` to Supabase unchanged.
- **Linking must preserve the anonymous user.** The web app calls `supabase.auth.linkIdentity({ provider: "apple", token: identityToken, nonce: rawNonce })` for the current anonymous session, not `signInWithIdToken`, otherwise Supabase creates a new user and every synced HealthKit row becomes orphaned. This ID-token form of `linkIdentity` requires **Manual linking** to be enabled under Auth → Providers in the Supabase project. After linking, send `SET_AUTH_SESSION` again with the new tokens.
- Use a long request timeout (the purchase timeout is fine): the person may sit on the sheet.

| Native → Web (broadcast) | When |
|---|---|
| `APPLE_CREDENTIAL_REVOKED { userId, reason }` | Apple reports the stored Apple user as `revoked` or `not_found`, checked at every launch and via `credentialRevokedNotification` while running. `userId` is the Apple user identifier (`user.id` from the success payload), not the Supabase user. The web app decides what this means for the account (typically sign out and show the sign-in wall); native only forgets the Apple user. Not persisted across relaunches. |

Native remembers the Apple user identifier after a successful authorization so it can perform that check; `CLEAR_AUTH_SESSION` and a `SET_AUTH_SESSION` for a different user forget it.

---

## Google Sign-In (iOS and Android)

Native only obtains a Google ID token through the platform's own UI. The web app verifies it with Supabase and owns the session: a native success means "Google returned a credential", never "Honoured is signed in". Both shells implement the same messages over a trusted transport. Android does this without moving to bridge v2 (it stays at `bridgeVersion: 1`), so the web app must feature-detect on the capability, never on `bridgeVersion`.

### Capability

`NATIVE_READY` and `PLATFORM_INFO` carry, next to any other capability:

```json
{
  "capabilities": {
    "googleSignIn": {
      "protocolVersion": 1,
      "supported": true,
      "configured": true,
      "transport": "trusted-auth-v1",
      "intents": ["sign_in", "link"]
    }
  }
}
```

- `supported` means the shell and its transport can run the flow. On Android it is `false` when the installed WebView lacks `WEB_MESSAGE_LISTENER`; there is no fallback to a weaker transport.
- `configured` means the public client IDs in this build are present and well formed. It does not prove that Google Cloud or Supabase are set up.
- No `googleSignIn` key (an older shell): hide every Google entry point. Never fall back to OAuth inside the WebView.

### Transport

| Shell | Web → Native | Native → Web |
|---|---|---|
| iOS | `window.webkit.messageHandlers.honouredNative.postMessage({...})`, as for every other message | the `honoured:native` event |
| Android | `window.HonouredAuth.postMessage(JSON.stringify({...}))` (AndroidX `WebMessageListener`) | a `message` event on `window.HonouredAuth`; `event.data` is the same JSON string `{ bridgeVersion, type, payload }`. The web adapter re-dispatches it as `honoured:native`. |

Native accepts the auth messages below only from the **main frame** whose origin exactly equals the configured web app origin (scheme, host and port; no wildcard). Anything else is dropped without a reply. On Android, `HonouredAuth` is injected only into frames of that origin, and the legacy `HonouredNative` (`addJavascriptInterface`) interface answers these message types with `ERROR { code: "insecure_transport" }`. Replies go only to the document that asked: iOS checks the page generation and origin before dispatching, and Android replies through that frame's own `JavaScriptReplyProxy`.

### Messages

| Web → Native | Reply |
|---|---|
| `SYNC_AUTH_CONTEXT { requestId, userId: string \| null }` | `AUTH_CONTEXT_SYNCED { authContextId, userId }` |
| `SIGN_IN_WITH_GOOGLE { requestId, intent: "sign_in" \| "link", authContextId }` | `GOOGLE_SIGN_IN_SUCCESS` or `GOOGLE_SIGN_IN_FAILED` |
| `CANCEL_GOOGLE_SIGN_IN { requestId, authContextId, targetRequestId }` | `GOOGLE_SIGN_IN_CANCEL_ACCEPTED { targetRequestId, cancelled }` |
| `CLEAR_GOOGLE_SIGN_IN { requestId, authContextId }` | `GOOGLE_SIGN_IN_CLEARED { authContextId, providerCleared, warningCode? }` |

**Auth context.** The web app sends `SYNC_AUTH_CONTEXT` after the page is ready and every time the signed-in Supabase user changes, including sign-out (`userId: null`). Native answers with an `authContextId` it generated. The id lives in memory only and carries no token; it only tells native which document and which owner a later Google request belongs to. Rules:

- The same user on the same page gets the same id back.
- A different user, a new page (any main-frame navigation or reload) and `CLEAR_GOOGLE_SIGN_IN` each produce a new id and invalidate every attempt of the old one.
- On iOS, `SET_AUTH_SESSION` for a user other than the context's owner, and `CLEAR_AUTH_SESSION`, invalidate the context as well. A token refresh for the same user keeps it, so a link flow in progress survives.

**Sign-in request.**

- `sign_in` requires a context whose `userId` is `null`; `link` requires a signed-in one.
- Native generates a 32-byte random nonce and sends its SHA-256 hex digest to Google. The success reply returns the raw value; the web app passes it to Supabase unchanged.

```json
{
  "type": "GOOGLE_SIGN_IN_SUCCESS",
  "payload": {
    "requestId": "gsi-1",
    "intent": "sign_in",
    "authContextId": "…",
    "idToken": "eyJ…",
    "rawNonce": "9f2c…",
    "accessToken": "ya29…"
  }
}
```

`accessToken` is present on iOS only. Pass it as `access_token` only when it is present, never as an empty string.

`GOOGLE_SIGN_IN_FAILED { requestId, authContextId, code, message }` codes:

| Code | Meaning |
|---|---|
| `cancelled` | The person closed the Google UI, or the web app cancelled the attempt. |
| `in_progress` | Another Google or Apple presentation, or a Google cleanup, is still running. |
| `not_configured` | Public client IDs missing or malformed in this build. |
| `unsupported` | This device or WebView cannot run the flow (for example, no Google Play services). |
| `invalid_payload` | Missing or bad fields, a reused `requestId`, or an intent that does not match the context. |
| `stale_context` | The context was replaced (page reload, owner change, clear) before or during the attempt. |
| `no_credential` | No Google account is available on the device. |
| `network_error` | No network. |
| `provider_error` | Anything else Google reported. |
| `timeout` | No result within 120 s. |

`message` is safe to show and never contains token material.

**Lifecycle.**

- One Google presentation at a time. On iOS, Apple and Google also share one lock.
- A request produces at most one result, and a credential is never sent twice.
- Timeout, cancel, a reload or an owner change invalidate the attempt. Its late result is dropped, and native sends nothing to a document it no longer trusts.
- Credentials never enter the event queue, the durable store, saved state or logs. They are not replayed on `NATIVE_READY`.
- A process restart forgets every attempt and nonce.

**Clear.** `CLEAR_GOOGLE_SIGN_IN` is part of sign-out and is idempotent.

1. Native invalidates the current context and its attempts at once.
2. It signs the Google SDK out: iOS `GIDSignIn.signOut()`, Android `CredentialManager.clearCredentialState`.
3. It replies with a fresh signed-out `authContextId`.

This does not revoke Google access or touch other devices. New Google requests get `in_progress` until the cleanup has finished. `providerCleared: false` with a `warningCode` reports a cleanup error; the sign-out itself still stands.

### Rules for the web app

- **`sign_in`:** `supabase.auth.signInWithIdToken({ provider: "google", token: idToken, nonce: rawNonce, access_token? })`.
- **`link`:** `supabase.auth.linkIdentity({ provider: "google", token: idToken, nonce: rawNonce, access_token? })` with the current session. The user id must be the same before and after.
  - This needs **Manual linking** enabled in Supabase.
  - A Google identity that already belongs to another account is a conflict. Keep the current session; never fall back to sign-in and never merge accounts.
- **Accepting a reply:** only while the request, page, context, intent and current user still match. The token is used once.
- **After Supabase accepts the session**, and only then:
  - resync the context;
  - send `SET_AUTH_SESSION` (iOS);
  - send `IDENTIFY_USER { userId: <Supabase user id> }`, never the Google subject or email.
- **Sign-out order:**
  1. Invalidate the local intent.
  2. Sign out of Supabase with `scope: "local"`.
  3. Send `SYNC_AUTH_CONTEXT { userId: null }` and `CLEAR_GOOGLE_SIGN_IN`.
  4. Send the existing native clears.

---

## v2 — Live Activities (iOS 16.2+)

One Live Activity (a "card") per tracked contract occurrence — one contract on one health day — on the Lock Screen and in the Dynamic Island. The contract the person most recently opened or started leads: native gives it relevance score 100 and every other card a lower one, in order of selection. That is a request to iOS, not a guaranteed place in the Dynamic Island when other apps have activities too. Opening another contract never ends a card or cancels a timer, and every card keeps updating whether it leads or not.

### Capability

`NATIVE_READY` (the `APP_READY` reply and the broadcast after each page load) and `PLATFORM_INFO` carry:

```json
{
  "platform": "ios",
  "bridgeVersion": 2,
  "capabilities": {
    "liveActivities": { "protocolVersion": 1, "supported": true, "enabled": true, "minimumOS": "16.2" }
  },
  "liveActivityBridgeSessionId": "3F1C0B2E-…"
}
```

- No `capabilities.liveActivities` (an older shell, Android): do not send the messages below. Android answers them with `ERROR { code: "not_implemented" }` anyway.
- `supported: false` (iOS 16.0–16.1): the timer, Health and notifications work as before. Mutations reply `ERROR { code: "live_activities_unsupported" }`; `START_TIMER` with a tracking context still starts the timer and replies `liveActivityStatus: "unsupported"`.
- `enabled` is the Live Activities switch for Honoured at that moment. It says nothing about notification or Health permission. A card requested while it is off is `disabled` and is created on the next foreground once the switch is on.

### Session, sequence and retries

Every mutation carries an envelope:

| Field | |
|---|---|
| `requestId` | Required. Echoed in the reply. |
| `bridgeSessionId` | The latest `liveActivityBridgeSessionId` native gave this page. |
| `clientSequence` | Positive integer, strictly increasing within the session, assigned when the person acts — not when a fetch finishes. |

`bridgeSessionId` changes whenever a new page replaces the current one (a navigation that fails leaves the page and its id in place), on `CLEAR_AUTH_SESSION` and when `SET_AUTH_SESSION` names a different user; a token refresh for the same user keeps it. The current value comes back in `NATIVE_READY`/`PLATFORM_INFO`, `AUTH_SESSION_ACCEPTED`, `AUTH_SESSION_CLEARED` and `LIVE_ACTIVITY_STATE`. A new page is not bound to an account until its first `SET_AUTH_SESSION`, so send mutations only after `AUTH_SESSION_ACCEPTED`, with the id from that reply, one at a time in `clientSequence` order.

Native checks the envelope when the message arrives, before any asynchronous work:

- Same `requestId` and `clientSequence` as an earlier message of this session: the first reply is sent again and nothing is repeated. This is how a transport retry is handled; a retried `START_TIMER` never starts a second run.
- Same `requestId`, different sequence: `request_id_reused`.
- `clientSequence` not greater than the last accepted one: `stale_sequence`.
- A session id that is not the current one: `stale_bridge_session`. No `SET_AUTH_SESSION` on this page yet: `auth_session_required`.

A request answered with an error is a finished attempt. After fixing the cause — for example sending `SET_GOALS` after `goal_definition_mismatch` — use a new `requestId` and a new sequence. In every Live Activity field a JSON `null` means the same as leaving the field out.

Native orders work by arrival, never by clocks. Focus follows the order of `TRACK_CONTRACT` and `START_TIMER` messages even if the device clock changes, and Health reads, timer events and ActivityKit callbacks that belong to an earlier account, definition or timer run are dropped when they come back.

### Contract definition

```json
{
  "contractId": "contract-walk",
  "contractName": "Morning Walk",
  "healthDay": "2026-09-23",
  "expiresAt": "2026-09-24T00:00:00+07:00",
  "timerActivityId": "contract-walk",
  "completionPolicy": { "kind": "all_health_slots", "requiredActivityIds": ["contract-walk:primary"] },
  "activities": [
    { "activityId": "contract-walk:primary", "slot": "primary", "name": "Walking", "mode": "health",
      "metric": "steps", "target": 8000, "unit": "count" }
  ]
}
```

| Field | Rules |
|---|---|
| `contractId` | 1–128 printable characters. Opaque: native infers nothing from it. |
| `contractName`, `activities[].name` | Display text. Whitespace collapses to one line; beyond 80 (contract) or 60 (activity) characters it is cut with "…". |
| `healthDay` | `yyyy-MM-dd` and native's current health day under the reset hour; otherwise `health_day_mismatch` with `expectedHealthDay`. |
| `expiresAt` | ISO 8601 with an offset, in the future (`occurrence_expired`). Use the contract's `deadline`. |
| `activities` | One or two, with unique `activityId` and unique `slot` (`primary`, `secondary`). `mode` is `health`, `timer` or `manual`. |
| `mode: health` | `metric`, `target` (finite, > 0) and `unit` (the metric's canonical unit) are required and must equal a goal from the latest `SET_GOALS` with the same `activityId`; otherwise `goal_definition_mismatch`. There is only ever one target per activity. Optional `displayUnit`: `km` or `mi`, distance metrics only. |
| `mode: timer`, `mode: manual` | Name only; `metric`, `target` and `unit` are refused. A `timer` activity's `activityId` is the Testament Timer's. At most one. |
| `timerActivityId` | Optional. The `START_TIMER` `activityId` this contract runs under — the web app uses the contract id. Any contract may declare it, so a Health contract with a running timer shows both. Must match the `timer` activity when there is one. Native keeps a timer it learned from `START_TIMER` when a later definition of the same occurrence leaves the field out, so send it every time if you can. |
| `completionPolicy` | See below. An unknown `kind` is refused. |

A completion policy says when native may show the card as honoured and end it by itself. The policies mirror the rules of the deployed web app, checked against the production bundle on 23/09: a contract is honoured when **every** Health-mapped slot is reached on the same health day, when its Testament Timer finishes naturally, or when the person reports it. The web app remains the only place the outcome is recorded; ending a card writes nothing anywhere.

| `kind` | Extra fields | Native ends the card as honoured when |
|---|---|---|
| `all_health_slots` | `requiredActivityIds`: exactly every `health` activity | every required slot has been reached in this occurrence |
| `timer_completion` | `timerActivityId` | native processes the natural finish of that timer, before `expiresAt` |
| `all_health_slots_or_timer` | both | whichever comes first; for a Health contract that can also run the timer |
| `web_authoritative` | — | only on `ACTIVITY_COMPLETED { scope: "contract" }` |

`ACTIVITY_COMPLETED { scope: "contract" }` ends the card as honoured under every policy. One reached slot is progress, never the contract. A slot stays reached for the occurrence even if its total later drops (deleted samples) or its target is raised, like the web app's reached-slot store.

### Messages

| Web → Native | Reply |
|---|---|
| `TRACK_CONTRACT { …envelope, reason: "opened", contract }` | `CONTRACT_TRACKING_ACCEPTED { contractId, healthDay, focused, presentationStatus, reason? }` |
| `SYNC_TRACKED_CONTRACTS { …envelope, contracts: [contract] }` | `TRACKED_CONTRACTS_SYNCED { tracked: [entry] }` |
| `STOP_TRACKING_CONTRACT { …envelope, contractId, healthDay, reason }` | `CONTRACT_TRACKING_STOPPED { contractId, healthDay, reason, stopped: true }` |
| `GET_LIVE_ACTIVITY_STATE` | `LIVE_ACTIVITY_STATE { supported, enabled, liveActivityBridgeSessionId, focusedOccurrence?, tracked: [entry] }` |

An `entry` is `{ contractId, healthDay, presentationStatus, focused, reason?, lastUpdatedAt? }`; `focusedOccurrence` is the card that currently leads.

- **`TRACK_CONTRACT`** — when the person opens a contract, or signs one and lands on it. Records the definition, makes it the latest selection and shows or updates its card; never ends another card. A timer-only contract whose timer is not running is recorded as `awaiting_timer` without an empty card; a contract with nothing measurable reports `pending` with reason `nothing_to_show`. Opening a card the person dismissed brings it back. A finished occurrence stays `ended`.
- **`SYNC_TRACKED_CONTRACTS`** — the full list of occurrences the person tracks, sent once the store has hydrated for the signed-in account, never an empty list while loading. Updates definitions and forgets today's occurrences that are no longer listed (their cards end). It never moves focus, never creates a card for an occurrence nobody opened (`pending`, reason `awaiting_open`) and never brings back one the person dismissed. An invalid entry comes back as `presentationStatus: "failed"` with the error code as `reason`, and its existing record is left alone. An entry without a valid `contractId` and `healthDay`, or more than 20 entries, fails the whole message.
- **`STOP_TRACKING_CONTRACT`** — `reason` is `user_stopped`, `contract_cancelled`, `contract_deleted`, `contract_expired` or `contract_broken`. Ends that occurrence's card at once and is idempotent. It never cancels the timer or any Health business, and must not stand in for a completion.
- **`GET_LIVE_ACTIVITY_STATE`** — read-only, no envelope; never creates or focuses a card. Use it after `NATIVE_READY` to see what native already tracks before building the sync list.

| `presentationStatus` | Meaning |
|---|---|
| `active`, `stale` | A card is up. `stale` means its data is old: no Health reading for 60 minutes, a countdown at zero that the app has not processed, or the day or expiry passed while the app was not running. It says nothing about the contract. |
| `pending` | Tracked without a card: waiting for an explicit open (`awaiting_open`) or nothing to show (`nothing_to_show`). |
| `awaiting_timer` | Timer-only contract; the card appears when its timer runs. |
| `needs_foreground` | iOS creates cards only while the app is in the foreground; retried when it is. |
| `disabled` | Live Activities are off for Honoured; retried on the next foreground. |
| `limit_reached` | iOS refused another card. Other cards are untouched and nothing retries in a loop; the next explicit open tries again. |
| `dismissed` | The person swiped it away, or it disappeared while the app was not running. Only an explicit open or start brings it back. |
| `ended` | `reason` is `completed`, `expired` or `day_ended`, which are final for the occurrence; or `system_ended` when iOS ended the card at its time limit, which, like `dismissed`, only an explicit open or start can replace. |
| `failed` | `payload_too_large`, `activitykit_error`, `unsupported`, or a sync entry's error code. |

Presentation problems are statuses, not errors. `ERROR` (with the `requestId`) is reserved for a malformed payload or envelope, the session, the sequence, the account, the health day, goals and expiry: `invalid_envelope`, `stale_bridge_session`, `stale_sequence`, `request_id_reused`, `auth_session_required`, `account_mismatch`, `invalid_contract`, `health_day_mismatch`, `goal_definition_mismatch`, `occurrence_expired`, `invalid_stop`, `live_activities_unsupported`, `store_unavailable`.

| Native → Web (broadcast) | When |
|---|---|
| `LIVE_ACTIVITY_STATE_CHANGED { supported, enabled, focusedOccurrence?, tracked }` | A status, a reason or the leading card changed — including as the result of a mutation, just before its reply. Not sent for new Health numbers. Carries no session id. In memory only: survives a reload, not a relaunch. |
| `LIVE_ACTIVITY_OPENED { eventId, contractId, healthDay }` | The person tapped a card. Durable like `NOTIFICATION_OPENED` and delivered once, after the page is ready. |

### Timer, completion and account messages

- `START_TIMER` may carry `trackingContext: { bridgeSessionId, clientSequence, timerActivityId, contract }`, where `timerActivityId` is the `activityId` being started and the contract's own timer, if it names one, is the same. The envelope is checked **before** the timer is touched. After that the timer always starts; tracking and focus follow once it has. `TIMER_STARTED` adds `liveActivityStatus` (a presentation status, `rejected` for a contract that cannot be tracked, or `unsupported`) and `liveActivityReason?`. Starting timer B still replaces timer A and broadcasts `TIMER_CANCELLED` for A first; A's card drops its timer, keeps its Health and ends if it has nothing else to show.
- `CANCEL_TIMER` may carry `reason: "paused" | "cancelled"` (default `cancelled`, echoed in `TIMER_CANCELLED`; any other value is treated as `cancelled`, never as an error) and `trackingContext: { bridgeSessionId, clientSequence }`. Native has no pause: a pause is a cancel and a resume is a new `START_TIMER` with the remaining time. Either way the card drops the timer, and a timer-only card ends until the timer runs again.
- A `START_TIMER` without a tracking context attaches its run to today's tracked occurrence that declared that timer, without moving focus.
- `ACTIVITY_COMPLETED` may add `scope: "contract" | "slot"`, `contractId`, `healthDay`, `completedAt` and the envelope (`bridgeSessionId`, `clientSequence`). Once any of these is present, `scope`, `contractId`, `healthDay` and the envelope are required. The celebration marker is then set for **that** health day, so a completion that arrives after the reset never silences today's goal. It is set even when the envelope is refused, because the contract is honoured either way and marking twice is harmless. `scope: "contract"` ends the card as honoured; `scope: "slot"` marks that activity reached. A completion for an occurrence of another account is refused with `account_mismatch`. The reply adds `contractId`, `healthDay`, `scope`, `tracked` and `presentationStatus?`. Without these fields the message behaves exactly as before, and nothing about the contract is inferred from `activityId`.
- `SET_AUTH_SESSION` for a different user and `CLEAR_AUTH_SESSION` remove every Honoured card at once — including a finished one still showing its result — and forget the previous account's tracking before anything else is processed. `LOGOUT_USER` is billing only and does not touch Live Activities.

### Timing and limits

- **Countdown.** A card counts down with the system's timer view and stops at zero. The finish counts only when native processes it: in the foreground at the deadline, through the notification, or at the next reconcile (foreground, launch, `GET_TIMER_STATE`). A suspended app cannot end a card on time, so the card sits at zero, stale, until then. The local notification does not depend on the card.
- **Health.** Cards update from source-deduplicated statistics, the same numbers as `health_daily`, after every collection pass, on open and sync, on foreground and when protected data becomes available — not every second, and not while the device is locked and Health data is encrypted. A failed or locked read keeps the last reading, shown as stale after 60 minutes ("Health updated 14:05"); it never becomes zero. A successful read with no data shows "No data yet". Heart rate is the average over the day so far, not a live sensor.
- **Day and expiry.** A card shows one health day. At the reset, or after a reset-hour or time-zone change, its Health part stops and the card ends, unless the Testament Timer it shows is still counting — the timer keeps its original occurrence. A card ends at `expiresAt` without touching the timer. When the app is not running at that moment, this happens the next time it runs.
- **Finished cards** end with their final content and stay on the Lock Screen for 30 seconds. iOS ends any card after 8 hours (it can stay visible up to 4 more); native does not recreate it on its own (`system_ended`).
- **Deep link.** A card opens `honoured://contract/<id>?day=<healthDay>&occurrence=<token>`. Only a token from the signed-in account's own records produces `LIVE_ACTIVITY_OPENED`; anything else just opens the app. The tap changes no business state.

### Integration notes for the web app

- Add the messages above to `src/lib/native-bridge.ts` and gate everything on `capabilities.liveActivities.supported`.
- Keep `liveActivityBridgeSessionId` from `AUTH_SESSION_ACCEPTED` and `AUTH_SESSION_CLEARED`, restart the sequence when it changes, and hold mutations while a `SET_AUTH_SESSION` is in flight.
- `SET_GOALS` currently carries the goals of the first active contract only. Every tracked contract's Health slots must be in it: send the goals of all active contracts, and wait for `GOALS_ACCEPTED` before the `TRACK_CONTRACT` or `SYNC_TRACKED_CONTRACTS` that relies on it.
- On opening a contract, `TRACK_CONTRACT`. On Start, `START_TIMER` with `trackingContext`. After hydration, `GET_LIVE_ACTIVITY_STATE` then `SYNC_TRACKED_CONTRACTS`. When a contract is honoured, `ACTIVITY_COMPLETED` with `scope: "contract"`; when it is broken, deleted, expired or rolled over, `STOP_TRACKING_CONTRACT` with the matching reason.
- Choose `completionPolicy` per contract: `all_health_slots_or_timer` for a Health contract (any contract can start the timer), `timer_completion` for one without Health slots, `web_authoritative` when unsure.
- Buffer `LIVE_ACTIVITY_OPENED` until auth and the router are ready, dedupe it by `eventId`, and route an unknown or finished contract to a safe screen.
- The deployed web app allows one active contract at a time, so several cards at once also need several active contracts on the web side.

---

## Message index

Web → Native: `APP_READY` `GET_PLATFORM_INFO` `IDENTIFY_USER` `LOGOUT_USER` `CHECK_ACCESS` `START_PURCHASE` `RESTORE_PURCHASES` `START_SESSION` `SET_AUTH_SESSION` `CLEAR_AUTH_SESSION` `REQUEST_HEALTH_PERMISSION` `GET_HEALTH_STATUS` `QUERY_HEALTH_METRICS` `SET_GOALS` `SET_DAY_RESET_HOUR` `START_TIMER` `CANCEL_TIMER` `GET_TIMER_STATE` `ACTIVITY_COMPLETED` `SET_SOUND_ENABLED` `GET_NOTIFICATION_STATUS` `OPEN_NOTIFICATION_SETTINGS` `SIGN_IN_WITH_APPLE` `SYNC_AUTH_CONTEXT` `SIGN_IN_WITH_GOOGLE` `CANCEL_GOOGLE_SIGN_IN` `CLEAR_GOOGLE_SIGN_IN` `TRACK_CONTRACT` `SYNC_TRACKED_CONTRACTS` `STOP_TRACKING_CONTRACT` `GET_LIVE_ACTIVITY_STATE`

Native → Web: `NATIVE_READY` `PLATFORM_INFO` `ERROR` `IDENTIFY_SUCCESS` `IDENTIFY_FAILED` `LOGOUT_SUCCESS` `LOGOUT_FAILED` `ACCESS_STATUS` `PURCHASE_SUCCESS` `PURCHASE_CANCELLED` `PURCHASE_FAILED` `RESTORE_SUCCESS` `RESTORE_FAILED` `AUTH_SESSION_ACCEPTED` `AUTH_SESSION_CLEARED` `AUTH_SESSION_UPDATED` `AUTH_SESSION_INVALID` `HEALTH_PERMISSION_STATUS` `HEALTH_METRICS` `GOALS_ACCEPTED` `DAY_RESET_HOUR_ACCEPTED` `GOAL_REACHED` `HEALTH_DATA_UPDATED` `TIMER_STARTED` `TIMER_CANCELLED` `TIMER_STATE` `TIMER_COMPLETED` `ACTIVITY_COMPLETION_ACCEPTED` `SOUND_STATE` `NOTIFICATION_STATUS` `NOTIFICATION_OPENED` `APPLE_SIGN_IN_SUCCESS` `APPLE_SIGN_IN_FAILED` `APPLE_CREDENTIAL_REVOKED` `AUTH_CONTEXT_SYNCED` `GOOGLE_SIGN_IN_SUCCESS` `GOOGLE_SIGN_IN_FAILED` `GOOGLE_SIGN_IN_CANCEL_ACCEPTED` `GOOGLE_SIGN_IN_CLEARED` `CONTRACT_TRACKING_ACCEPTED` `TRACKED_CONTRACTS_SYNCED` `CONTRACT_TRACKING_STOPPED` `LIVE_ACTIVITY_STATE` `LIVE_ACTIVITY_STATE_CHANGED` `LIVE_ACTIVITY_OPENED`

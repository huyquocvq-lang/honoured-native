# Honoured Native Bridge v2

The native shell hosts `https://honour-your-word.lovable.app` inside a WebView and exposes a small, whitelisted message bridge. v2 adds HealthKit, timers, notifications, auth session hand-off and Sign in with Apple. Every v1 message keeps working unchanged.

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

**Event queue.** Some events originate while the WebView is not ready — a notification tapped on cold start, a goal reached during a background sync, a session refreshed in the background. Native buffers these and flushes them in order immediately after replying `NATIVE_READY` to `APP_READY`. The buffer is bounded (last 50) and survives a WebView reload but not an app relaunch.

All platform-specific capabilities must be invoked through an explicit message type. Do not expose a generic native method executor to the WebView.

---

## v1 — foundation and billing (unchanged)

| Web → Native | Reply |
|---|---|
| `APP_READY` | `NATIVE_READY { platform, bridgeVersion }` then any queued events |
| `GET_PLATFORM_INFO` | `PLATFORM_INFO { platform, bridgeVersion }` |
| `IDENTIFY_USER { userId }` | `IDENTIFY_SUCCESS` or `IDENTIFY_FAILED { message }`, followed by `ACCESS_STATUS` when a verdict is available |
| `LOGOUT_USER` | `LOGOUT_SUCCESS` then `ACCESS_STATUS { isSubscribed: false, source: "logout" }` |
| `CHECK_ACCESS { userId }` | `ACCESS_STATUS { isSubscribed, entitlement?, source }` |
| `START_PURCHASE { userId, packageIdentifier? }` | `PURCHASE_SUCCESS` / `PURCHASE_CANCELLED` / `PURCHASE_FAILED`, success followed by `ACCESS_STATUS` |
| `RESTORE_PURCHASES { userId }` | `RESTORE_SUCCESS` / `RESTORE_FAILED`, success followed by `ACCESS_STATUS` |
| `START_SESSION` | `ERROR` — trial sessions are enforced by Supabase RPC from the web app |

See `docs/billing.md` for RevenueCat details.

---

## v2 — auth session

Native writes HealthKit data to Supabase under row-level security, so it needs the signed-in user's session. The web app owns the session while it is in the foreground; native only refreshes on its own when it wakes in the background and the WebView is not running.

| Web → Native | Reply |
|---|---|
| `SET_AUTH_SESSION { userId, accessToken, refreshToken, expiresAt }` | `AUTH_SESSION_ACCEPTED { userId }` |
| `CLEAR_AUTH_SESSION` | `AUTH_SESSION_CLEARED` |

| Native → Web (broadcast) | When |
|---|---|
| `AUTH_SESSION_UPDATED { accessToken, refreshToken, expiresAt }` | Native refreshed the token in the background. Web must call `supabase.auth.setSession()` with these values. |
| `AUTH_SESSION_INVALID { reason }` | Refresh failed. Web should re-authenticate and send a fresh `SET_AUTH_SESSION`. |

Rules:

- Web sends `SET_AUTH_SESSION` on `SIGNED_IN`, `TOKEN_REFRESHED` and `INITIAL_SESSION` from supabase-js, including for anonymous users. This is the only way native learns who to sync for.
- `expiresAt` is Unix seconds.
- Native stores the pair in the Keychain and never logs it.
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

Web owns contract state: on `GOAL_REACHED` it marks the contract honoured and runs the in-app celebration if the app is in the foreground.

---

## v2 — Testament Timer

Timers must survive backgrounding, so native owns the countdown and the completion notification. The web app renders the countdown but takes its clock from `endsAt`.

| Web → Native | Reply |
|---|---|
| `START_TIMER { activityId, activityName, durationSeconds }` | `TIMER_STARTED { activityId, endsAt }` |
| `CANCEL_TIMER { activityId }` | `TIMER_CANCELLED { activityId }` |
| `GET_TIMER_STATE` | `TIMER_STATE { active, activityId?, endsAt? }` |

| Native → Web (broadcast) | When |
|---|---|
| `TIMER_COMPLETED { activityId, completedAt, notified }` | The countdown reached `endsAt`. `notified` is `true` if a local notification was posted because the app was not active. |

Rules:

- One timer at a time. `START_TIMER` while one is running cancels the previous one and replies `TIMER_CANCELLED` for it first.
- The 33-minute cap is enforced by the web app; native accepts any `durationSeconds > 0`.
- `endsAt` is ISO 8601. The web app must derive its display from it rather than from its own `setInterval`, which stops when the app is backgrounded.
- Web calls `GET_TIMER_STATE` after every `NATIVE_READY` so a reload mid-timer picks the countdown back up.
- Native schedules a local notification at `endsAt` with identifier `timer-<activityId>`. When the app returns to the foreground before `endsAt`, the notification stays scheduled. When the app is active at `endsAt`, native cancels the notification and emits `TIMER_COMPLETED { notified: false }` so the web app runs the in-app celebration instead.

---

## v2 — completion, sound and notifications

| Web → Native | Reply |
|---|---|
| `ACTIVITY_COMPLETED { activityId, source }` | `ACTIVITY_COMPLETION_ACCEPTED` |
| `SET_SOUND_ENABLED { enabled }` | `SOUND_STATE { enabled }` |

- `source` is `"timer"`, `"healthkit"` or `"manual"`. Web sends this whenever a contract is marked honoured from its side, so native can mark `(activityId, today)` as celebrated and skip its own background notification for it. In M3 this is also what drives the Live Activity blink.
- `enabled` mirrors the "Completion sound" setting, default `false`. It decides whether the timer and goal notifications carry the gong sound. The in-app gong is played by the web app; native only sets the audio session to `.ambient` so the hardware silent switch is respected.

| Native → Web (broadcast) | When |
|---|---|
| `NOTIFICATION_OPENED { kind, activityId }` | The user tapped a notification. `kind` is `"timer"` or `"goal"`. Queued on cold start and delivered after `NATIVE_READY`. The web app navigates to that activity. |

Native asks for notification permission the first time `START_TIMER` or `SET_GOALS` with a non-empty list arrives, not at launch.

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

- `email` and `fullName` are only present on the very first authorization for this Apple ID; store them then or never.
- `code` in the failure event is `"cancelled"` or `"failed"`.
- Native generates the nonce, hashes it with SHA-256 for the Apple request and returns the raw value. The web app passes `identityToken` and `rawNonce` to Supabase.
- **Linking must preserve the anonymous user.** The web app calls `supabase.auth.linkIdentity` for the current anonymous session, not `signInWithIdToken`, otherwise Supabase creates a new user and every synced HealthKit row becomes orphaned. After linking, send `SET_AUTH_SESSION` again with the new tokens.

---

## Message index

Web → Native: `APP_READY` `GET_PLATFORM_INFO` `IDENTIFY_USER` `LOGOUT_USER` `CHECK_ACCESS` `START_PURCHASE` `RESTORE_PURCHASES` `START_SESSION` `SET_AUTH_SESSION` `CLEAR_AUTH_SESSION` `REQUEST_HEALTH_PERMISSION` `GET_HEALTH_STATUS` `QUERY_HEALTH_METRICS` `SET_GOALS` `SET_DAY_RESET_HOUR` `START_TIMER` `CANCEL_TIMER` `GET_TIMER_STATE` `ACTIVITY_COMPLETED` `SET_SOUND_ENABLED` `SIGN_IN_WITH_APPLE`

Native → Web: `NATIVE_READY` `PLATFORM_INFO` `ERROR` `IDENTIFY_SUCCESS` `IDENTIFY_FAILED` `LOGOUT_SUCCESS` `LOGOUT_FAILED` `ACCESS_STATUS` `PURCHASE_SUCCESS` `PURCHASE_CANCELLED` `PURCHASE_FAILED` `RESTORE_SUCCESS` `RESTORE_FAILED` `AUTH_SESSION_ACCEPTED` `AUTH_SESSION_CLEARED` `AUTH_SESSION_UPDATED` `AUTH_SESSION_INVALID` `HEALTH_PERMISSION_STATUS` `HEALTH_METRICS` `GOALS_ACCEPTED` `DAY_RESET_HOUR_ACCEPTED` `GOAL_REACHED` `HEALTH_DATA_UPDATED` `TIMER_STARTED` `TIMER_CANCELLED` `TIMER_STATE` `TIMER_COMPLETED` `ACTIVITY_COMPLETION_ACCEPTED` `SOUND_STATE` `NOTIFICATION_OPENED` `APPLE_SIGN_IN_SUCCESS` `APPLE_SIGN_IN_FAILED`

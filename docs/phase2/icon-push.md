# Icon push (V1.2 M2-06, M2-07)

The Icon card (`icon-live-activity.md`) opens at the morning reminder, turns to
the evening line, shows HONOURED and closes at the cut-off without the app
running. Parts:

| Part | Where |
|---|---|
| Token registration (M2-06) | iOS `Notifications/PushTokenRegistry.swift`, `PushTokenSupport.swift` |
| Tokens and send log | `docs/db/icon_push_v1.sql`, `docs/db/icon_push_v1_1.sql` |
| Sender (M2-07) | the database: `docs/db/icon_push_v2.sql`, `icon_push_v3.sql`, `icon_push_v4.sql`, `icon_push_v5.sql` (`icon_push_tick`, `icon_push_plan`, pg_net) |
| Provider token | web app route `/api/internal/apns-token` (`src/lib/apns-token.server.ts`); local copy in `docs/phase2/icon-push/web/` |
| Decisions, reference | `docs/phase2/icon-push/plan.ts` with `plan_test.ts` (Deno) and `parity_fixtures.ts` |
| Schedule | pg_cron job `icon-push`, every minute |

Why the database sends: the Lovable project cannot host a Supabase Edge
Function, APNs only speaks HTTP/2, and pg_net does (checked Oct 4). Postgres
cannot sign the ES256 provider token, so the web app's server route signs it
and stores it; the web runtime already signs ES256 for Sign in with Apple.

## Tokens (M2-06)

Each install registers, under the signed-in session, through
`register_push_token`:

- `device`: the APNs device token, for the fallback notification;
- `push_to_start`: ActivityKit's push-to-start token (iOS 17.2+);
- `activity`: the update token of each Icon card, keyed by contract
  (`client_id`) and Icon day. Cards the app starts itself are requested with
  `pushType: .token`, so they have one too.

Rows also carry the gateway (`sandbox` for builds whose embedded provisioning
profile says `aps-environment = development`, and the simulator; otherwise
`production`), the bundle id, the iOS version and whether Live Activities are
on. The app sends a token again when anything in that row changes, when the
session changes and once a day.

An install is identified by a random id kept in the Keychain for this device
only (it survives a reinstall, not a backup restore onto another phone). An
install belongs to one account: registering for another account removes the
previous account's rows, and a token belongs to the install that registered it
last. After sign-out clears the session, or an account switch stores the new
one, the app calls `unregister_push_tokens` with the id, as anon, before it
registers anything again; offline, it retries before its next registration.
Tables are readable only by their owner; only the database job sees all of
them.

## What is sent (M2-07)

Every minute `icon_push_tick()`:

1. reads the replies to earlier requests (`net._http_response`) and logs each
   slot once all its requests have one;
2. checks the provider token and, when it is 40 minutes old, asks the web app
   for a new one (`icon_push_request_token`, at most every 5 minutes);
3. lists due slots (`icon_push_jobs`), decides per install
   (`icon_push_plan`) and queues one pg_net request per send
   (`icon_push_sends`).

| Slot | Due | Card token | No card token, push-to-start | Neither (or Live Activities off) |
|---|---|---|---|---|
| morning | morning reminder, pending day | nothing (the app opened the card) | start the card, morning line, stale at the evening reminder | quiet notification |
| evening | evening reminder, pending day | with push-to-start: close it and start a fresh card on the evening line; without: update it, with alert | start the card on the evening line | quiet notification |
| result | day HONOURED before the cut-off | update to HONOURED, no alert | nothing | nothing |
| end | cut-off passed | end, dismissed at once | nothing | nothing |
| renew-… | an install's card is 7 h 40 min old and would run out before the cut-off, no evening card first | with push-to-start: close it and start a fresh card on the day as it stands, alert repeating its line | start a fresh card | nothing (an update cannot extend the 8 hours) |

- The evening card is a fresh card because iOS ends a Live Activity 8 hours
  after it starts: with 07:00 and 20:00 reminders the morning card is gone by
  the evening (`icon_push_v3.sql`). Closing the morning card is housekeeping
  (`icon_push_sends.auxiliary`); only the start decides whether the slot was
  sent.
- Renewal (`icon_push_v5.sql`, client Oct 6): iOS ends a Live Activity 8 hours
  after it starts. A card dates from when its update token first arrived
  (`push_tokens.token_since`, kept when the same token is registered again) or
  when this job started it, whichever is later; the slot is
  `renew-<that start in Unix seconds>`, so each card is renewed once. Apple
  requires an alert to start a card by push ("Include an alert in the JSON
  payload"), so a renewal lights the phone briefly, without sound. The app
  renews cards itself whenever it is open, which moves the server's renewal on.
- A morning or evening reminder is sent only within 15 minutes of its time, an
  end within 15 minutes of the cut-off, so a late run never sends stale
  reminders.
- `icon_push_log` gets one row per slot: `sent` if any install got it,
  `skipped` when nothing could be sent, `failed` for an answer a retry cannot
  change (for example `BadTopic`). APNs 5xx, 429, timeouts and requests with no
  reply after 10 minutes are sent again on the next tick. 410, `BadDeviceToken`
  and `Unregistered` delete the token, and the slot is planned again with what
  is left. `ExpiredProviderToken` and `InvalidProviderToken` pause sending until
  a new provider token arrives, never sooner than 20 minutes after the last one.
- Live Activity JSON: `attributes-type` `IconActivityAttributes`, attributes
  `{ facts }`, `content-state` as the app's `IconLiveActivityState`, dates in
  Unix seconds. Every card push carries the day's last reported Health total
  (`icon_days.measured_value`) as `value`, so a push never blanks the total
  the Dynamic Island shows; with no report the key is left out
  (`icon_push_v4.sql`). The notification fallback does not use it. Push-to-start also carries `input-push-token: 1` (iOS 18) so the
  started card gets an update token. Topic `<bundle id>.push-type.liveactivity`,
  priority 10, expiring at the cut-off (end: 4 hours after).
- Fallback: `apns-push-type: alert`, no sound. Title "Icon", subtitle activity
  and target ("Walking · 10,000 steps"), body the line and the cut-off in the
  Icon's time zone ("You've got this. Due 11:59 pm."). In the foreground the
  app does not show it.
- Only bundle ids in `APNS_TOPIC` and gateways in `APNS_ENVIRONMENT` are used;
  the route stores both with each provider token.

The words are the app's (`IconCopy`); the client approved the affirmations on
Oct 4 (O-12). The notification repeats the card's words, as the scope asks.

`icon_push_plan` is the SQL port of `plan.ts`. Any change goes into `plan.ts`
first, with its tests, then into the SQL; `parity_fixtures.ts` generates the
cases whose SQL output must be byte-identical (27/27 on Oct 4). With the
Health total there are 35 cases: `icon_push_v4.sql` gives 35/35 on production
in a rolled-back run, and was applied on Oct 5. With renewals there are 44:
`icon_push_v5.sql` gives 44/44 in a rolled-back run, and was applied on Oct 6.

## Setup

1. Database: `icon_push_v1.sql`, `icon_push_v1_1.sql`, `icon_push_v2.sql`,
   `icon_push_v3.sql`, `icon_push_v4.sql`, `icon_push_v5.sql`.
2. Secrets (Lovable Cloud): `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`
   (the whole `.p8`), `APNS_TOPIC` (allowed bundle ids, comma-separated),
   `APNS_ENVIRONMENT` (`sandbox`, `production` or both; unset means both). For
   the App Store build add its bundle id and `production`; the next provider
   token carries the change. On Oct 6 it was `sandbox` only while the client's
   TestFlight install registers `production` tokens, so that phone received no
   push at all. Set to both that day: the 10:34 UTC provider token carries both
   gateways and the self-test got 400 BadDeviceToken from each.
3. Web app: the `/api/internal/apns-token` route, published. The database
   calls it at `icon_push_state.token_url`
   (`https://honour-your-word.lovable.app/api/internal/apns-token`; the
   `project--…lovable.app` address answers 403 to server calls).
4. First token and self-test, from SQL:

   ```sql
   select public.icon_push_request_token();   -- then, a few seconds later:
   select key_id is not null, issued_at, topics, environments from public.apns_provider_tokens;
   select public.icon_push_selftest();        -- returns two request ids; a few seconds later:
   select id, status_code, content from net._http_response where id in (<ids>);
   ```

   The self-test sends to a made-up device token. `400 BadDeviceToken` means
   the key, team and topic work on that gateway; `403 InvalidProviderToken`
   means they do not (or the key is not enabled for that gateway).
5. Schedule: `select cron.schedule('icon-push', '* * * * *', 'select public.icon_push_tick()');`
6. App: the `aps-environment` entitlement needs Push Notifications on the App
   ID. Development: done (signed build, Oct 4). Production: enable it on the
   client's App ID (O-11).

## Checking on a device

It needs an iPhone on iOS 17.2+ with a development build.

1. Sign in; `push_tokens` gets a `device` and a `push_to_start` row for the
   install, `sandbox`.
2. Set an Icon day's morning reminder a few minutes ahead and close the app: the
   card appears within a minute of it, and an `activity` row follows.
3. At the evening reminder a fresh card shows "Finish what you signed." and the
   morning card goes.
4. Stamp the day (walk, or self-report): HONOURED within a minute or two.
5. At the cut-off the card closes.
6. Sign out: the install's rows are gone.
7. With Live Activities off for the app: the reminders arrive as quiet
   notifications.

`icon_push_log` and `icon_push_sends` show what each slot did.

## Limits

- A card the server started gets its update token only when iOS lets the app
  run briefly in the background. Until then the server cannot update or close
  it; the card's stale date still turns it to the evening line, and iOS ends it
  8 hours after it started.
- A card the person swiped away is not opened again until the next
  appearance (morning or evening), by the server or the app.
- The provider token sits in `apns_provider_tokens` and, for a moment, in the
  pg_net request queue. Neither is reachable through the API (RLS, and the
  `net` schema is not exposed).
- iOS budgets Live Activity pushes; three a day per card is far inside it.

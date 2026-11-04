# Icon card (Live Activity) — V1.2 M2-08

One Live Activity per Icon day, on the Lock Screen and in the Dynamic Island.
It appears at the morning reminder and again at the evening reminder, and
shows the day's result briefly before it closes. The card has no actions; a
tap opens the app.

Code: `ios/HonouredShared/IconLiveActivity.swift` (data and copy, shared by
the app and the widget), `ios/HonouredWidgets/IconLiveActivityViews.swift`
and `IconLiveActivityWidget.swift` (presentation),
`ios/HonouredShared/IconSignatureCache.swift` (signature images).

## Data

Everything is a plain value, so the app can start a card locally and the
push-to-start job (M2-07) can build the same JSON on the server.

`IconActivityAttributes` (fixed for the day) holds `facts`:

| Field | Example | Notes |
| --- | --- | --- |
| `contractId` | web contract id | `contracts.client_id`; also keys the signature |
| `iconDay` | `2026-10-06` | the Icon day |
| `weekday` | `TUE` | first three letters, upper case |
| `sessionNumber`, `totalSessions` | `5`, `17` | `icon_days.session_number` and the day count |
| `targetValue`, `targetUnit` | `10,000`, `STEPS` | the target as the person wrote it, split for layout |
| `activityName` | `Walking` | at most 40 characters |
| `because` | the Because line | at most 120 characters |
| `deadline` | cut-off instant | `icon_days.deadline_at`; shown in the device's zone, `Due midnight` for 00:00 |

`IconLiveActivityState` (changes during the day):

| Field | Values |
| --- | --- |
| `phase` | `morning`, `evening`, `result` |
| `line` | morning: the day's affirmation; evening: `Finish what you signed.`; result: `HONOURED` or `BROKEN` |
| `result` | `honoured`, `broken`, or absent |
| `updatedAt` | timestamp |
| `value` | the day's Health total so far, in the metric's canonical unit (count, meters, kcal, minutes); absent when unknown or self-reported, never zero for "no reading" |

Attributes plus state stay under the 4 KB ActivityKit and APNs limit even with
the longest allowed text (unit-tested). The Lock Screen card shows no progress
(client decision, 28 Sep); the Dynamic Island shows the day's Health total
(client, Oct 5), see Layout.

Affirmations rotate one per Icon day, seven in turn. The first two come from
the scope ("You've got this.", "You're closer than you think."); the other
five were approved by the client on Oct 4 (O-12): "Today is part of the
promise.", "Keep your word to yourself.", "Small steps, kept promises.",
"Become what you signed.", "Prove it again today." Each fits one line beside
the signature and the cut-off, at the largest allowed text size (render-tested).

## Layout

Lock Screen, four rows: mark, "Icon" and `5 OF 17`; target and activity;
the Because line in italics and the Icon day (`TUE 06.10.26`); signature, the
line of the moment and the cut-off. The day sits right above the cut-off,
both flush right (Phase 4); the Because line gives way to it. Dynamic
Island: the mark and the day's Health total so far (compact: `6,240`,
`3.2km`, `320`, `18m`, in the target's unit and written
like the target), the mark (minimal), the full rows without the Because line
(expanded, with the total before the target: `6,240 / 10,000 STEPS`, and
the day above the cut-off as on the Lock Screen). The
total stays after HONOURED, in gold, and keeps following Health. Without a
reading the compact slot shows the target; a BROKEN day shows ✕. HONOURED is
gold, BROKEN red. Every variant, including the longest text at the largest
allowed text size, renders under the Lock Screen's 160 pt.

The card and the island keep the Honoured ∞ mark; the web app's Icon
symbol (circle and four-point sparkle, Oct 5) is not used here (decided
Oct 5).

iOS shows an app's own Live Activity in the Dynamic Island only while that
app is not in the foreground; inside Honoured the island is empty and the
progress is on the app's screens.

## Signature

A push-started card carries only the contract id, so the widget reads the
person's signature from the App Group container (`IconSignatureCache`,
group `HONOURED_APP_GROUP` = `group.<bundle id>`, entitlement on both the app
and the widget).

The app fills it (`IconSignatureSync`): after a health upload or when it
becomes active, at most every 15 minutes, it lists the active Icons with
their `signature_path`, downloads each missing signature from the private
`signatures` bucket with the person's own session, and turns it into white
ink on transparency (`IconSignatureImage`, at most 480 px wide and 64 KB).
Signatures of Icons that ended are dropped; signing out or switching account
empties the cache. Without the entitlement, or before the first sync, the
card renders without a signature.

Every App ID that ships the app needs the App Groups capability with this
group: Xcode registers it for the development team when it signs with
`-allowProvisioningUpdates`; the production App IDs need the same in the
client's developer account.

## Lifecycle without push (M2-09, local)

`IconCardCoordinator` applies `IconCardPlan` whenever the app becomes active
and after every health upload (so also during background HealthKit
delivery). It reads the Icon days whose cut-off is within the next 36 hours,
with their contract, from Supabase using the person's own session.

- The card appears twice a day, as the scope describes: at the morning reminder
  and again at the evening one. iOS ends a Live Activity 8 hours after it
  starts, so a 07:00 card is gone before a 20:00 reminder; the evening gets a
  fresh card, which lasts until the cut-off because the evening reminder is set
  within 8 hours of it.
- A card opens once the app is in the foreground after that appearance's
  reminder (ActivityKit starts cards only from the foreground). Both reminders
  off means no card.
- A morning card carries the evening reminder as its stale date; from then the
  widget shows "Finish what you signed." without the app running.
- At the evening reminder the server push-starts the evening card and closes
  the morning one. The app waits 3 minutes for that, then does it itself if
  needed; in the background, where it cannot open a card, it leaves the
  morning card in place.
- Each pass reads the day's Health total for every card it shows, with the
  same read and window as Icon scoring (`IconVerifier`: midnight of the Icon
  day in the Icon's time zone, to now or the cut-off), and updates the card
  when the total changes. A read that fails (a locked device) or finds nothing
  keeps the total on the card; a new card starts from the last reported one
  (`icon_days.measured_value`). The server stops taking reports once the day
  is stamped, so after HONOURED only the app moves the total on.
- iOS ends a card 8 hours after it starts (ActivityKit: "A Live Activity can
  be active for up to eight hours"), so a card that would run out before the
  cut-off, with no evening card coming first, is renewed (client, Oct 6):
  whenever the app is in the foreground it swaps a card at least an hour old
  for a fresh one, unseen since the island hides the app's own card then;
  otherwise the server push-starts one 20 minutes before the 8 hours
  (`icon-push.md`). A card iOS already ended (still on the Lock Screen) comes
  back when the app opens; one the person removed stays away until the next
  appearance or renewal. Of two cards for a day, the newer stays.
- When the day is stamped HONOURED the card shows the result until the cut-off.
- The card closes at the cut-off, or when the day is stamped BROKEN or amended,
  the Icon ends, or another account signs in, the next time the app runs. Each
  appearance is started once: a card the person swiped away is not opened
  again until the next appearance.
- Sign-out and account switch close every card.

Without push, a card the app cannot run for may outlive its cut-off until iOS
ends it (at most 8 hours after it started). Push-to-start and push updates
(M2-07) remove that gap and open cards at the reminder times without the app;
see `icon-push.md`. The app starts its own cards with a push token, so the
server can update and close those too, and treats a card the server started
as already shown.

Debug builds can show a sample card with `-HonouredBridgeScenario icon-card`
and remove it with `icon-card-end`.

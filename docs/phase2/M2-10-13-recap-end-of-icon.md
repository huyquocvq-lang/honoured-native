# M2-10 to M2-13 — Icon recap, end of an Icon, Go again

Sources: scope v6, "Weekly & Monthly Recap" (the weekly lines below are its
own); tracker tasks M2-11 to M2-13 (added Oct 1: final summary, invitation to
go again, prefilled re-signing, no automatic renewal). The monthly and
end-of-Icon wording was drafted on Oct 4 and approved by the client the same
day (O-15), together with rules 3, 4 and 6.

## Recap (M2-10)

1. **Periods.** Monday-to-Sunday weeks and calendar months, by each Icon
   day's own date (the day in the Icon's time zone).
2. **When.** After the period ends, once no Icon day in it is still pending
   (the server stamps every day within 24 hours of its cut-off), the next time
   the person is on Home. Only the period just before the current one is
   offered, so a recap never arrives weeks late. Each recap shows once per
   account on a device. When both are due, the month comes first.
3. **Totals.** Honoured and Broken count sessions stamped in the period.
   Amended counts Icons ended early in the period, by the day they were ended;
   the days an early exit releases are not counted, otherwise a 3-month Icon
   ended in week 2 would show "Amended" every week after.
4. **Tone.** More Honoured than Broken is a strong period; anything else,
   including a tie, is a tough one. With nothing stamped Honoured or Broken
   there is no recap. A tough period with at least one Honoured session adds
   "That's one more than zero." (with the count: "That's three more than
   zero.").

## End of an Icon (M2-11)

5. **When it ends.** Once its last cut-off has passed and every session is
   stamped. An Icon ended early is AMENDED already and gets no summary. The app
   never ends an Icon from an incomplete list of days.
6. **Closing status.** HONOURED when more sessions were honoured
   than broken, otherwise BROKEN; resolved at the last cut-off. Closing it
   takes it off the active lists and frees its activity for a new Icon (one
   active Icon per activity). In History its days are its record (below); the
   closed Icon adds no entry of its own.
7. **Summary.** Shown once per account on a device, within 14 days of the last
   cut-off, before any recap: the Icon's activity and target, the count and
   the strong or tough line. No HONOURED/BROKEN stamp: the scope says a hard
   period is never rubbed in.

## History calendar (client request Oct 5)

The client: "Icon colour dots are great. But they need to sync to the
calendar — when an Icon day is honoured/broken/amended, that activity record
appears in the calendar with the same colour coding. Calendar is where users
see the full detail + history."

Before, History read only resolved contracts: an Icon is active for its whole
period, so none of its days appeared, and a finished Icon showed once on its
last day. Now (`src/lib/history-entries.ts`):

- every Icon day stamped HONOURED or BROKEN is an entry on its own Icon date,
  green or red like the day marks, while the Icon runs and after it ends;
- an Icon ended early is one AMENDED (amber) entry on the day it was ended,
  with "k of N sessions honoured"; the days the exit released are not shown,
  since they never took place;
- ordinary contracts are unchanged; a date with several entries takes the
  colour of the newest; month totals count every entry;
- an Icon day's detail shows Target, Session "k of N" and Result (the Health
  reading, "Self-reported" or "No Health data"); its list row reads
  "Icon · Session k of N".

## Go again (M2-12)

8. "Go again" opens the composer with the finished Icon's activity, target,
   Because, days, period, reminders and daily cut-off. The new period starts
   on the day it is signed. Everything stays editable; the signature pad is
   empty, so it needs a fresh signature; signing runs the usual checks
   (duplicate Icon, evening window, day exclusivity, sessions). Nothing renews
   by itself.

## Wording

| Where | Text | Source |
|---|---|---|
| Week, strong | You slayed it this week. | scope v6 |
| Week, tough | I believe in you even though this week has been challenging. Keep the dream alive and chase it. Let's start this week energized and use last week as kindle to start the flame. | scope v6 |
| Tough, one Honoured | That's one more than zero. | scope v6 |
| Tough, more Honoured | That's two/three/… more than zero. | client (O-15) |
| Month, strong | You slayed it this month. | client (O-15) |
| Month, tough | I believe in you even though this month has been challenging. Keep the dream alive and chase it. Let's start this month energized and use last month as kindle to start the flame. | client (O-15) |
| Recap titles | Your week · Your month | client (O-15) |
| Recap labels | Honoured · Amended · Broken | scope v6 |
| End, title | Icon complete | client (O-15) |
| End, count | 16 of 18 sessions honoured | client (O-15) |
| End, strong | You kept your word. You became an Icon. | client (O-15) |
| End, tough | This Icon tested you, and you saw it through. Keep the dream alive and use these days as kindle to start the next flame. | client (O-15) |
| End, buttons | Go again · Not now | client (O-15) |

## Approved by the client (O-15, Oct 4)

- The wording above.
- The closing status of a finished Icon (rule 6).
- A tie counts as a tough period (rule 4); Amended means Icons ended early
  (rule 3).

## Implementation (Oct 4)

- **Decisions:** `src/lib/icon-recap.ts` in the web app (local copy and
  tests in `m2-10-13/web/`): periods, totals, tone, wording, which moments
  are due, when an Icon ends, and the Go again prefill. Pure functions; the
  app passes the clock, the Icon days and what was already shown. 32 tests,
  passing in four time zones (UTC, New York, Sydney, Ho Chi Minh City); each
  rule was also changed on purpose once to check a test fails.
- **Web (Lovable 214b2e0, published Oct 4):**
  - `index.tsx`: the 1-second sweep closes finished Icons (`completeIcons` in
    `store.ts`, without the resolved-contract notices that drive the contract
    Live Activity), once contracts are loaded from the server. A due moment
    shows full screen when the person is on Home with nothing else open, and
    is recorded first in `AppState.momentsSeen`, so it appears once per
    account on a device.
  - `IconMoment.tsx`: the recap and the end-of-Icon screens.
  - `Contract.tsx`: `ContractScreen` takes the Go again prefill.
  - `History.tsx`: Icon days in the calendar, the totals, the day detail and the list (Oct 5, `history-entries.ts`).
  - `icon-days.ts`: reads every page of `icon_days`; PostgREST returns at
    most 1,000 rows per request, ordered by day, so the newest days were the
    ones cut off.
- **Checks:** the two files in Lovable are byte-identical to the local ones;
  type check clean; Lovable suite 479/479 (42 files), including new tests for
  `completeIcons` and the paging. The composer prefill has no automated test:
  the suite does not render components. The live site serves the new strings.
- **No database change.** Icon days come from `icon_days` as before; the
  closing status is written by the web app like any contract status, and
  `contracts_icon_guard` already lets an active Icon become HONOURED or
  BROKEN (and never active again).
- **Live data:** one Icon (Sydney, Oct 2 to Jan 1). Its first weekly recap
  (28 Sep – 4 Oct) appears once its Oct 3 and Oct 4 days are stamped; it ends
  after Jan 1.
- **Not yet seen on a device:** the recap and summary screens, Go again and
  signing from it (M2-13, with M2-14).

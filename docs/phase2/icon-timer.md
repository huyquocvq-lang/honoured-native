# Icon timer and DEF-01 — Oct 6

Raised 6 Oct 2026 while testing an Icon that Apple Health cannot measure
("Basketball · 22 min", Mondays and Thursdays for one week): the Icon had no
Testament Timer, and with a daily contract in force the Contract tab hid the
Active Icons list (DEF-01 in the M2 QA plan). Not in scope v6, which verifies
the Oath through HealthKit only. Web change only: no database or native change.

## Rules

1. **Which Icons.** An active Icon with no Health metric (`icon_metric` null,
   so self-reported), a "complete" commitment and a time target ("22 min",
   "1 hr"). Measured Icons stay Health-only; the server refuses self-report
   for them anyway.
2. **When.** Only on a pending Icon day, before its cut-off, and only when the
   timer can finish before the cut-off. One timer at a time: while another
   contract's timer runs the Icon shows "Another timer is running. Finish it
   first." instead of replacing it.
3. **Finish.** A finished timer stamps the Icon day it was started for
   HONOURED through `self_report_icon_day` (resolution `self_reported`, so
   History shows "Self-reported"). It never honours the Icon as a whole:
   `honourContract` now refuses Icon contracts. A timer that finishes on
   another day or after its day's cut-off stamps nothing; the self-report
   prompt stays.
4. **Pause.** A paused timer cannot be resumed when the remaining time would
   run past its day's cut-off. Cancel is always available.
5. **Celebration.** The completion gong plays when the timer finishes while
   the app is in front (`notified: false`), as for ordinary contracts. No
   completion overlay: the Icon row shows "Timer finished. Today's session is
   HONOURED." If saving fails: "Couldn't save the timer result. Tap Honoured to
   record it."

## Where it shows

- **Contract tab, Active Icons:** "Start The Testament Timer" with
  "22 min · stamps today's session Honoured on finish"; while it runs, the
  countdown, Pause/Resume and Cancel timer. Today's self-report question is
  hidden while the timer runs or is paused.
- **Home, Icons row:** "· 12:34 left" or "· Paused 12:34" after the Icon's
  line.
- **DEF-01:** with a daily contract in force, the Contract tab shows the Active
  Icons list above "Your contract is in force", so End early, self-report and
  the timer stay reachable.

## Native

Nothing changes. Icons are excluded from Live Activity tracking, so the web
sends the plain `START_TIMER` (`activityId` = the Icon's local contract id);
native counts down, shows "Time's up" and reports `TIMER_COMPLETED` as for
any timer. The Icon card does not show the countdown; it shows HONOURED once
the day is stamped (Icon push, `icon-push.md`).

## Code

Web (Lovable project Honoured V13): `src/lib/icon-timer.ts` (rules,
completion, notices), `src/lib/timer-store.ts` (routing of finished Icon
timers, `iconDay` on the timer state), `src/lib/store.ts` (`honourContract`
guard), `src/components/ActiveIcons.tsx` (controls, Home row),
`src/components/screens/Contract.tsx` (DEF-01). Tests:
`tests/icon-timer.test.ts`, `tests/icon-timer-store.test.ts`. Local copy in
`icon-timer/web/`.

## Checks (Oct 6)

- Lovable commit `c0d1fbb`: `bunx tsgo --noEmit` clean, `bunx vitest run`
  46 files / 514 tests passed (as reported by the Lovable agent).
- Not yet published, and not yet tried in the browser or on an iPhone. Still
  to check on a device: start, pause, resume and cancel on an Icon day; a
  finish with the app in front (gong, notice) and in the background ("Time's
  up", stamp on the next open); the Icon card turning HONOURED; the Contract
  tab with a daily contract in force.

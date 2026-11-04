# Motion probe: M1 test guide

Draft for review before it is shared.

The motion probe is a test tool inside Honoured for Phase 3 Milestone 1. Each
time iOS lets Honoured run, the probe records what Core Motion (the iPhone's
own step counter) and Apple Health report, and when Honoured noticed a test
target. It adds no new way of running in the background. Measuring the
existing ways is the point of M1.

The probe only opens in TestFlight and development builds. App Store builds
ignore it.

## Before you start

1. Install the TestFlight build that includes the probe and sign in to
   Honoured as usual. Background updates from Apple Health need a signed-in
   account.
2. Open `honoured://motion-probe` on the iPhone, for example by tapping it in
   Notes. The Motion probe screen opens over Honoured.
3. Turn on **Record app runs**.
4. Allow the three permissions the screen offers:
   - Motion & Fitness
   - Health steps, distance and energy
   - notifications

   If you decline one, the related test cases cannot be measured.
5. Charge the iPhone above 50% and note whether Low Power Mode is on.

## A test session

1. Set a target that takes a few minutes to walk, for example 500 or 1,000
   steps. Tap **Start session**. Both sources count from zero at that moment.
2. Do the test case below.
3. Keep walking until you have clearly passed the target, then stop.
4. When the probe announces the target, it sends a notification titled
   "Probe target reached", one for Core Motion and one for HealthKit. Do not
   clear these notifications before the next step. The probe reads their
   delivery time from Notification Center.
5. Open Honoured, open the probe again and tap **Rebuild crossing times**. The
   report estimates the minute each source crossed the target and shows each
   delay as a range.
6. Tap **Stop session**.
7. Record the screen during the walk if you can. A screen recording is the
   only proof of when a notification or Live Activity change appeared on a
   locked iPhone.

## Test cases

| # | Situation | How |
|---|---|---|
| T1 | Honoured open | Keep the probe screen open while walking. |
| T2 | Home Screen, not locked | Start, press Home, walk with the screen on. |
| T3 | Locked, in a pocket | Start, press Home, then lock the iPhone and walk. When you stop, unlock without opening Honoured and wait two minutes before opening it. |
| T4 | Locked for a long time | Lock the iPhone for at least 30 minutes before the walk, then walk. |
| T5 | Force-quit | Start, swipe Honoured away in the app switcher, walk. |
| T6 | After a restart | Start, restart the iPhone and do not unlock it, walk, then unlock. |
| T7 | Watch only | Wear an Apple Watch, leave the iPhone on a table, walk. |
| T8 | Watch and iPhone | Wear the Watch and carry the iPhone, walk. |
| T9 | Low Power Mode | Repeat T3 with Low Power Mode on. |

For Live Activities and the Dynamic Island, run T1 to T5 with an active step
contract that shows a card. Note in the recording when the card's number
changes.

## Sending the results

Tap **Export log** and share the zip file. It contains:

- `events.jsonl`: one line per event
- `reports/`: for each rebuilt session, a report and a per-minute CSV of Core
  Motion and each Apple Health source
- `metrickit/`: the energy and CPU reports iOS delivers about once a day

The log holds step counts, timestamps, battery level and the names of your
Health sources (for example "Apple Watch"). It holds no account details.

## How to read the log

Every event is labelled:

- `recorded`: Honoured or iOS noted the moment as it happened, for example the
  app being woken, a reading, or iOS's own delivery time of a notification.
- `estimated`: inferred afterwards. These events always carry a time window and
  the method used. The moment a target was crossed is always estimated,
  because no Apple API reports when the Nth step happened.
- `unknown`: no evidence. For example, a notification that was cleared before
  Honoured could check it has no recorded delivery time.

A delay between two recorded moments is a measurement. A delay involving an
estimated moment is shown as a range, for example "3–7 min".

## Known limits

- Core Motion keeps about seven days of step history on the iPhone.
- After a restart, iOS keeps Honoured's own files locked until the first
  unlock. The probe therefore records nothing before that unlock, and this is
  part of what T6 shows.
- When the iPhone is locked, iOS encrypts Apple Health data, so readings may
  fail with an error. That error is itself a result the log keeps.
- The probe sees a lock only when it starts while Honoured is on screen or
  running. A lock that starts while Honoured is suspended in the background,
  or after it was swiped away, leaves no trace. The report then lists the time
  Honoured spent in the background instead of saying the iPhone was unlocked.
- The battery figures from a short test are indicative only.
- The calorie figure is an estimate from distance and pace, assuming 70 kg. It
  is not Apple Health's Active Energy, which the report lists next to it.

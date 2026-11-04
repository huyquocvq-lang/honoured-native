# Phase 4 — Two-Milestone Estimate and Scope Reply

Thanks for the revised Phase 1 scope. I've checked each item against the current app. The total stays inside your range, but the hours sit differently between items.

Estimates (yours -> mine)
1. Zero defaults: 4h -> 4h
2. Icon amend, re-sign and change history: 20-25h -> 28h
3. Date on the daily card: 1h -> 2h
4. Email opt-in: 2-3h -> 5h
5. Philosophy modal: 12-16h -> 7h
6. Health & Tracking source selection: 12-19h -> 18h
Total: 51-68h -> 64h

Milestones
- Milestone 1: items 1, 4, 5 and 6 = 34h
- Milestone 2: items 2 and 3 = 30h. Both change the lock-screen Icon card, so they ship in the same app update.

Why they differ
1. Zero defaults: as you estimated. Signing will also require a target above 0 (at least 100 for words), so a contract can't be signed without a target.

2. Icon amendments: once an Icon is signed, its target is locked in the database, and scoring, reminders and the lock-screen card all read that one target. To keep the original and change only future days, each Icon day needs its own target, the amendment history needs its own records that are never edited, and each new signature is stored next to the original instead of replacing it. That touches the database, the app's screens and the lock-screen card. Word Tracker Icons would add 2-3h, and same-day amendments about 2h.

3. Date on the card: your example ("Due midnight") matches the lock-screen Icon card, which is native, so it ships with the next app update. The date comes from the Icon day, not the deadline, because a midnight cut-off falls on the next calendar date. Showing the date on the card inside the app as well would add 1h.

4. Email opt-in: 2.5-3h covers email sign-up only. Apple and Google sign-up need extra work because they share buttons with sign-in and Apple sign-in can't carry the choice through. This records the consent (yes or no, with date and source); sending emails or syncing to an email tool isn't included.

5. Philosophy modal: a modal right before signing, placed before the step that uses a free session, so going back costs nothing. 12-16h would only be needed for an elaborate animated sequence.

6. Health & Tracking: the Core Motion integration (3-5h in your breakdown) was built in the Core Motion M2 milestone. Those hours go to the parts that are new:
- the "iPhone" option, which reads only the Apple Health data this iPhone recorded (today the app can only pick a source by its name)
- updating Icon days and History when someone switches between Automatic and iPhone, which needs a small database update
- moving people who picked Apple Watch, Garmin or another app in the current source picker onto the three new options
- keeping the new screen working with the current App Store version until people update

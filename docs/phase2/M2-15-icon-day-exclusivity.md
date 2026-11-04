# M2-15 — Icon day exclusivity

Client request, 3 Oct 2026: when an Icon is set for a day, that day allows
only the Icon. An attempt to add another activity shows:

> Icon already set for this day. Finish your Icon first.

Estimate: 4 h (M2 74 h, V1.2 171 h). The cases the request does not spell
out were decided on 3 Oct (developer proposal, to share with the client).

## Rules

1. **Reserved days.** Each scheduled day of an active Icon is reserved: the
   whole calendar day in the Icon's time zone, from 00:00 to 24:00, whether
   or not it has been stamped yet. Reservation lasts until the Icon ends; the
   days an early exit marks AMENDED are released.
2. **Ordinary contract.** A contract cannot be signed if the time it covers,
   from signing to its deadline, touches a reserved day. Message: "Icon
   already set for this day. Finish your Icon first."
3. **Second Icon.** An Icon cannot be signed if any of its scheduled days is a
   reserved day of another active Icon. The whole Icon is refused (no days are
   silently dropped, so the session count shown before signing stays true).
   Same message.
4. **Icon after a contract.** An Icon cannot be signed while an active
   ordinary contract covers any of its scheduled days; an active legacy
   Standing contract covers every day. Message (proposed, same voice as the
   client's): "Contract already set for this day. Finish your contract first."
5. **Days without an Icon** are unaffected: ordinary contracts work as before.

## Where it is enforced

- **App (web):** before signing, so the person sees the message and keeps
  the draft and signature.
- **Database:** the same check when the contract row is first written, so two
  devices or an old app version cannot get around it. The web app must treat
  that refusal as a message, not a failed sync that retries forever.

## Tests to include

Ordinary contract on an Icon day (before and after the cut-off), on a
non-Icon day, and with a deadline that runs into the next Icon day; second
Icon with and without overlapping weekdays; Icon while a contract is active
or after it resolved; an amended Icon releasing its days; the database
refusing a conflicting insert without blocking other contracts' sync.

## Implementation (Oct 4)

- **Database:** `docs/db/icon_exclusivity_v1.sql`. A BEFORE INSERT trigger,
  `contracts_icon_reserve`, runs after `contracts_icon_guard` (triggers fire in
  name order) on the first write of an active contract, with a per-person
  advisory lock so two devices cannot both pass. Held days come from
  `icon_reserved_days(user)`: whole days in the Icon's time zone. A refusal is
  `P0001` with DETAIL `icon_day_reserved` or `contract_day_reserved` and the
  message above. Rows that already exist (the web upserts every change) and
  contracts arriving already resolved pass untouched.
- **Web:** `src/lib/icon-exclusivity.ts` (local copy in `m2-15/web/`) holds
  the same rules on device-local days. `Contract.tsx` checks in `sign()` before
  a session is spent, so the draft and signature stay. `contract-sync.ts` saves
  through `upsertContractRows`: when the database refuses rows, the rest are
  sent one at a time, so one refusal never blocks other contracts. The refused
  contract is removed from the device (it was never accepted) and a sheet shows
  the message with an OK button.
- **Order:** web published first, then the trigger. A page still open on the
  old version keeps failing to save a refused contract until it reloads; the
  new version then removes it and shows the message.
- **Checks:** database 23/23 in a rolled-back production run (every case
  under "Tests to include", plus re-sync of existing rows, resolved history,
  Standing both ways, another person's Icon, trigger order, grants); web 16
  tests in four time zones locally and 439/439 in the Lovable suite.
- A person whose Icon covers every day (the live Sydney Icon) cannot sign any
  other contract until it ends. That is the requested behaviour.

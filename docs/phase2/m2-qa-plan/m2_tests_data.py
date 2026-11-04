# Test cases for V1.2 Milestone 2 (the Icon). Data only; build_m2_tests.py
# turns it into the workbook. Each case: id, task, area, source, title,
# priority, type, platform, preconditions, steps, expected, evidence.

CASES = []


def tc(id, task, area, source, title, priority, type_, platform, pre, steps, expected, evidence, note=""):
    CASES.append(dict(id=id, task=task, area=area, source=source, title=title, priority=priority, type=type_,
                      platform=platform, pre=pre, steps=steps, expected=expected, evidence=evidence, note=note))


# --------------------------------------------------------------------------
# M2-01 Icon row, status pill, Standing Contract removal
# --------------------------------------------------------------------------
tc("M2-01-TC01", "M2-01", "Icon row", "Scope v6 §4 The Oath Row; client Icon mockup Oct 1 (E-20)",
   "Icon row replaces Standing Contract (unset state)", "P1", "Functional", "iPhone app",
   "S0. No daily contract in force. No Icon set in the composer.",
   "1. Open the Contract tab.\n2. Scroll to the terms area below Because.\n3. Look for any Standing Contract option on the page.",
   "- A row 'Icon' with a grey target icon, the grey lines 'Become an Icon' and '(for multi-day goals)', and a chevron, directly above the Deadline field.\n"
   "- No Standing Contract checkbox, row or toggle anywhere in the composer.\n"
   "- Deadline row reads 'Deadline' with a date and time.",
   "1) SCR terms area with the unset Icon row and the Deadline row.\n2) SCR full composer scrolled top to bottom (no Standing option).")

tc("M2-01-TC02", "M2-01", "Icon row", "Scope v6 §4 The Oath Row (set state; reminder times not shown)",
   "Set state shows the Icon terms only, in gold", "P1", "Functional", "iPhone app",
   "S0. Composer open, Icon not set.",
   "1. Tap the Icon row.\n2. In the sheet select Tue, Thu, Sat, Sun; keep 1 Month; leave reminders at 07:00 / 20:00.\n3. Tap SET THE ICON.",
   "- Sheet closes.\n- Row: target icon in gold, 'Icon', gold summary 'Tue · Thu · Sat · Sun | 1 Month'.\n"
   "- No reminder time appears in the row.\n- The Deadline label becomes 'DEADLINE (EACH ICON DAY)' and shows a time only.",
   "1) SCR row in set state with the Deadline row.")

tc("M2-01-TC03", "M2-01", "Status pill", "Scope v6 §4 ('OATH · UNSIGNED' renamed ICON · UNSIGNED, E-19)",
   "Status pill follows the Icon draft", "P1", "Functional", "iPhone app",
   "S0. Composer open.",
   "1. Read the pill under 'The Contract'.\n2. Set a valid Icon (any days, 1 Week).\n3. Read the pill.\n4. Reopen the sheet, tap Remove Icon.\n5. Read the pill.",
   "- Step 1: 'UNSIGNED' with a grey dot.\n- Step 3: 'ICON · UNSIGNED' with a gold dot.\n- Step 5: back to 'UNSIGNED' (grey dot).",
   "1) SCR pill unset.\n2) SCR pill ICON · UNSIGNED.\n3) SCR pill after Remove Icon.")

tc("M2-01-TC04", "M2-01", "Icon row", "Scope v6 §4 ('Tap to reopen and edit before signing')",
   "Days are summarised Monday to Sunday whatever the tap order; row reopens the committed terms", "P2", "Functional", "iPhone app",
   "S0. Composer open.",
   "1. Open the sheet, tap Sun then Tue (in that order), choose 3 Months, SET THE ICON.\n2. Tap the row again.\n3. Change the period to 1 Week, then tap Cancel.\n4. Read the row.",
   "- Step 1 row: 'Tue · Sun | 3 Months'.\n- Step 2: the sheet opens with Tue and Sun selected and 3 Months selected.\n- Step 4: the row still reads 'Tue · Sun | 3 Months' (Cancel discards the change).",
   "1) SCR row after step 1.\n2) SCR sheet reopened (step 2).\n3) SCR row after Cancel.")

tc("M2-01-TC05", "M2-01", "Standing removal", "Scope v6 §4 ('Standing Contract is removed as an option')",
   "New contracts are never Standing", "P2", "Data", "iPhone app + DB",
   "S0. Sign any ordinary (non-Icon) contract on a day that is not held by an Icon, or use the Icon signed in M2-04-TC01.",
   "1. Sign the contract.\n2. Run Q-01 (Icon) or look the contract up by client id with Q-01 without the icon filter.",
   "- The stored contract has standing = false.\n- No UI offered a Standing choice at any point.",
   "1) DB Q-01 row showing standing = false.")

tc("M2-01-TC06", "M2-01", "Standing removal", "Scope v6 §4 Existing Standing Contracts",
   "Legacy Standing contracts keep running until they end", "P3", "Regression", "iPhone app",
   "An account with a Standing contract signed before V1.2.",
   "1. Open Home and the Contract tab.\n2. Wait past the daily reset hour.",
   "- The Standing contract is still listed ('Standing Contract', 'Resets in …') and rolls to a new cycle at the reset hour.",
   "1) SCR Standing row before and after the reset.",
   "Production had 0 Standing contracts on Oct 4 (checked), so mark N/A unless test data exists. Automated regression: E-19.")

tc("M2-01-TC07", "M2-01", "Icon row", "Scope v6 §4 ('One activity type per Oath contract')",
   "An Icon has one activity: the secondary activity is hidden", "P2", "Functional", "iPhone app + DB",
   "S0. Composer with a secondary activity added.",
   "1. Add a secondary activity.\n2. Set an Icon.\n3. Look for the Secondary activity block.\n4. Sign the Icon (or remove the Icon and continue with other tests).",
   "- With the Icon set, the Secondary activity block is not shown.\n- After signing, the contract has no secondary activity (Q-01: secondary_activity is null).",
   "1) SCR composer with Icon set and no secondary block.\n2) DB Q-01 (secondary_activity null) if signed.")

# --------------------------------------------------------------------------
# M2-02 Icon sheet
# --------------------------------------------------------------------------
tc("M2-02-TC01", "M2-02", "Icon sheet", "Scope v6 §4 The Oath Sheet; client mockup Oct 1",
   "Sheet opens as a bottom sheet with handle and header", "P1", "Functional", "iPhone app",
   "S0. Composer open.",
   "1. Tap the Icon row.",
   "- Bottom sheet over the dimmed Contract page, with a grab handle.\n- Header: gold target icon, 'Icon', 'Become an Icon', '(for multi-day goals)'.\n"
   "- Sections in order: DAYS, PERIOD, REMINDERS, the session count box, SET THE ICON, Cancel.\n- The page behind does not scroll while the sheet is open.",
   "1) SCR sheet top.\n2) SCR sheet bottom (scrolled).")

tc("M2-02-TC02", "M2-02", "Icon sheet", "Scope v6 §3 step 3, §4 Days, colour system",
   "Seven day toggles; at least one day required", "P1", "Functional", "iPhone app",
   "Sheet open, fresh (no Icon set yet).",
   "1. Observe the day buttons M T W T F S S.\n2. Tap Mon and Wed, then tap Wed again.\n3. Deselect every day.",
   "- Fresh sheet: no day selected; 'Choose at least one day.' is shown and SET THE ICON is disabled.\n"
   "- Selected day: white letter with a hairline outline; unselected: dim grey letter with a faint outline; no solid fills.\n"
   "- Tapping a selected day deselects it.\n- With no day selected, SET THE ICON is disabled again.",
   "1) SCR fresh sheet (message + disabled button).\n2) SCR with Mon selected.")

tc("M2-02-TC03", "M2-02", "Icon sheet", "Scope v6 §3 step 4, §4 Period",
   "Period quick picks with 1 Month as default", "P1", "Functional", "iPhone app",
   "Sheet open, fresh.",
   "1. Note the selected period.\n2. Tap each of 1 Week, 3 Months, 6 Months, 1 Year, 1 Month.",
   "- Options: 1 Week, 1 Month, 3 Months, 6 Months, 1 Year, Custom.\n- 1 Month is selected on a fresh sheet.\n"
   "- Exactly one option is selected at a time; the count box reads 'over 1 Week.', 'over 3 Months.' … accordingly.",
   "1) SCR period picks with 1 Month selected.")

tc("M2-02-TC04", "M2-02", "Session count", "Scope v6 §3 step 6, §4 Live session count; §7 acceptance (17 sessions)",
   "Live session count is always visible and correct", "P1", "Functional", "iPhone app",
   "Sheet open. Note today's date.",
   "1. Select Tue, Thu, Sat, Sun with 1 Month.\n2. Change to 1 Week, then to every day + 1 Week.\n3. Select Mon, Wed, Fri with 3 Months.",
   "- The box always shows 'You are committing to', 'N sessions', 'over <period>.', 'Make sure this is achievable.' and updates on every change.\n"
   "- N equals the 'Session count' table in the Test Data sheet for today's date (e.g. Tue·Thu·Sat·Sun | 1 Month = 17 on Mon 5 Oct, 18 on Tue 6 Oct; every day | 1 Week = 7).\n"
   "- 1 session reads 'session' (singular).",
   "1) SCR count for each step (3 screenshots) with the date visible in the status bar.",
   "The count includes today even when today's cut-off has already passed; see M2-04-TC07.")

tc("M2-02-TC05", "M2-02", "Custom period", "Scope v6 §4 Period (2 days to 1 year); M2-02 done-when",
   "Custom period accepts 2 days to one calendar year", "P1", "Boundary", "iPhone app",
   "Sheet open, at least one day selected.",
   "1. Tap Custom.\n2. Enter 2.\n3. Enter 365 (or the maximum shown in the label).\n4. SET THE ICON with 2 days and every day selected.",
   "- A field labelled 'Duration in days (2–365)' appears (366 when the coming year contains 29 Feb).\n"
   "- 2 and the maximum are accepted: no error, the count updates, SET THE ICON enabled.\n- Row summary after step 4: 'Mon · Tue · Wed · Thu · Fri · Sat · Sun | 2 Days'.",
   "1) SCR custom field with 2.\n2) SCR with the maximum.\n3) SCR row '… | 2 Days'.")

tc("M2-02-TC06", "M2-02", "Custom period", "Scope v6 §4 Period; M2-02 done-when",
   "Custom period rejects values outside the range", "P1", "Negative", "iPhone app",
   "Sheet open on Custom, at least one day selected.",
   "1. Enter 1.\n2. Enter the maximum + 1 (366 in Oct 2026).\n3. Enter 2.5, then abc, then leave it empty.",
   "- 1 → 'Choose at least 2 days.'\n- maximum + 1 → 'Choose no more than 1 year.'\n- 2.5 / abc / empty → 'Enter a whole number of days.'\n"
   "- While invalid: SET THE ICON disabled, the count shows '0 sessions' and 'over ….'",
   "1) SCR each message (3).")

tc("M2-02-TC07", "M2-02", "Reminders", "Scope v6 §3 step 5, §4 Reminders and custom toggles",
   "Morning and evening reminders: defaults, toggles, either or both off", "P1", "Functional", "iPhone app",
   "Sheet open, fresh.",
   "1. Read both reminder rows.\n2. Turn Morning off; then turn Evening off; then both on.\n3. With both off, select a day and SET THE ICON.",
   "- Defaults: Morning on 07:00, Evening on 20:00.\n- Toggle ON: hairline outlined track with a solid white knob on the right; OFF: faint track with a dim knob on the left (not the iOS switch).\n"
   "- An off reminder's time is greyed out and cannot be edited.\n- Both off is allowed: SET THE ICON works.",
   "1) SCR defaults.\n2) SCR one on, one off.")

tc("M2-02-TC08", "M2-02", "Reminders", "Decision Oct 1 (E-27): morning before 12:00, evening from 12:00",
   "Morning must be before 12:00, evening from 12:00", "P1", "Negative", "iPhone app",
   "Sheet open, a day selected.",
   "1. Set Morning to 12:30.\n2. Set Morning back to 07:00 and Evening to 11:00.\n3. Set Evening to 12:00.",
   "- Steps 1 and 2: 'Morning must be before 12:00, evening from 12:00.' and SET THE ICON disabled.\n- Step 3: message gone, SET THE ICON enabled.",
   "1) SCR message with the disabled button.")

tc("M2-02-TC09", "M2-02", "Reminders", "Implementation (TIME_REQUIRED)",
   "An enabled reminder needs a time", "P3", "Negative", "iPhone app",
   "Sheet open.",
   "1. With Morning on, clear its time (iOS time picker: Reset/Clear, if offered).",
   "- 'Choose a time.' under the row; SET THE ICON disabled.",
   "1) SCR message.",
   "Mark N/A if the iOS picker cannot produce an empty value.")

tc("M2-02-TC10", "M2-02", "Icon sheet", "Scope v6 §4 ('SET THE OATH closes the sheet and saves the settings to the unsigned contract')",
   "SET THE ICON applies; Cancel discards the working copy", "P1", "Functional", "iPhone app",
   "S0. Composer open.",
   "1. Set an Icon: Mon, Wed | 1 Week, Morning 08:00.\n2. Reopen, change to Fri | 3 Months, Morning 09:00, then Cancel.\n3. Reopen the sheet.",
   "- After step 1 the row reads 'Mon · Wed | 1 Week'.\n- After step 2 the row still reads 'Mon · Wed | 1 Week'.\n- Step 3 shows Mon, Wed, 1 Week and Morning 08:00.",
   "1) SCR row after step 2.\n2) SCR sheet after step 3.")

tc("M2-02-TC11", "M2-02", "Icon sheet", "Scope v6 §4 ('Swipe down cancels with no Oath set')",
   "Swipe down, backdrop tap and Cancel close the sheet without setting an Icon", "P1", "Functional", "iPhone app",
   "S0. Composer, Icon not set.",
   "1. Open the sheet, select Mon, drag the handle down a short way (about 1 cm) and release.\n2. Drag the handle down well past 1.5 cm and release.\n3. Open again, select Mon, tap the dimmed area above the sheet.\n4. Open again, select Mon, tap Cancel.",
   "- Step 1: the sheet follows the finger and snaps back; it stays open.\n- Steps 2–4: the sheet closes and the row stays unset ('Become an Icon').",
   "1) REC steps 1–2 (drag feel).\n2) SCR row unset after closing.")

tc("M2-02-TC12", "M2-02", "Icon sheet", "Scope v6 §4 ('Remove Oath' link when already set)",
   "Remove Icon link appears only when an Icon is set", "P1", "Functional", "iPhone app",
   "S0. Composer.",
   "1. Open the sheet with no Icon set.\n2. Set an Icon and reopen the sheet.\n3. Tap Remove Icon.",
   "- Step 1: no 'Remove Icon' link.\n- Step 2: a small underlined 'Remove Icon' link under SET THE ICON.\n- Step 3: the sheet closes; the row is unset; the pill reads 'UNSIGNED'; Deadline is back to date and time.",
   "1) SCR sheet without the link.\n2) SCR sheet with the link.\n3) SCR composer after removal.")

tc("M2-02-TC13", "M2-02", "Icon sheet", "M2-02 notes (layout at large text)",
   "Sheet is usable at the largest text size", "P2", "Usability", "iPhone app",
   "iPhone Settings › Accessibility › Display & Text Size › Larger Text: largest standard size.",
   "1. Open the sheet.\n2. Scroll to the bottom.",
   "- Nothing overlaps or is cut off; the sheet scrolls inside itself (max ~85% of the screen) and SET THE ICON is reachable.",
   "1) SCR top and bottom at large text.")

# --------------------------------------------------------------------------
# M2-03 Schema, schedule, RLS (database)
# --------------------------------------------------------------------------
tc("M2-03-TC01", "M2-03", "Schedule", "M2-03 done-when; Scope v6 §4 Deadline ('The period sets the end date')",
   "Signing stores the Icon terms and one day row per scheduled day", "P1", "Data", "DB",
   "An Icon signed in M2-04-TC01 (note its client id from Q-01).",
   "1. Run Q-01 and Q-02 for the Icon.\n2. Compare with the composer terms and the Active Icons line ('Session k of N').",
   "- Q-01: icon_weekdays = ISO weekday numbers of the chosen days (Mon = 1 … Sun = 7); icon_start_day = signing date; icon_period_count/unit as chosen; icon_end_day = start + period; icon_deadline_time = the cut-off; icon_timezone = the iPhone's zone (e.g. Asia/Ho_Chi_Minh); morning/evening times as set; status active.\n"
   "- Q-02: one row per scheduled day only; session_number 1..N with no gap; cutoff_local / morning_local / evening_local all at the chosen wall-clock times in the Icon's zone; every row pending.\n"
   "- N equals the 'of N' shown in Active Icons.",
   "1) DB Q-01.\n2) DB Q-02.\n3) SCR Active Icons line.")

tc("M2-03-TC02", "M2-03", "Schedule", "Scope v6 §4 ('Non-Oath days are ignored'), §7 ('Monday, Wednesday and Friday: no reminders, no tracking')",
   "Days that are not Icon days have no row", "P1", "Data", "DB",
   "An Icon on some weekdays only (e.g. Tue, Thu, Sat, Sun).",
   "1. Run Q-02.",
   "- No row for any Mon, Wed or Fri; each listed day falls on a selected weekday.",
   "1) DB Q-02.")

tc("M2-03-TC03", "M2-03", "Security", "M2-03 done-when ('Per-user Icon data is isolated'); AGENTS.md account isolation",
   "Another account cannot read the Icon data (RLS)", "P1", "Security", "DB",
   "ACC-A has an Icon with days and push tokens. Know the user ids of ACC-A and ACC-B (Q-00).",
   "1. Run Q-09 with OWNER = ACC-A and VIEWER = ACC-B.\n2. Run Q-09 with VIEWER = ACC-A (positive control).",
   "- Step 1: icon_days_visible = 0, contracts_visible = 0, push_tokens_visible = 0.\n- Step 2: ACC-A sees its own rows (counts > 0).",
   "1) DB Q-09 both runs.",
   "Pre-checked Oct 4 on production with a random viewer: 0 rows visible in contracts, icon_days and push_tokens (Automated Evidence AE-24).")

tc("M2-03-TC04", "M2-03", "Security", "M2-03 notes (icon_days select-only); docs/db/icon_v1.sql",
   "Clients cannot write Icon results or push internals", "P1", "Security", "DB",
   "None.",
   "1. Run Q-14.",
   "- authenticated cannot insert or update icon_days; cannot read apns_provider_tokens, icon_push_log or icon_push_sends; cannot run icon_push_tick; anon cannot read apns_provider_tokens; anon can call unregister_push_tokens (needed for sign-out).",
   "1) DB Q-14.",
   "Pre-checked Oct 4 (AE-25).")

# --------------------------------------------------------------------------
# M2-04 Signing, lock-in, active list, End early, reminder editing
# --------------------------------------------------------------------------
tc("M2-04-TC01", "M2-04", "Signing", "Scope v6 §3 step 8, §4 Signing and Lock-in",
   "Sign an Icon (self-reported activity)", "P1", "Functional", "iPhone app + DB",
   "S0. ICON-S data (Test Data). No Icon holds today.",
   "1. Activity: Custom 'Meditation'; Target 10 min; Because 'Quiet mind, steady word.'.\n2. Icon: the days in ICON-S, period as in ICON-S; reminders as in the Run Plan.\n3. Deadline (each Icon day): as in ICON-S.\n4. Sign with a finger and tap SIGN THIS CONTRACT.",
   "- The app returns to Home; 'YOUR CONTRACTS' shows an 'ICONS' row with 'Meditation · Session 1 of N · Today' (or 'Next: …').\n"
   "- Contract tab: 'ACTIVE ICONS' lists 'Meditation · 10 min', the gold terms summary, the progress line and an 'End early' link.\n"
   "- Q-01: the Icon with icon_metric = null (self-reported) and the chosen terms; Q-02 as in M2-03-TC01.\n- On a free plan the 'n of 12 sessions used' counter goes up by one.",
   "1) SCR Home after signing.\n2) SCR Active Icons.\n3) DB Q-01, Q-02.")

tc("M2-04-TC02", "M2-04", "Signing", "Scope v6 §4 Verification ('pull the relevant HealthKit metric')",
   "A measurable activity gets a Health metric", "P1", "Data", "iPhone app + DB",
   "S0. ICON-W data (Walking, 500 steps) on days free of other Icons.",
   "1. Sign ICON-W.\n2. Run Q-01.",
   "- icon_metric = 'steps', icon_target = 500, icon_unit = 'count'.\n"
   "- Mapping reference (for other Icons in this plan): 'Running 33 min' → exercise_minutes 33 min; 'Running 30 km' → distance_walking_running 30000 m; 'Cycling 10 km' → distance_cycling; a custom activity with minutes (e.g. Meditation) → no metric (self-report).",
   "1) DB Q-01 row.")

tc("M2-04-TC03", "M2-04", "Signing", "Existing V1.04 signing rules",
   "Required fields and signature", "P1", "Negative", "iPhone app",
   "S0. Icon set in the composer.",
   "1. Clear the activity and tap SIGN THIS CONTRACT.\n2. Fill the activity, clear Because, sign.\n3. Fill Because, leave the signature pad empty, sign.",
   "- 1: 'What are you committing to?'\n- 2: 'Because… must be filled.'\n- 3: 'Sign the contract.'\n- In every case nothing is signed and the draft (activity, Because, Icon terms) stays.",
   "1) SCR each message (3).")

tc("M2-04-TC04", "M2-04", "Signing", "Mike Sep 28 (evening reminder within 8 h of the deadline); E-44",
   "Evening reminder must be within 8 hours before the cut-off", "P1", "Boundary", "iPhone app",
   "S0. Icon set with Evening on. Deadline 23:00.",
   "1. Evening 14:59 → sign.\n2. Evening 15:00 → sign (cancel the signing gate if it appears, or use a test account).\n3. Deadline 18:00 with Evening 20:00 → sign.",
   "- 1 and 3: 'Set the evening reminder within 8 hours before the deadline.'; nothing signed; draft and signature kept.\n- 2: accepted (exactly 8 hours is allowed).",
   "1) SCR message (case 1).\n2) SCR message (case 3).",
   "Run case 2 last, or on a test account, since it signs an Icon.")

tc("M2-04-TC05", "M2-04", "Signing", "Scope v6 §5 Out of scope ('Multiple simultaneous Oaths for the same activity type')",
   "Only one active Icon per activity", "P1", "Negative", "iPhone app",
   "ACC-A has an active Icon 'Meditation'.",
   "1. Compose another Icon with activity 'meditation' (lower case, trailing space) on days the first Icon does not hold.\n2. Sign.",
   "- 'You already have an active Icon for meditation.'; nothing signed.",
   "1) SCR message.")

tc("M2-04-TC06", "M2-04", "Signing", "Implementation (ICON_NO_SESSIONS)",
   "An Icon with no session left cannot be signed", "P2", "Negative", "iPhone app",
   "S0. Today's time is after 01:00.",
   "1. Icon: only today's weekday selected, Custom 2 days, Evening reminder off (otherwise the 8-hour rule answers first).\n2. Deadline (each Icon day) 00:30 (earlier than now; not 00:00).\n3. Sign.",
   "- 'This Icon has no session left in its period.'; nothing signed.",
   "1) SCR message.",
   "Custom 2 days covers today and tomorrow; tomorrow is not selected, and today's cut-off has passed.")

tc("M2-04-TC07", "M2-04", "Signing", "Scope v6 §4 Live session count (observation)",
   "Signing after today's cut-off: count shown vs sessions created", "P3", "Edge", "iPhone app + DB",
   "S0 on a throwaway account. Every day, 1 Week, cut-off earlier than now (e.g. 09:00 when it is 10:00), Evening reminder off.",
   "1. Read the count in the sheet.\n2. Sign.\n3. Read Active Icons and Q-02.",
   "- The sheet shows 7 sessions.\n- The Icon has 6 sessions: today is skipped because its cut-off had passed at signing; Active Icons reads 'Next: <tomorrow> · Session 1 of 6'.",
   "1) SCR sheet count.\n2) SCR Active Icons.\n3) DB Q-02.",
   "Implemented behaviour. If the client wants the sheet to exclude a day whose cut-off has passed, log a change request.")

tc("M2-04-TC08", "M2-04", "Lock-in", "Scope v6 §4 ('days, period and target are locked for the full period'); §5 Editing after signing out of scope",
   "Signed terms are locked", "P1", "Functional", "iPhone app + DB",
   "An active Icon.",
   "1. Look for any way to edit days, period, target, activity or cut-off in Contract, Home and Settings.\n2. Run Q-10 (tries to change the terms as the owner, then rolls back).",
   "- The UI offers only End early (Contract tab) and reminder times (Settings › Icon reminders).\n- Q-10: the row read back after the update still has the original weekdays, period, target and primary_target.",
   "1) SCR Active Icons (no edit control).\n2) DB Q-10.")

tc("M2-04-TC09", "M2-04", "Reminder editing", "Scope v6 §4 ('remain editable in Settings after signing')",
   "Reminder times can be edited in Settings after signing", "P1", "Functional", "iPhone app + DB",
   "An active Icon with at least one day still ahead.",
   "1. Settings › ICON REMINDERS: the Icon's activity and terms are listed with Morning and Evening rows.\n2. Change Morning (e.g. 07:00 → 08:15), tap Save.\n3. Run Q-01 and Q-02.",
   "- Save turns into 'Saved'.\n- Q-01: icon_morning_time = 08:15.\n- Q-02: morning_local = 08:15 for every pending day whose cut-off is still ahead; past or stamped days keep their old time.",
   "1) SCR Settings section before/after Save.\n2) DB Q-01, Q-02.")

tc("M2-04-TC10", "M2-04", "Reminder editing", "Decision Oct 1 (12:00 rule); Mike Sep 28 (8-hour window, E-44)",
   "Reminder editor validation", "P1", "Negative", "iPhone app",
   "An active Icon with cut-off 22:00 (or any).",
   "1. Morning 12:30.\n2. Morning 07:00, Evening 11:00.\n3. Evening more than 8 hours before the cut-off (e.g. 13:00 for 22:00).",
   "- 1 and 2: 'Morning must be before 12:00, evening from 12:00.'; Save disabled.\n- 3: 'Set the evening reminder within 8 hours before the deadline.'; Save disabled.",
   "1) SCR each message.")

tc("M2-04-TC11", "M2-04", "Reminder editing", "Scope v6 §4 ('Either or both may be off'); icon-live-activity.md",
   "Both reminders off: no card and no reminder, the day is still scored", "P2", "Functional", "iPhone app + DB",
   "An active Icon with a day ahead.",
   "1. Settings › Icon reminders: turn both off, Save.\n2. On the next Icon day, watch the Lock Screen at the old reminder times.\n3. Run Q-02 and Q-04 for that day.",
   "- Q-02: morning_local and evening_local empty for the pending days.\n- No card and no notification that day; Q-04 has no morning or evening row for it.\n- The day is still stamped (HONOURED/BROKEN) as usual.",
   "1) DB Q-02.\n2) DB Q-04.\n3) SCR Active Icons showing the day's result.")

tc("M2-04-TC12", "M2-04", "Active Icons", "Scope v6 §4 ('User can view all active Oath contracts from the main Contract screen')",
   "Active Icons list on the Contract tab", "P1", "Functional", "iPhone app",
   "An active Icon; check on an Icon day and on a non-Icon day.",
   "1. Open the Contract tab on an Icon day.\n2. Repeat on a day that is not an Icon day.\n3. Repeat after the last cut-off while the last day is still pending (if observed).",
   "- 'ACTIVE ICONS' above the composer; each Icon shows: gold target icon, 'Activity · Target', gold terms summary, a progress line, today's result, recent day marks, notes, 'End early'.\n"
   "- Icon day: 'Session k of N · Today' and 'Today · Pending' / 'Today · HONOURED' / measured value.\n- Other day: 'Next: Tue 13 Oct · Session k of N'.\n- After the last cut-off: 'Period complete — results pending'.",
   "1) SCR each state.")

tc("M2-04-TC13", "M2-04", "Home", "M2-04 (Home compact Icons row, E-27)",
   "Home shows a compact Icons row", "P1", "Functional", "iPhone app",
   "An active Icon.",
   "1. Open Home.\n2. Tap the Icons row.",
   "- Under YOUR CONTRACTS: 'ICONS' with one line per active Icon, e.g. 'Meditation · Session 1 of 3 · Today · Pending' (or the result).\n- Tapping opens the Contract tab.",
   "1) SCR Home Icons row.")

tc("M2-04-TC14", "M2-04", "End early", "Scope v6 §4 ('Early exit is marked AMENDED')",
   "End an Icon early: AMENDED", "P1", "Functional", "iPhone app + DB",
   "An active Icon with days still ahead (use a throwaway Icon or the end of the plan).",
   "1. Contract tab › End early.\n2. Tap Cancel.\n3. End early again › End Icon.\n4. Check Home, History, Settings.\n5. Run Q-01 and Q-02.\n6. If a card was showing, put the app in the background and reopen it.",
   "- Dialog: 'End this Icon early?' / 'The remaining sessions will be marked AMENDED. This can't be undone.' / Cancel / End Icon.\n- Cancel changes nothing.\n"
   "- After End Icon: gone from Active Icons, Home and Settings › Icon reminders; History lists it as AMENDED (amber).\n"
   "- Q-01: status amended, resolved_at set. Q-02: days with a cut-off still ahead are amended (resolution amended); stamped days unchanged; a passed day still pending stays pending until scored.\n"
   "- No further card or reminder for it; a card on screen closes the next time the app becomes active.",
   "1) SCR dialog.\n2) SCR History entry.\n3) DB Q-01, Q-02.")

tc("M2-04-TC15", "M2-04", "Active Icons", "Scope v6 §4 ('view all active Oath contracts from the main Contract screen'); M2-15 allows a daily contract on non-Icon days",
   "Active Icons stay reachable while a daily contract is in force", "P1", "Functional", "iPhone app",
   "An active Icon that does NOT hold today (e.g. Icon on Mon/Wed, run on Tue). Sign an ordinary contract today with a deadline before the next Icon day.",
   "1. Open the Contract tab.\n2. From Home, tap the Icons row.\n3. If the Icon is self-reported and yesterday was an Icon day still inside its 24-hour window, look for the self-report prompt.",
   "- The Active Icons list, End early and any due self-report prompt are reachable while the daily contract is in force.",
   "1) SCR Contract tab.\n2) SCR after tapping the Home Icons row.",
   "PRE-IDENTIFIED RISK (found while writing this plan): with a daily contract in force the Contract tab shows only 'Your contract is in force', so the Active Icons list, End early and self-report are not shown. Expected to FAIL until fixed; an unreported self-report day would then expire BROKEN (no_data).")

# --------------------------------------------------------------------------
# M2-05 Verification and scoring
# --------------------------------------------------------------------------
tc("M2-05-TC01", "M2-05", "Scoring", "Mike Sep 28 #4 (HONOURED as soon as the target is met); M2-05 done-when",
   "Measured day stamped HONOURED as soon as the target is met", "P1", "Functional", "iPhone app + DB",
   "ICON-W active on today; today's steps below the target when you start (choose the target just above the current Home Steps tile, e.g. current 2,300 → target 3,000).",
   "1. Walk until the Home Steps tile passes the target.\n2. Bring the app to the foreground (or wait for a background Health upload).\n3. Watch Active Icons; run Q-02.",
   "- Before the target: Q-02 status pending, measured_value rising; Active Icons 'Today · <value> / <target> steps'.\n"
   "- After: 'Today · HONOURED' (Home row 'Honoured'); Q-02 status honoured, resolution target_met, measured_value ≥ target, scored_at before the cut-off.\n- A running card turns to HONOURED (see M2-08-TC03).",
   "1) SCR Active Icons before and after.\n2) DB Q-02 before and after.\n3) SCR Home Steps tile.")

tc("M2-05-TC02", "M2-05", "Scoring", "Mike Sep 28 #4 ('BROKEN waits for full-day data after the deadline'); bridge.md (one settle hour)",
   "BROKEN (target missed) only after the cut-off plus one hour", "P1", "Functional", "iPhone app + DB",
   "ICON-R (Running 30 km) active today; you move normally so some walking/running distance is recorded.",
   "1. Shortly after the cut-off, open the app; run Q-02.\n2. Open the app again more than 1 hour after the cut-off; run Q-02.\n3. Check Active Icons and the day marks.",
   "- Step 1: still pending with a measured_value; Active Icons shows 'Waiting for Apple Health data — results settle within 24 hours of the cut-off.'\n"
   "- Step 2: status broken, resolution target_missed, measured_value < 30000.\n- The day mark for that day is red; label '<Day d Mon>: Broken'.",
   "1) DB Q-02 at both times (timestamps visible).\n2) SCR Active Icons note and day mark.")

tc("M2-05-TC03", "M2-05", "Scoring", "Mike Sep 28 #5 (pending at most 24 h, then BROKEN); Scope v6 §4 ('Handle HealthKit permission denial gracefully with a clear message')",
   "No Health data: pending, then BROKEN (no_data) 24 hours after the cut-off, with a clear message", "P1", "Functional", "iPhone app + DB",
   "A measured Icon day (e.g. ICON-W2) and Health read access for its metric turned OFF before the day starts: iPhone Settings › Health › Data Access & Devices › Honoured.",
   "1. During the day and after the cut-off, open the app; run Q-02.\n2. 24–25 hours after the cut-off, run Q-02 and open Active Icons.\n3. Turn Health access back on.",
   "- Before 24 h: the day stays pending; it is never stamped BROKEN early (a declined permission is not read as zero).\n"
   "- After 24 h (cron every 15 min): status broken, resolution no_data, measured_value empty.\n"
   "- Active Icons shows: 'No Apple Health data was recorded for <Day d Mon>. If Honoured can't read Health, allow it in Settings › Health › Data Access & Devices › Honoured.'",
   "1) SCR iPhone Health access screen (off).\n2) DB Q-02 before and after 24 h.\n3) SCR Active Icons message.")

tc("M2-05-TC04", "M2-05", "Self-report", "M2-05 (unmeasured Icons are self-reported, E-28)",
   "Self-report today's session", "P1", "Functional", "iPhone app + DB",
   "ICON-S active; today is an Icon day (any time after 00:00).",
   "1. Contract tab › the Icon.\n2. Read the prompt; tap Honoured.\n3. Run Q-02.",
   "- Prompt: 'Did you honour today's session?' with BROKEN and HONOURED buttons (available from the start of the day, before the cut-off).\n"
   "- After Honoured: 'Today · HONOURED'; the prompt disappears; Home row 'Honoured'.\n- Q-02: status honoured, resolution self_reported.",
   "1) SCR prompt.\n2) SCR after reporting.\n3) DB Q-02.")

tc("M2-05-TC05", "M2-05", "Self-report", "M2-05 (24-hour window)",
   "Self-report a previous day within 24 hours of its cut-off", "P1", "Functional", "iPhone app + DB",
   "ICON-S; yesterday's day not reported and its cut-off less than 24 h ago.",
   "1. Contract tab › the Icon.\n2. Tap Broken for yesterday.\n3. Run Q-02.",
   "- Prompt reads 'Did you honour <Day d Mon>'s session?'.\n- After Broken: Q-02 broken, resolution self_reported; the day mark is red.",
   "1) SCR prompt.\n2) DB Q-02.")

tc("M2-05-TC06", "M2-05", "Self-report", "M2-05 (window closes 24 h after the cut-off)",
   "Self-report is not offered after the window or before the day", "P2", "Negative", "iPhone app + DB",
   "ICON-S with a day more than 24 h past its cut-off and unreported, and a future day.",
   "1. Open the Icon in the Contract tab.\n2. Run Q-02.",
   "- No prompt for the expired day or for a day that has not started.\n- The expired day becomes broken / no_data within 15 minutes of the 24-hour mark.",
   "1) SCR (no prompt).\n2) DB Q-02.")

tc("M2-05-TC07", "M2-05", "Finality", "O-05 (implemented as final)",
   "A stamped day never changes", "P2", "Data", "iPhone app + DB",
   "A day already stamped HONOURED (e.g. from M2-05-TC01).",
   "1. Keep walking and open the app several times; for a self-reported day, try to report again (reload the page first).\n2. Run Q-02.",
   "- status, resolution and scored_at stay as first stamped; no second prompt appears.",
   "1) DB Q-02 before/after.",
   "O-05 (finality) still awaits the client's confirmation.")

tc("M2-05-TC08", "M2-05", "Scoring", "Scope v6 §4 Verification (measure the relevant metric)",
   "Icon measurement matches Apple Health for the same day", "P2", "Data", "iPhone app + DB",
   "Daily reset hour 00:00 (Settings). A measured steps Icon day.",
   "1. Compare the Home Steps tile (today) with the Icon's measured value (Active Icons and Q-02) and Q-07.",
   "- Same value within one sync (the Icon day runs from 00:00 to the cut-off in the Icon's zone, read with the same Health source preference).",
   "1) SCR Home tile.\n2) DB Q-02, Q-07.",
   "With a reset hour other than 00:00 the Home day starts at the reset hour, so values can differ.")

tc("M2-05-TC09", "M2-05", "Scoring", "M2-05 notes (verification needs the iPhone app)",
   "In a desktop browser a measured Icon says the iPhone verifies it", "P3", "Functional", "Web",
   "ACC-A signed in on honour-your-word.lovable.app in a desktop browser; a measured Icon active.",
   "1. Open the Contract tab in the browser.",
   "- The Icon shows 'Results are verified by the Honoured iPhone app.'",
   "1) WEB screenshot.")

tc("M2-05-TC10", "M2-05", "Day marks", "M2-05 (recent marks)",
   "Recent day marks show each settled day", "P2", "Functional", "iPhone app",
   "An Icon with at least two settled days.",
   "1. Contract tab › the Icon.\n2. With VoiceOver, swipe over the dots.",
   "- One dot per settled day (last 7): green Honoured, red Broken, amber Amended.\n- VoiceOver reads e.g. 'Mon 5 Oct: Honoured'.",
   "1) SCR dots.\n2) REC VoiceOver (optional).")

# --------------------------------------------------------------------------
# M2-06 Push tokens
# --------------------------------------------------------------------------
tc("M2-06-TC01", "M2-06", "Push tokens", "M2-06 done-when; E-38",
   "Signing in registers the device and push-to-start tokens", "P1", "Functional", "iPhone app + DB",
   "Build installed; Notifications allowed; Live Activities on. Note: on Oct 4 production had 0 push tokens, so the app must register again.",
   "1. Open the app signed in as ACC-A (or sign in).\n2. Wait a few seconds; run Q-03.",
   "- One install (same 8-character install prefix) with a 'device' row (token_len 64) and a 'push_to_start' row (token_len > 64); environment sandbox; topic = the app's bundle id; os_version = the iPhone's iOS; live_activities_enabled true.\n- No token value appears anywhere (Q-03 shows a hash only).",
   "1) DB Q-03.")

tc("M2-06-TC02", "M2-06", "Push tokens", "E-38 (per-card update tokens)",
   "Each Icon card registers its update token", "P1", "Functional", "iPhone app + DB",
   "A card is showing (from M2-07-TC01 or the app).",
   "1. Bring the app to the foreground once after the card appears.\n2. Run Q-03.",
   "- An 'activity' row with contract_client_id = the Icon's client id and icon_day = today, same install.",
   "1) DB Q-03.",
   "A card the server starts gets its token only when iOS lets the app run (icon-push.md Limits).")

tc("M2-06-TC03", "M2-06", "Push tokens", "E-38 (Live Activities switch reported)",
   "Turning Live Activities off and on is reported", "P1", "Functional", "iPhone app + DB",
   "Signed in.",
   "1. iPhone Settings › Honoured › Live Activities: off. Return to the app.\n2. Run Q-03.\n3. Turn it back on, return to the app, run Q-03.",
   "- After 1: live_activities_enabled = false on the device and push_to_start rows.\n- After 3: true again.",
   "1) SCR iOS setting.\n2) DB Q-03 both times.")

tc("M2-06-TC04", "M2-06", "Push tokens", "M2-06 done-when ('clear safely'); bridge.md auth section",
   "Signing out removes the install's tokens and closes Icon cards", "P1", "Security", "iPhone app + DB",
   "Signed in with tokens registered (Q-03 shows rows); ideally a card showing. Note the 8-character install prefix.",
   "1. Sign out in the app.\n2. Run Q-03 and Q-03b (by install prefix).\n3. Look at the Lock Screen.",
   "- Q-03 for ACC-A: 0 rows; Q-03b: 0 rows for the install.\n- Every Icon card is gone.",
   "1) DB Q-03, Q-03b.\n2) LS after sign-out.")

tc("M2-06-TC05", "M2-06", "Push tokens", "M2-06 ('handle logout/account changes'); AGENTS.md account isolation",
   "Account switch moves the install to the new account", "P1", "Security", "iPhone app + DB",
   "ACC-A signed in with tokens and an Icon card; ACC-B available.",
   "1. Sign out, sign in as ACC-B.\n2. Run Q-03 for ACC-A and for ACC-B.\n3. Check Home, Contract and the Lock Screen as ACC-B.",
   "- ACC-A: 0 rows. ACC-B: device and push_to_start rows with the same install prefix.\n- ACC-A's cards are gone; ACC-B sees none of ACC-A's Icons, recaps or reminders.",
   "1) DB Q-03 (A and B).\n2) SCR Home as ACC-B.\n3) LS.")

tc("M2-06-TC06", "M2-06", "Push tokens", "E-38 (unregister retried offline)",
   "Sign-out while offline is completed when back online", "P2", "Edge", "iPhone app + DB",
   "Signed in with tokens.",
   "1. Airplane mode on; sign out.\n2. Run Q-03b (rows still there).\n3. Airplane mode off; open the app (signed out or signed in as another account).\n4. Run Q-03b.",
   "- Step 2: rows still present (could not reach the server).\n- Step 4: the old account's rows for this install are removed before anything new is registered.",
   "1) DB Q-03b at steps 2 and 4.")

tc("M2-06-TC07", "M2-06", "Push tokens", "M2-14 (reinstall); E-38 (Keychain installation id)",
   "Reinstalling keeps one install", "P2", "Edge", "iPhone app + DB",
   "Signed in; note the install prefix in Q-03.",
   "1. Delete the app (do not sign out).\n2. Reinstall the same build, sign in as ACC-A.\n3. Run Q-03.",
   "- Rows exist again under the same 8-character install prefix (no second install).",
   "1) DB Q-03 before and after.")

tc("M2-06-TC08", "M2-06", "Push tokens", "AGENTS.md ('tokens out of logs'); E-38",
   "Tokens and installation id never reach the logs", "P2", "Security", "iPhone app (Xcode console)",
   "Device connected to Xcode, Console capturing the Honoured process.",
   "1. Launch the app, sign in, let tokens register (Q-03).\n2. Search the captured log with the regular expression [0-9a-f]{64,} and for the words 'token' and 'installation'.",
   "- No APNs token, push-to-start token, installation id or access token appears in the log.",
   "1) LOG extract (search results empty).")

# --------------------------------------------------------------------------
# M2-07 Scheduler (server push)
# --------------------------------------------------------------------------
tc("M2-07-TC01", "M2-07", "Server push", "Scope v6 §4 ('Triggered by push-to-start from Supabase at each user's reminder times'); M2-07 done-when",
   "Morning card arrives at the reminder with the app closed", "P1", "Functional", "iPhone + push + DB",
   "ICON-S day today, pending; Morning reminder a few minutes ahead (Settings › Icon reminders); iOS 17.2+; Live Activities on; app force-quit (swipe away).",
   "1. Lock the iPhone and wait for the reminder time.\n2. Note the time the card appears.\n3. Run Q-04 and Q-05.",
   "- Within about 1 minute of the reminder the Icon card appears on the Lock Screen (morning line = the day's affirmation) with an 'Icon' alert.\n"
   "- Q-04: one row slot morning, channel live_activity_start, status sent, apns_status 200.\n- Q-05: the matching request, outcome sent.",
   "1) LS card with the clock visible.\n2) DB Q-04, Q-05.")

tc("M2-07-TC02", "M2-07", "Server push", "Scope v6 §4 ('appears … again at the evening reminder time'); E-44 (fresh evening card)",
   "Evening: a fresh card replaces the morning card", "P1", "Functional", "iPhone + push + DB",
   "After M2-07-TC01 the app was opened once, so Q-03 has an 'activity' row for today (the morning card's token). App in the background or closed; iPhone locked; evening reminder ahead.",
   "1. Wait for the evening reminder with the iPhone locked.\n2. Run Q-04 and Q-05.",
   "- Within about 1 minute: one Icon card on the Lock Screen with 'Finish what you signed.' and an alert; the morning card is gone (if two cards remain, record it: the morning card's update token had not reached the server, see icon-push.md Limits).\n"
   "- Q-05: a live_activity_start (auxiliary false) and, if the morning card's token was registered, a live_activity_end with auxiliary true.\n- Q-04: slot evening, status sent.",
   "1) LS evening card.\n2) DB Q-04, Q-05.")

tc("M2-07-TC03", "M2-07", "Server push", "Scope v6 §3 step 12; Mike Sep 28 #4; M2-09",
   "HONOURED reaches the card while the app is closed", "P1", "Functional", "iPhone + push + DB",
   "The evening card showing for today's ICON-S day and its token on the server: Q-03 'activity' row for today with a token_hash that changed after the evening card appeared (if not, open the app once and lock again). The iPhone app closed; ACC-A signed in on a desktop browser.",
   "1. In the browser, self-report today as Honoured.\n2. Watch the iPhone Lock Screen.\n3. Run Q-04, Q-05.",
   "- Within 1–2 minutes the card shows HONOURED in gold, without an alert.\n- Q-04: slot result, channel live_activity_update, status sent.",
   "1) WEB after reporting.\n2) LS HONOURED card.\n3) DB Q-04.")

tc("M2-07-TC04", "M2-07", "Server push", "Scope v6 §4 ('runs until the deadline … and closes')",
   "The card closes at the cut-off", "P1", "Functional", "iPhone + push + DB",
   "A card showing today whose token is on the server (Q-03 'activity' row updated after the card appeared; if not, open the app once). App closed.",
   "1. Watch the Lock Screen at the cut-off.\n2. Run Q-04.",
   "- Within about 1 minute after the cut-off the card is removed.\n- Q-04: slot end, channel live_activity_end, status sent.",
   "1) LS just before and just after the cut-off.\n2) DB Q-04.")

tc("M2-07-TC05", "M2-07", "Server push", "Scope v6 §4 ('Silent on non-Oath days'); §7",
   "Nothing on days that are not Icon days", "P1", "Functional", "iPhone + DB",
   "An active Icon with a non-Icon day.",
   "1. On the non-Icon day, watch the Lock Screen at the reminder times.\n2. Run Q-04.",
   "- No card and no notification; Q-04 has no row for that date.",
   "1) DB Q-04.")

tc("M2-07-TC06", "M2-07", "Server push", "M2-07 done-when ('without duplicates')",
   "Each appearance is sent once", "P1", "Data", "DB",
   "After M2-07-TC01..TC04 ran on one day.",
   "1. Run Q-04 and Q-05 for that day.",
   "- Q-04: exactly one row per slot (morning, evening, result, end).\n- Q-05: no repeated request for a slot except retries after a 5xx/timeout (outcome retry) or the evening close (auxiliary).",
   "1) DB Q-04, Q-05.")

tc("M2-07-TC07", "M2-07", "Server push", "icon-push.md ('only within 15 minutes of its time')",
   "A reminder already more than 15 minutes old is not sent", "P2", "Edge", "iPhone + DB",
   "ICON-S day today, morning slot not sent yet today.",
   "1. Settings › Icon reminders: set Morning 20 minutes in the past, Save.\n2. Wait 2 minutes; run Q-04.\n3. Set Morning 3 minutes ahead, Save; wait.",
   "- After step 2: no morning row and no card.\n- After step 3: the card arrives at the new time (M2-07-TC01).",
   "1) DB Q-04 after step 2 and after step 3.",
   "Run this before M2-07-TC01 on the same day: each slot is sent once per day.")

tc("M2-07-TC08", "M2-07", "Server push", "M2-07 ('timezone-aware'); icon_v1.sql (times in the Icon's zone)",
   "Reminder times follow the Icon's time zone", "P2", "Edge", "iPhone + DB",
   "An Icon signed in the iPhone's home zone (e.g. Asia/Ho_Chi_Minh).",
   "1. Change the iPhone's time zone (Settings › General › Date & Time, automatic off) to e.g. Australia/Sydney.\n2. Wait for the next reminder.\n3. Restore automatic time.",
   "- The reminder arrives at the Icon-zone time (e.g. 08:15 Ho Chi Minh = 12:15 Sydney), not at 08:15 Sydney.\n- The card's 'Due …' shows the cut-off converted to the iPhone's current zone.",
   "1) LS card with the clock.\n2) DB Q-02 (morning_local in the Icon's zone).")

tc("M2-07-TC09", "M2-07", "Server push", "M2-07 ('sandbox/production split')",
   "Development build uses the sandbox gateway", "P2", "Configuration", "DB",
   "Development build signed in.",
   "1. Run Q-03 and Q-05 after any push.",
   "- Tokens are environment sandbox and pushes to them succeed (outcome sent).\n- Production gateway: tested with the App Store/TestFlight build once O-11 is done.",
   "1) DB Q-03, Q-05.",
   "Production half blocked by O-11 (Push on the production App ID).")

tc("M2-07-TC10", "M2-07", "Server push", "icon-push.md (410 / Unregistered removes the token)",
   "A dead token is removed after APNs rejects it", "P3", "Edge", "iPhone + DB",
   "A throwaway account with an Icon day today and a reminder ahead; tokens registered.",
   "1. Delete the app without signing out.\n2. After the next reminder, run Q-03 and Q-05.",
   "- Q-05: the push gets 410 (or BadDeviceToken/Unregistered), outcome drop-token.\n- Q-03: that token row is gone.",
   "1) DB Q-05, Q-03.",
   "APNs may keep accepting pushes for a short while after deletion; repeat at the next reminder if needed.")

tc("M2-07-TC11", "M2-07", "Server push", "E-41 (pg_cron icon-push every minute)",
   "The push job and the expiry job are running", "P1", "Operational", "DB",
   "None.",
   "1. Run Q-06.",
   "- icon-push: schedule '* * * * *', active, about 60 runs in the last hour, 0 failed.\n- icon-days-expire: '*/15 * * * *', active, 4 runs in the last hour, 0 failed.",
   "1) DB Q-06.")

# --------------------------------------------------------------------------
# M2-08 Card layout
# --------------------------------------------------------------------------
tc("M2-08-TC01", "M2-08", "Card layout", "Scope v6 §4 The Oath Card rows 1–4; Mike Sep 28 #2 (no progress bar); E-33",
   "Lock Screen card, morning", "P1", "Functional", "iPhone (Lock Screen)",
   "A morning card showing (M2-07-TC01).",
   "1. Lock the iPhone and capture the card.",
   "- Black card, gold accents, serif title.\n- Row 1: gold infinity mark, 'Icon', '<WEEKDAY> · <k> OF <N>' (e.g. 'FRI · 1 OF 3').\n"
   "- Row 2: target value and unit in capitals with the activity (e.g. '10 MIN · Meditation').\n- Row 3: the Because line in italics.\n"
   "- Row 4: the person's signature in white ink, the day's affirmation in gold, 'Due <cut-off>'.\n- No progress bar.",
   "1) LS card.",
   "Reference renders: docs/phase2/evidence/m2-qa/automated/card-renders/icon-lock-*.png (AE-08).")

tc("M2-08-TC02", "M2-08", "Card layout", "Scope v6 §4 Row 4 (evening line); Mike Sep 28 #2",
   "Lock Screen card, evening", "P1", "Functional", "iPhone (Lock Screen)",
   "An evening card showing (M2-07-TC02).",
   "1. Capture the card.",
   "- Same rows as the morning card; row 4 line 'Finish what you signed.'; no progress bar or remaining amount.",
   "1) LS card.")

tc("M2-08-TC03", "M2-08", "Card layout", "Scope v6 §3 step 12; E-33",
   "Result state HONOURED", "P1", "Functional", "iPhone (Lock Screen)",
   "A card after the day is stamped HONOURED (M2-07-TC03 or M2-05-TC01).",
   "1. Capture the card.",
   "- Row 4 reads 'HONOURED' in gold; the card stays until the cut-off.",
   "1) LS card.")

tc("M2-08-TC04", "M2-08", "Card layout", "E-31 (00:00 cut-off = midnight that ends the day); E-33",
   "A 00:00 cut-off reads 'Due midnight'", "P2", "Functional", "iPhone (Lock Screen)",
   "An Icon whose deadline (each Icon day) is 00:00.",
   "1. Capture its card.",
   "- 'Due midnight'; the card stays until midnight at the end of the Icon day.",
   "1) LS card.")

tc("M2-08-TC05", "M2-08", "Card layout", "Scope v6 §4 ('Affirmations rotate — one new affirmation per Oath day'); O-12 approved Oct 4",
   "Affirmations rotate one per session", "P1", "Functional", "iPhone (Lock Screen)",
   "Morning cards on two consecutive sessions of one Icon.",
   "1. Capture the morning card of session 1 and of session 2.",
   "- Session 1: 'You've got this.'; session 2: 'You're closer than you think.'. The order continues: 3 'Today is part of the promise.', 4 'Keep your word to yourself.', 5 'Small steps, kept promises.', 6 'Become what you signed.', 7 'Prove it again today.', 8 back to 'You've got this.'.",
   "1) LS card session 1.\n2) LS card session 2.",
   "Server copy checked Oct 4: icon_copy_affirmation(1..8) returns this order (AE-20). Renders of all seven: AE-08.")

tc("M2-08-TC06", "M2-08", "Signature", "Scope v6 §1 ('carrying the user's signature'); E-34; O-11",
   "The card shows the person's own signature", "P1", "Functional", "iPhone (Lock Screen) + DB",
   "An Icon signed with a distinctive signature; after signing, the app opened at least once (signatures sync at most every 15 minutes).",
   "1. Capture the card.\n2. Run Q-12.",
   "- The signature on the card is the one drawn at signing, as white ink on the black card.\n- Q-12: has_signature true for the Icon.",
   "1) SCR of the signature pad just before signing.\n2) LS card.\n3) DB Q-12.",
   "Development App IDs have the App Group (E-34); the production App IDs still need it (O-11).")

tc("M2-08-TC07", "M2-08", "Dynamic Island", "Mike Sep 28 #3 (simple Dynamic Island: mark and target); client Oct 5 (island hidden inside Honoured)",
   "Dynamic Island: compact, minimal and expanded", "P2", "Functional", "iPhone with Dynamic Island",
   "A card showing for a self-reported Icon (ICON-S); iPhone 14 Pro or later.",
   "1. Unlock and go to the Home Screen: capture the compact view.\n2. Start a timer in the iOS Clock app so two Live Activities share the island: capture the minimal view.\n3. Long-press the Icon in the island: capture the expanded view.\n4. Open Honoured: capture the top of the screen.",
   "- Compact: mark and target (a self-reported Icon has no Health total).\n- Minimal: mark.\n- Expanded: the card's rows without the Because line.\n- Inside Honoured the island does not show the card: iOS shows an app's own Live Activity only while that app is not in the foreground.",
   "1) DI compact.\n2) DI minimal.\n3) DI expanded.\n4) SCR in Honoured.",
   "Skip on an iPhone without Dynamic Island. Measured Icons: M2-08-TC11.")

tc("M2-08-TC08", "M2-08", "Card layout", "Scope v6 §4 ('Final height must fit Apple's Live Activity size limit'); E-33",
   "Card fits at the largest text size", "P2", "Usability", "iPhone (Lock Screen)",
   "Larger Text at the largest standard size; a card showing.",
   "1. Capture the card.",
   "- All four rows visible; affirmation, line and 'Due …' on one line; nothing clipped.",
   "1) LS card at large text.",
   "Renders at the largest allowed size: max 153 pt of 160 (E-33, AE-08).")

tc("M2-08-TC09", "M2-08", "Card layout", "E-33 (activity ≤ 40, Because ≤ 120 characters)",
   "Long activity and Because text", "P3", "Edge", "iPhone (Lock Screen)",
   "An Icon with a 40-character activity and a 120-character Because.",
   "1. Capture the card.",
   "- Text is shortened to fit; layout intact; no overlap with the signature or 'Due …'.",
   "1) LS card.",
   "Automated render 'icon-lock-long-text' (AE-08).")

tc("M2-08-TC10", "M2-08", "Card", "icon-live-activity.md ('The card has no actions; a tap opens the app')",
   "Tapping the card opens the app", "P2", "Functional", "iPhone",
   "A card showing.",
   "1. Tap the card on the Lock Screen and unlock.",
   "- Honoured opens; no other action.",
   "1) REC.")

tc("M2-08-TC11", "M2-08", "Dynamic Island", "Client Oct 5 ('where the tick is, it still should give the current Health Kit data for the activity I've chosen')",
   "The island shows the day's Health total, also after HONOURED", "P1", "Functional", "iPhone with Dynamic Island + DB",
   "ICON-W (steps) signed with Morning at a time already past (not off), so its card shows before the target is met; some steps already recorded today; iPhone 14 Pro or later.",
   "1. Open Health › Steps and note today's total; open Honoured, then go to the Home Screen: capture the compact and the expanded view.\n2. Walk about 300 steps; open Honoured for a few seconds, then go to the Home Screen: capture the compact view.\n3. Keep walking until the target is met and the card shows HONOURED: capture the compact and the expanded view.\n4. Walk about 300 more steps; open Honoured, then the Home Screen: capture the compact view.\n5. Run Q-02.",
   "- Before HONOURED: compact shows the day's total in the target's unit (e.g. 2,840), matching Health; expanded shows '2,840 / 3,000 STEPS · Walking'.\n- The total rises after the walk in step 2.\n- After HONOURED: compact shows the total in gold, not a tick; expanded shows HONOURED with the total before the target.\n- The total keeps rising after HONOURED (step 4).\n- The figure is never 0 when Health has steps, and never shown for a self-reported Icon.",
   "1) SCR Health steps.\n2) DI compact and expanded before.\n3) DI compact after the walk.\n4) DI compact and expanded after HONOURED.\n5) DI compact after more steps.\n6) DB Q-02.",
   "The total refreshes whenever the app runs, in the foreground or for a background Health delivery (the phone must be unlocked to read Health). Renders: AE-29.")

tc("M2-08-TC12", "M2-08", "Dynamic Island", "Client Oct 5; icon-push.md (card pushes carry the last reported total)",
   "A push keeps the island's total", "P2", "Functional", "iPhone with Dynamic Island + DB",
   "ICON-W pending with a total already reported (Q-02 measured_value set) and its morning card showing; iPhone locked before the evening reminder.",
   "1. Before the evening reminder note measured_value (Q-02).\n2. Keep the app closed through the evening reminder.\n3. Unlock and go to the Home Screen: capture the compact view; run Q-04.",
   "- The fresh evening card shows the reported total (Q-02 measured_value, in the target's unit), not the target.\n- Q-04: evening slot sent as live_activity_start.",
   "1) DB Q-02 before.\n2) DI compact.\n3) DB Q-04.",
   "Needs the new native build; icon_push_v4.sql is on production since Oct 5 and matches plan.ts 35/35 (AE-30).")

# --------------------------------------------------------------------------
# M2-09 Card lifecycle and fallback
# --------------------------------------------------------------------------
tc("M2-09-TC01", "M2-09", "Lifecycle", "E-36 (the app keeps cards right whenever it runs)",
   "The app opens the day's card when the push did not", "P2", "Functional", "iPhone + DB",
   "An Icon day with a reminder ahead; the iPhone in Airplane mode from 2 minutes before the reminder until 20 minutes after it.",
   "1. After the reminder (+20 min), turn Airplane mode off and open the app.\n2. Watch the Lock Screen/Dynamic Island; run Q-04.",
   "- One card for the day appears (opened by the app or by the late push; never two).\n- Q-04 shows the slot recorded once.",
   "1) LS card.\n2) DB Q-04.",
   "APNs may still deliver the stored push on reconnection; either way exactly one card must remain.")

tc("M2-09-TC02", "M2-09", "Lifecycle", "E-36 (a morning card goes stale at the evening reminder)",
   "A morning card turns to the evening line on its own", "P2", "Functional", "iPhone",
   "A morning card showing; Airplane mode on from 5 minutes before the evening reminder.",
   "1. Watch the card at the evening reminder (still offline).",
   "- At the evening reminder the same card shows 'Finish what you signed.' without any network.",
   "1) LS before and after the evening time.")

tc("M2-09-TC03", "M2-09", "Lifecycle", "E-44 (3-minute grace; never two cards)",
   "App open at the evening reminder: one fresh card", "P1", "Functional", "iPhone",
   "A morning card showing; the app in the foreground at the evening reminder.",
   "1. Keep the app open across the evening reminder for 4 minutes.\n2. Check the Dynamic Island / Lock Screen.",
   "- Exactly one Icon card after 4 minutes, on the evening line; the morning card is gone.",
   "1) REC across the reminder.\n2) LS after 4 minutes.")

tc("M2-09-TC04", "M2-09", "Lifecycle", "E-38 (a swiped-away card is not reopened until the next appearance)",
   "A card swiped away stays away until the next appearance", "P1", "Functional", "iPhone",
   "A morning card showing.",
   "1. Swipe the card away on the Lock Screen.\n2. Open and close the app.\n3. Wait for the evening reminder.",
   "- After step 2: no new morning card.\n- Step 3: the evening card appears.",
   "1) LS after step 2.\n2) LS evening card.")

tc("M2-09-TC05", "M2-09", "Lifecycle", "Scope v6 §3 step 12; icon-live-activity.md",
   "HONOURED stays until the cut-off, then the card closes", "P1", "Functional", "iPhone",
   "A day stamped HONOURED before its cut-off with its card showing.",
   "1. Watch the card until the cut-off.",
   "- HONOURED shown until the cut-off; then the card closes (M2-07-TC04).",
   "1) LS HONOURED.\n2) LS after the cut-off.")

tc("M2-09-TC06", "M2-09", "Lifecycle", "Mike Sep 28 #4 (BROKEN waits until after the deadline); icon-live-activity.md",
   "A day stamped BROKEN or amended closes the card", "P2", "Functional", "iPhone",
   "A card showing for a self-reported Icon.",
   "1. Self-report today as Broken in the app.\n2. Put the app in the background and reopen it.",
   "- The card closes (it does not show BROKEN). A measured day is only stamped BROKEN after the cut-off, when its card has already closed, so BROKEN is not expected on a card.",
   "1) LS before and after.",
   "Scope §3 step 12 says the card shows the result briefly; with BROKEN decided after the deadline (Mike #4) only HONOURED can be shown.")

tc("M2-09-TC07", "M2-09", "Fallback", "Scope v6 §4 Fallback; M2-09 done-when; icon-push.md",
   "Live Activities off: quiet notifications with the same text", "P1", "Functional", "iPhone + push + DB",
   "iPhone Settings › Honoured › Live Activities off (Q-03 shows false); Notifications allowed; an Icon day with morning and evening reminders ahead; app closed.",
   "1. Wait for the morning reminder.\n2. Wait for the evening reminder.\n3. Run Q-04, Q-05.",
   "- A notification without sound: title 'Icon', subtitle '<Activity> · <target>' (e.g. 'Meditation · 10 min'), body '<affirmation> Due <cut-off>.' in the morning and 'Finish what you signed. Due <cut-off>.' in the evening (time in the Icon's zone).\n"
   "- No Live Activity appears.\n- Q-04/Q-05: channel alert, status sent.",
   "1) LS morning notification.\n2) LS evening notification.\n3) DB Q-04.")

tc("M2-09-TC08", "M2-09", "Fallback", "icon-push.md ('In the foreground the app does not show it')",
   "No notification banner while the app is open", "P2", "Functional", "iPhone",
   "Live Activities off; app in the foreground at a reminder time.",
   "1. Keep Honoured open across the reminder.",
   "- No banner is shown inside the app.",
   "1) REC across the reminder.")

tc("M2-09-TC09", "M2-09", "Fallback", "Scope v6 §4 ('on iOS below 17.2 … standard push')",
   "iOS below 17.2", "P3", "Compatibility", "iPhone/iPad iOS 16.x–17.1",
   "A device on iOS 16.2–17.1 with the build.",
   "1. Run M2-07-TC01 and M2-07-TC02 on it.",
   "- Without push-to-start: the morning reminder is a quiet notification; once the app has opened a card, the evening comes as an update of that card with an alert.",
   "1) LS.\n2) DB Q-04, Q-05.",
   "Mark N/A without such a device. Server plan covered by plan_test.ts and SQL parity (E-41, E-44).")

tc("M2-09-TC10", "M2-09", "Lifecycle", "icon-live-activity.md ('Sign-out and account switch close every card')",
   "Signing out closes every Icon card", "P1", "Security", "iPhone",
   "A card showing.",
   "1. Sign out.",
   "- The card disappears immediately (see also M2-06-TC04).",
   "1) LS after sign-out.")

tc("M2-09-TC11", "M2-09", "Lifecycle", "Apple: a Live Activity lasts at most 8 hours (E-06); client Oct 6 (renewal)",
   "Morning reminder only: a card shows until the cut-off", "P2", "Edge", "iPhone",
   "An Icon with Morning on and Evening off; cut-off more than 8 hours after the morning reminder; APNS_ENVIRONMENT includes the phone's gateway.",
   "1. Note when each Icon card appears and disappears, without opening the app.",
   "- No card lasts more than 8 hours (iOS), but a fresh one replaces it before then, so an Icon card shows from the morning reminder until the cut-off.",
   "1) LS times.\n2) DB Q-04 (renew-<seconds> slots).",
   "Before Oct 6 the card simply ended after 8 hours. See M2-09-TC13.")

tc("M2-09-TC12", "M2-09", "Lifecycle", "Client Oct 6 (island gone for hours); ActivityKit: a Live Activity lasts up to eight hours",
   "Opening the app renews an old card, unseen", "P1", "Functional", "iPhone with Dynamic Island",
   "A measured Icon day with a card showing that started at least an hour ago and would run out before the cut-off (e.g. Morning 07:00, Evening off, cut-off 00:00, at 09:00 or later).",
   "1. Note the time; open Honoured for a few seconds.\n2. Go to the Home Screen: capture the compact and the expanded island.\n3. Lock the phone: capture the Lock Screen.",
   "- The card in the island and on the Lock Screen looks the same as before (same line and total); no notification, no sound.\n- Only one Icon card on the Lock Screen.\n- Xcode console: an Icon card started and the old one ended.",
   "1) DI compact and expanded.\n2) LS.\n3) LOG.",
   "Needs a build with the app-side renewal (after Oct 6). Automated: AE-31.")

tc("M2-09-TC13", "M2-09", "Lifecycle", "Client Oct 6; icon_push_v5.sql",
   "The server renews a card before iOS ends it", "P1", "Functional", "iPhone with Dynamic Island + DB",
   "APNS_ENVIRONMENT includes the phone's gateway (production for TestFlight). A card started by the morning push or the app; the app not opened afterwards; Evening off; cut-off more than 8 hours after the card started.",
   "1. Keep the app closed. About 7 h 40 min after the card started, watch the phone.\n2. Capture the Lock Screen and, unlocked, the island.\n3. Run Q-04 (expect a renew-<seconds> slot) and Q-05.",
   "- The phone lights up silently with the card's line (Apple requires an alert to start a card by push).\n- One fresh card in the island and on the Lock Screen, same line and total; the old one closed.\n- Q-04: renew-<seconds> sent as live_activity_start; Q-05: one end (auxiliary) and one start, both 200.",
   "1) LS at the renewal.\n2) DI compact.\n3) DB Q-04 and Q-05.",
   "Blocked for the client's TestFlight phone until APNS_ENVIRONMENT includes production (Oct 6). Automated: AE-32.")

tc("M2-09-TC14", "M2-09", "Lifecycle", "Client Oct 6; ActivityKit (ended cards stay on the Lock Screen up to four hours)",
   "A card iOS ended comes back when the app opens", "P2", "Edge", "iPhone",
   "A card that started more than 8 hours ago and was not renewed (Airplane mode through the renewal time, app closed); the day not yet at its cut-off.",
   "1. Unlock: the island shows no Icon card; the Lock Screen may still show the ended card.\n2. Open Honoured, then go to the Home Screen.",
   "- A fresh Icon card in the island, on the line of the moment.\n- A card the person had removed from the Lock Screen is not brought back by opening the app.",
   "1) DI before and after.\n2) LS.",
   "Automated: AE-31.")

# --------------------------------------------------------------------------
# M2-10 Weekly / monthly recap
# --------------------------------------------------------------------------
tc("M2-10-TC01", "M2-10", "Recap", "Scope v6 §4 Weekly & Monthly Recap; O-15 approved Oct 4",
   "Weekly recap appears once, on Home, after the week", "P1", "Functional", "iPhone app",
   "ACC-A had Icon days last week (Mon–Sun), all stamped.",
   "1. Open the app on Home in the new week.\n2. Read the screen; tap Continue.\n3. Close and reopen the app.",
   "- A full-screen recap: 'Your week', the range (e.g. '28 SEP – 4 OCT'), three counts in order Honoured / Amended / Broken, then the tone lines, and a Continue button.\n"
   "- After Continue it does not come back (also not after a relaunch).",
   "1) SCR recap.\n2) SCR Home after relaunch.")

tc("M2-10-TC02", "M2-10", "Recap", "M2-10 done-when ('Counts reconcile to daily results')",
   "Recap counts match the stamped days", "P1", "Data", "iPhone app + DB",
   "The recap from M2-10-TC01.",
   "1. Run Q-08 for the same Monday–Sunday.",
   "- Honoured and Broken equal Q-08's honoured and broken; Amended equals amended_icons (Icons ended early that week); pending = 0.",
   "1) SCR recap.\n2) DB Q-08.")

tc("M2-10-TC03", "M2-10", "Recap", "Scope v6 ('Strong week … You slayed it this week.')",
   "Strong week", "P1", "Functional", "iPhone app",
   "A week with more Honoured than Broken.",
   "1. Read the recap lines.",
   "- Exactly one line: 'You slayed it this week.'",
   "1) SCR recap.")

tc("M2-10-TC04", "M2-10", "Recap", "Scope v6 (difficult week; 'Even one Honoured session … That's one more than zero.'); O-15",
   "Difficult week with Honoured sessions", "P1", "Functional", "iPhone app",
   "A week with Honoured ≤ Broken and at least one Honoured.",
   "1. Read the recap lines.",
   "- 'I believe in you even though this week has been challenging. Keep the dream alive and chase it. Let's start this week energized and use last week as kindle to start the flame.'\n"
   "- Then 'That's one more than zero.' (1 Honoured) or 'That's two more than zero.' etc.",
   "1) SCR recap.")

tc("M2-10-TC05", "M2-10", "Recap", "O-15 rules (a tie is a tough period); Scope v6",
   "Difficult week without Honoured, and a tie", "P2", "Functional", "iPhone app",
   "A week with 0 Honoured (or Honoured = Broken).",
   "1. Read the recap lines.",
   "- 0 Honoured: only the difficult-week paragraph.\n- Tie: the difficult-week paragraph and 'That's <n> more than zero.'",
   "1) SCR recap.")

tc("M2-10-TC06", "M2-10", "Recap", "M2-10 (shown once every day of the period is stamped)",
   "The recap waits while a day of the week is pending", "P2", "Functional", "iPhone app + DB",
   "Last week's Sunday still pending (e.g. a self-report Icon not yet reported).",
   "1. Open Home on Monday: no recap.\n2. Report Sunday (or wait for the 24-hour rule), return to Home.",
   "- No recap while Q-08 shows pending > 0.\n- The recap appears once the day is stamped.",
   "1) SCR Home without recap + DB Q-08 (pending > 0).\n2) SCR recap.")

tc("M2-10-TC07", "M2-10", "Recap", "O-15 rules; Scope ('Shows totals Honoured, Amended and Broken')",
   "No recap for a week with nothing stamped Honoured or Broken", "P3", "Edge", "iPhone app",
   "A week where the only Icon was ended early before any day was stamped.",
   "1. Open Home the next week.",
   "- No weekly recap.",
   "1) SCR Home.")

tc("M2-10-TC08", "M2-10", "Recap", "Scope v6 ('end of each week and month'); O-15 monthly wording",
   "Monthly recap", "P1", "Functional", "iPhone app + DB",
   "Icon days in the previous calendar month, all stamped (first observable on 1 Nov 2026 for October).",
   "1. Open the app on Home in the new month.\n2. If a weekly recap is also due, continue.",
   "- 'Your month', the month name (e.g. 'OCTOBER'), the three counts, and 'You slayed it this month.' or the month version of the difficult paragraph ('… this month has been challenging … use last month as kindle …') plus 'That's … more than zero.' when it applies.\n"
   "- When both are due, the month recap comes first, then the week.",
   "1) SCR monthly recap.\n2) DB Q-08 for the month.",
   "Before Nov 1 this can only be seen by moving the iPhone clock forward on a throwaway account (see Run Plan note); unit tests cover the rules (AE-15).")

tc("M2-10-TC09", "M2-10", "Recap", "Implementation (shown on Home only)",
   "A recap never interrupts another screen", "P2", "Functional", "iPhone app",
   "Last week's last Icon day still pending (self-report Icon), so no recap yet.",
   "1. On the Contract tab, report that day.\n2. Stay on the Contract tab for a minute.\n3. Go to Home.",
   "- No recap appears on the Contract tab; it appears as soon as Home is shown.",
   "1) SCR Contract tab.\n2) SCR recap on Home.")

# --------------------------------------------------------------------------
# M2-11 End of an Icon
# --------------------------------------------------------------------------
tc("M2-11-TC01", "M2-11", "End of Icon", "M2-11 done-when; O-15 (closing rule approved)",
   "An Icon closes after its last cut-off once every day is stamped", "P1", "Functional", "iPhone app + DB",
   "ICON-S (3 days) with every day stamped and the last cut-off passed.",
   "1. Open the app.\n2. Check Home, Contract tab, Settings › Icon reminders, History.\n3. Run Q-01.",
   "- The Icon leaves Home, Active Icons and Settings › Icon reminders.\n- History keeps one entry per stamped day (M2-11-TC06); the closed Icon adds no entry of its own.\n"
   "- Q-01: status honoured/broken; resolved_at = the last cut-off.",
   "1) SCR History.\n2) DB Q-01.")

tc("M2-11-TC02", "M2-11", "End of Icon", "M2-11 done-when; O-15",
   "End-of-Icon summary, strong record", "P1", "Functional", "iPhone app",
   "An Icon that closed with Honoured > Broken (ICON-S: 2 Honoured, 1 Broken).",
   "1. Open the app on Home.",
   "- Full screen: gold target icon, 'Icon complete', '<Activity> · <target>', '2 of 3 sessions honoured', 'You kept your word. You became an Icon.', buttons GO AGAIN and Not now.\n- No HONOURED/BROKEN stamp.\n- Shown once.",
   "1) SCR summary.")

tc("M2-11-TC03", "M2-11", "End of Icon", "O-15 (tough line; tie closes BROKEN)",
   "End-of-Icon summary, tough record", "P1", "Functional", "iPhone app + DB",
   "An Icon that closed with Honoured ≤ Broken (e.g. 1 of 2: one honoured, one broken).",
   "1. Open the app on Home.\n2. Run Q-01.",
   "- '1 of 2 sessions honoured', 'This Icon tested you, and you saw it through. Keep the dream alive and use these days as kindle to start the next flame.' and 'That's one more than zero.'\n- Q-01: status broken (a tie closes BROKEN).",
   "1) SCR summary.\n2) DB Q-01.")

tc("M2-11-TC04", "M2-11", "End of Icon", "M2-11 (after the last result)",
   "No closing while the last day is pending", "P2", "Functional", "iPhone app",
   "An Icon past its last cut-off with the last day pending.",
   "1. Open the Contract tab.",
   "- Active Icons shows 'Period complete — results pending'; no summary yet.\n- After the day is stamped the Icon closes and the summary appears.",
   "1) SCR pending state.\n2) SCR summary later.")

tc("M2-11-TC05", "M2-11", "End of Icon", "Scope v6 (early exit is AMENDED)",
   "An Icon ended early gets no summary", "P2", "Functional", "iPhone app",
   "An Icon ended early (M2-04-TC14).",
   "1. Open Home after its original end date.",
   "- No end-of-Icon summary for it; History keeps AMENDED.",
   "1) SCR Home.")

tc("M2-11-TC06", "M2-11", "History calendar", "Client request Oct 5 ('Icon colour dots … need to sync to the calendar … same colour coding')",
   "Each stamped Icon day appears in the History calendar in its colour", "P1", "Functional", "iPhone app + DB",
   "An Icon with at least one HONOURED and one BROKEN day (running or finished), e.g. ICON-S.",
   "1. Contract tab: note the Icon's day marks.\n2. History: open the month of those days.\n3. Run Q-02 for the Icon.",
   "- Every day stamped HONOURED is a green date and every BROKEN day a red date, on the Icon day itself (also when the server stamped it after midnight), while the Icon runs and after it closes.\n"
   "- The same days and colours as the day marks and Q-02; pending days are not coloured.",
   "1) SCR day marks.\n2) SCR History month.\n3) DB Q-02.")

tc("M2-11-TC09", "M2-11", "History calendar", "Client request Oct 5 ('Calendar is where users see the full detail + history')",
   "Icon day detail and list row", "P1", "Functional", "iPhone app",
   "As M2-11-TC06; one measured and one self-reported Icon day if possible.",
   "1. Tap a coloured Icon date.\n2. Tap the matching row in the list below.",
   "- Detail: date, activity, TARGET, SESSION 'k of N', RESULT (the Health reading such as '12,382 / 10,000 steps', 'Self-reported' or 'No Health data'), the Because line and the HONOURED/BROKEN badge.\n"
   "- List row: date, activity, gold 'ICON · SESSION k OF N', Because, badge; tapping it selects that date.",
   "1) SCR detail (measured).\n2) SCR detail (self-reported).\n3) SCR list.")

tc("M2-11-TC10", "M2-11", "History calendar", "Client request Oct 5 ('when an Icon day is … amended'); Scope v6 (early exit is AMENDED)",
   "An Icon ended early shows one AMENDED date", "P2", "Functional", "iPhone app",
   "An Icon with some stamped days, then ended early (M2-04-TC14).",
   "1. History: open the month of the exit.\n2. Tap the amber date.",
   "- The exit date is amber; its detail shows SESSIONS 'k of N sessions honoured' and the AMENDED badge.\n- The stamped days before it keep green/red; the days after the exit are not coloured.",
   "1) SCR History month.\n2) SCR detail.")

tc("M2-11-TC11", "M2-11", "History calendar", "Client request Oct 5; History filters and totals",
   "Totals and filters include Icon days", "P2", "Functional", "iPhone app",
   "A month with Icon days and at least one ordinary contract.",
   "1. Read the line under the legend.\n2. Tap HONOURED, BROKEN, AMENDED filters.",
   "- '<h> honoured. <b> broken. <a> amended.' counts every Icon day and contract dated in the month.\n- Each filter keeps only matching dates and rows.",
   "1) SCR totals.\n2) SCR each filter.")

tc("M2-11-TC07", "M2-11", "End of Icon", "Scope v6 §5 (one Icon per activity) + M2-11 (frees the activity)",
   "Closing frees the activity for a new Icon", "P2", "Functional", "iPhone app",
   "A closed Icon 'Meditation'.",
   "1. Compose a new Icon 'Meditation' and sign.",
   "- No 'You already have an active Icon …' message; the new Icon is created.",
   "1) SCR Active Icons with the new Icon.")

tc("M2-11-TC08", "M2-11", "End of Icon", "Implementation (summary within 14 days; once per account on a device)",
   "Summary on a second device, and its time limit", "P3", "Edge", "iPhone + desktop browser",
   "A closed Icon; a desktop browser signed in as ACC-A.",
   "1. Open the browser within 14 days of the last cut-off.",
   "- The browser shows the summary once too (each device shows it once). After 14 days it is no longer shown.",
   "1) WEB summary.")

# --------------------------------------------------------------------------
# M2-12 Go again
# --------------------------------------------------------------------------
tc("M2-12-TC01", "M2-12", "Go again", "M2-12 task; Scope v6 ('A new Oath after the period ends means signing again — no auto-renewal')",
   "Go again prefills the previous terms", "P1", "Functional", "iPhone app",
   "The summary from M2-11-TC02 or TC03.",
   "1. Tap GO AGAIN.\n2. Read the composer; open the Icon sheet.",
   "- The Contract tab opens with the same activity, target and Because; the Icon row shows the same days and period (ICON-S: 'Mon · Tue · Wed · Thu · Fri · Sat · Sun | 3 Days'); the sheet shows the same reminders; the deadline time is the old cut-off.\n"
   "- Pill 'ICON · UNSIGNED'; the signature pad is empty.",
   "1) SCR composer.\n2) SCR sheet.")

tc("M2-12-TC02", "M2-12", "Go again", "M2-12 done-when ('Prefill is editable before signing')",
   "The prefill can be changed before signing", "P1", "Functional", "iPhone app + DB",
   "Composer from M2-12-TC01.",
   "1. Change a day, the period and the target.\n2. Sign with a fresh signature.\n3. Run Q-01.",
   "- A new Icon (new client_id) with the edited terms, start day = today; the old Icon stays closed.",
   "1) DB Q-01 (both Icons).")

tc("M2-12-TC03", "M2-12", "Go again", "M2-12 ('requiring a fresh signature')",
   "A fresh signature is required", "P1", "Negative", "iPhone app",
   "Composer from M2-12-TC01.",
   "1. Tap SIGN THIS CONTRACT without signing.",
   "- 'Sign the contract.'; nothing signed.",
   "1) SCR message.")

tc("M2-12-TC04", "M2-12", "Go again", "M2-12 (usual checks apply)",
   "The usual signing checks apply", "P2", "Negative", "iPhone app",
   "Composer from M2-12-TC01 while another active Icon holds today, or with an evening reminder outside the window.",
   "1. Sign.",
   "- The matching message ('Icon already set for this day. Finish your Icon first.' or 'Set the evening reminder within 8 hours before the deadline.').",
   "1) SCR message.")

tc("M2-12-TC05", "M2-12", "Go again", "Scope v6 (no auto-renewal)",
   "Nothing renews by itself", "P1", "Functional", "iPhone app + DB",
   "A closed Icon; tap Not now on its summary (or leave Go again without signing).",
   "1. Wait a day; run Q-01.",
   "- No new Icon was created; no card or reminder for the old terms.",
   "1) DB Q-01.")

tc("M2-12-TC06", "M2-12", "Go again", "Implementation (prefill is cleared when leaving)",
   "Leaving the composer drops the prefill", "P3", "Functional", "iPhone app",
   "Composer from M2-12-TC01.",
   "1. Switch to Home with the tab bar, then back to the Contract tab.",
   "- The composer opens without the Icon set (normal prefill rules).",
   "1) SCR composer.")

# --------------------------------------------------------------------------
# M2-13 Wording and polish
# --------------------------------------------------------------------------
tc("M2-13-TC01", "M2-13", "Wording", "Scope v6 weekly lines; O-12 and O-15 approved Oct 4 (E-47)",
   "Every Icon string matches the approved wording", "P1", "Content", "iPhone app",
   "Screenshots from M2-08, M2-10, M2-11, M2-12.",
   "1. Compare each string on screen with the 'Approved wording' table in the Test Data sheet, character by character.",
   "- Exact match, including punctuation, capitals and the American 'energized' in the weekly line.",
   "1) Checklist in the Notes column with any difference.")

# --------------------------------------------------------------------------
# M2-15 Icon-day exclusivity
# --------------------------------------------------------------------------
tc("M2-15-TC01", "M2-15", "Exclusivity", "Client request Oct 3 (E-37); M2-15 done-when",
   "An ordinary contract on an Icon day is refused before signing", "P1", "Functional", "iPhone app",
   "An active Icon holding today. No daily contract in force. Note the sessions counter (free plan).",
   "1. Compose an ordinary contract (no Icon) with a deadline today, sign with a finger, tap SIGN THIS CONTRACT.\n2. Repeat after today's Icon cut-off (still today).",
   "- 'Icon already set for this day. Finish your Icon first.' under the form.\n- Nothing signed; activity, Because and the signature stay; the sessions counter does not change.\n- Same result after the cut-off (the whole calendar day is held).",
   "1) SCR message with the draft kept.\n2) SCR after the cut-off.")

tc("M2-15-TC02", "M2-15", "Exclusivity", "O-13 decision (contract touching a held day)",
   "A contract whose deadline runs into the next Icon day is refused", "P1", "Functional", "iPhone app",
   "An Icon holding tomorrow but not today.",
   "1. Compose an ordinary contract today with a deadline tomorrow 08:00; sign.",
   "- 'Icon already set for this day. Finish your Icon first.'; nothing signed.",
   "1) SCR message.")

tc("M2-15-TC03", "M2-15", "Exclusivity", "Decision Oct 1 (Icons run alongside the daily contract) as narrowed by M2-15",
   "A contract on a day without an Icon is allowed", "P1", "Functional", "iPhone app",
   "An active Icon not holding today or the deadline's day.",
   "1. Sign an ordinary contract today with a deadline today.",
   "- Signed normally; the Icon is unaffected.",
   "1) SCR Home with the contract and the Icons row.",
   "Then run M2-04-TC15 while this contract is in force.")

tc("M2-15-TC04", "M2-15", "Exclusivity", "O-13 (second Icon)",
   "A second Icon cannot share a day with an active Icon", "P1", "Functional", "iPhone app",
   "An active Icon on e.g. Mon/Wed/Fri.",
   "1. Compose an Icon for a different activity on Wed/Sat; sign.\n2. Change it to Tue/Thu; sign.",
   "- 1: 'Icon already set for this day. Finish your Icon first.'; nothing signed.\n- 2: signed (no shared day).",
   "1) SCR message.\n2) SCR Active Icons with both.")

tc("M2-15-TC05", "M2-15", "Exclusivity", "O-13 (Icon over an active contract; proposed copy); database enforcement",
   "An Icon over another device's active contract is refused by the database", "P1", "Functional", "iPhone + desktop browser + DB",
   "ACC-A open on the iPhone and in a desktop browser, both on the Contract tab with no contract in force.",
   "1. In the browser, sign an ordinary contract for today.\n2. Without refreshing the iPhone, sign an Icon there that includes today.\n3. Wait a few seconds.",
   "- The iPhone shows a sheet: 'Contract already set for this day. Finish your contract first.' with OK.\n- The Icon disappears from the iPhone; Q-01 has no row for it; the browser's contract is intact.",
   "1) SCR refusal sheet.\n2) DB Q-01 / Q-11.",
   "Open the iPhone composer before step 1 and do not pull to refresh, so the iPhone does not know about the browser's contract when it signs.")

tc("M2-15-TC06", "M2-15", "Exclusivity", "Client request Oct 3; database enforcement",
   "An ordinary contract from a stale device is refused by the database", "P2", "Functional", "iPhone + desktop browser + DB",
   "A browser tab opened before an Icon was signed on the iPhone (do not refresh it).",
   "1. On the iPhone sign an Icon including today.\n2. In the stale browser tab sign an ordinary contract for today.",
   "- The browser shows 'Icon already set for this day. Finish your Icon first.' with OK; the contract is removed there; other contracts keep syncing.",
   "1) WEB refusal sheet.\n2) DB Q-11.")

tc("M2-15-TC07", "M2-15", "Exclusivity", "O-13 ('AMENDED days released')",
   "Ending an Icon early releases its days", "P1", "Functional", "iPhone app",
   "An Icon holding today; End early it (M2-04-TC14).",
   "1. Sign an ordinary contract for today.",
   "- Signed normally.",
   "1) SCR Home with the contract.")

# --------------------------------------------------------------------------
# M2-14 Cross-cutting device QA
# --------------------------------------------------------------------------
tc("M2-14-TC01", "M2-14", "Time zone", "M2-14 (timezone); icon_v1.sql (Icon days in the Icon's zone)",
   "Travelling: the Icon keeps its own days and times", "P2", "Edge", "iPhone + DB",
   "An active Icon signed in the home zone.",
   "1. Change the iPhone's zone to one 3+ hours away (automatic time off).\n2. Open the app: Home, Active Icons, the card.\n3. Restore automatic time.",
   "- Cut-offs and reminders stay at the same instants (Icon zone, Q-02); the card's 'Due …' shows the new local time.\n- Results and recaps stay attached to the Icon's dates.",
   "1) SCR Active Icons in the other zone.\n2) LS card.\n3) DB Q-02.")

tc("M2-14-TC02", "M2-14", "Time zone", "M2-14 (DST)",
   "Daylight-saving change keeps wall-clock times", "P2", "Edge", "DB",
   "A throwaway Icon signed with the iPhone set to a zone that changes clocks during the Icon (e.g. America/New_York across 1 Nov 2026, or Australia/Sydney across 5 Apr 2027).",
   "1. Run Q-13 for the days around the change.\n2. End the Icon early afterwards to release its days.",
   "- cutoff_local, morning_local and evening_local stay at the same wall-clock times before and after the change while the UTC offset changes by one hour.",
   "1) DB Q-13.")

tc("M2-14-TC03", "M2-14", "Health", "Scope v6 §4 ('Evening progress requires background HealthKit updates'); M2-05",
   "HONOURED arrives with the app in the background", "P1", "Functional", "iPhone + DB",
   "A measured Icon day pending; the app in the background (not force-quit); iPhone locked.",
   "1. Walk past the target without opening the app.\n2. After 30–60 minutes, run Q-02 (scored_at) and look at the card.",
   "- The day is stamped HONOURED without opening the app (after a background Health delivery); the card turns HONOURED via push.",
   "1) DB Q-02.\n2) LS HONOURED.",
   "Background delivery timing is controlled by iOS; record the delay seen.")

tc("M2-14-TC04", "M2-14", "Multiple Icons", "Scope v6 §4 ('view all active Oath contracts')",
   "Two Icons on different days", "P2", "Functional", "iPhone app + DB",
   "Two active Icons with different activities and disjoint days.",
   "1. Check Home, Active Icons, Settings › Icon reminders.\n2. On each Icon's day, check its card.",
   "- Both listed everywhere; each card appears only on its own days with its own facts.",
   "1) SCR Home, Active Icons, Settings.\n2) LS each card.")

tc("M2-14-TC05", "M2-14", "Offline", "M2-14 (edge cases)",
   "Offline during an Icon day", "P2", "Edge", "iPhone + DB",
   "A measured Icon day; Airplane mode during the afternoon, back online before the cut-off.",
   "1. Walk past the target while offline.\n2. Go online, open the app.",
   "- The reading is reported when online and the day becomes HONOURED (if before the 24-hour limit).",
   "1) DB Q-02.")

tc("M2-14-TC06", "M2-14", "Accessibility", "M2-01/M2-02 notes (VoiceOver, focus)",
   "VoiceOver on the Icon row and sheet", "P2", "Accessibility", "iPhone app",
   "VoiceOver on.",
   "1. Focus the Icon row.\n2. Open the sheet; swipe through every control; change a day and the period.",
   "- Row read as a button with its title and summary.\n- On open, focus moves into the sheet (Monday); days read as 'Monday, selected/not selected'; switches as 'Morning reminder, switch, on/off'; the session count is announced after a change.\n- Closing returns focus to the Icon row.",
   "1) REC with VoiceOver audio.")

tc("M2-14-TC07", "M2-14", "Accessibility", "Implementation (dialogs)",
   "VoiceOver on End early, recap and summary", "P3", "Accessibility", "iPhone app",
   "VoiceOver on.",
   "1. Open End early; then a recap or summary if due.",
   "- End early is announced as an alert with its title and text, focus on Cancel.\n- Recap/summary: dialog with its title; focus on Continue / GO AGAIN.",
   "1) REC.")

tc("M2-14-TC08", "M2-14", "Data", "Settings › Reset everything (existing); M2-03 (days belong to the contract)",
   "Reset everything removes Icons and stops their reminders", "P3", "Edge", "iPhone app + DB",
   "A throwaway account with an active Icon and a card showing.",
   "1. Settings › Data › Reset everything › Erase everything.\n2. Run Q-01 and Q-02 (with the old client id).\n3. Reopen the app; wait past the next reminder time.",
   "- Q-01 and Q-02 return no rows (the days go with the contract).\n- The card closes when the app reopens; no further reminder or card.",
   "1) DB Q-01, Q-02.\n2) LS after the next reminder time.")

tc("M2-14-TC09", "M2-14", "Cross-device", "Scope v6 §5 (cross-device sync within the existing Supabase architecture)",
   "An Icon signed in a desktop browser works on the iPhone", "P3", "Functional", "Desktop browser + iPhone + DB",
   "ACC-A signed in on a desktop browser and on the iPhone; no Icon holding the chosen days.",
   "1. Sign an Icon in the browser (reminders a few minutes ahead).\n2. On the iPhone pull to refresh Home.\n3. Wait for the reminder with the iPhone locked.",
   "- The Icon appears on the iPhone (Home, Active Icons); icon_timezone is the computer's zone (Q-01).\n- The card arrives on the iPhone at the reminder.",
   "1) WEB signed Icon.\n2) SCR iPhone Active Icons.\n3) LS card.\n4) DB Q-01.")

tc("M2-14-TC10", "M2-14", "Compatibility", "O-10 (shell 1.0.4 never reports Icon readings)",
   "Older app versions", "P3", "Compatibility", "iPhone with build 1.0.4",
   "An iPhone still on build 1.0.4 (App Store).",
   "1. Sign a measured Icon there; observe a day.",
   "- Known limitation, not a pass criterion: 1.0.4 cannot read Icon days, so measured days end BROKEN (no_data) 24 hours after the cut-off. Record what is seen.",
   "1) DB Q-02.",
   "Tracked as O-10; resolved by shipping the new native build.")

# --------------------------------------------------------------------------
# End-to-end scenarios
# --------------------------------------------------------------------------
tc("M2-E2E-01", "M2-07 to M2-09", "End to end", "Scope v6 §3 steps 1–12",
   "One Icon day from morning card to close", "P1", "Scenario", "iPhone + push + DB",
   "ICON-S signed; today an Icon day; Live Activities on; app closed.",
   "1. Morning reminder: card arrives (M2-07-TC01).\n2. Evening reminder: fresh card (M2-07-TC02).\n3. Self-report Honoured from the browser (M2-07-TC03).\n4. Cut-off: card closes (M2-07-TC04).\n5. Next morning: Active Icons mark for the day; Q-04 has four rows.",
   "- Every step as in the referenced cases; one card at a time; four log rows (morning, evening, result, end), all sent.",
   "1) The evidence of the referenced cases.\n2) DB Q-04 for the day.")

tc("M2-E2E-02", "M2-01 to M2-09", "End to end", "Scope v6 §7 Acceptance Example",
   "Scope acceptance example", "P1", "Scenario", "iPhone + push + DB",
   "A test account free of other Icons for a month.",
   "1. Contract: Running, 33 min, Because 'Spring has started, it's warrior season.'.\n2. Icon: Tue, Thu, Sat, Sun | 1 Month; Morning 07:00, Evening 20:00; deadline (each Icon day) 23:59.\n3. Read the count; SET THE ICON; sign.\n4. Observe at least one Icon day and one Mon/Wed/Fri.",
   "- Count 17 or 18 depending on the start date (Test Data); row 'Tue · Thu · Sat · Sun | 1 Month'.\n- On Icon days: card at 07:00 with an affirmation, fresh card at 20:00 'Finish what you signed.'; HealthKit exercise minutes ≥ 33 → HONOURED; fewer → BROKEN after 00:59 (cut-off + 1 h); card closes at 23:59.\n- Mon, Wed, Fri: no card, no reminder, no result row.",
   "1) SCR sheet and row.\n2) LS cards.\n3) DB Q-02, Q-04.",
   "The evening card shows no progress bar (client decision Sep 28).")

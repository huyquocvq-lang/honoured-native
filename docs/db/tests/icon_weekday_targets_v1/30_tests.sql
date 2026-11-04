\set ON_ERROR_STOP on
-- After icon_weekday_targets_v1.sql on the revision suite's seed. T = today
-- in UTC; dow(n) = the ISO weekday of T + n. Icons signed here:
--   21 steps, every day, Mon 5000 ... Sun 11000 (4000 + 1000 x weekday)
--   22 km, every day, 7.5 km on dow(1), 5 km otherwise
--   23 self-reported reps, every day, 5 x weekday reps
--   24 steps, the same 8000 on every day
--   25 steps, three days (T-1, T, T+1), Mon 6000, otherwise 7000
--   26 steps, Monday and Wednesday only, 4000 / 6000

------------------------------------------------------------------------------
-- Signing with weekday targets.
select public.t_sign_targets('21', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', 'UTC', -1, 2, 'week',
  '5000 steps', 'steps', 5000, 'count', '{1,2,3,4,5,6,7}',
  (select jsonb_object_agg(d::text, (4000 + d * 1000)::text || ' steps') from generate_series(1, 7) d));
select public.t_eq('21: the signed weekday targets are kept',
  (select icon_day_targets ->> '7' from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000021'),
  '11000 steps');
select public.t_eq('21: every day starts on its weekday''s target',
  (select count(*) from public.icon_days
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021'
     and (target_text, target_value, target_revision)
         is distinct from ((4000 + extract(isodow from day) * 1000)::text || ' steps',
                           (4000 + extract(isodow from day) * 1000)::double precision, 0)),
  0::bigint);
select public.t_eq('21: all 14 days exist', (select count(*) from public.icon_days
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021'), 14::bigint);

select public.t_sign_targets('22', 'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2', 'UTC', -1, 2, 'week',
  case when public.t_dow('UTC', 1) = '1' then '7.5 km' else '5 km' end,
  'distance_walking_running', case when public.t_dow('UTC', 1) = '1' then 7500 else 5000 end, 'meters',
  '{1,2,3,4,5,6,7}',
  (select jsonb_object_agg(d::text, case when d::text = public.t_dow('UTC', 1) then '7.5 km' else '5 km' end)
   from generate_series(1, 7) d));
select public.t_eq('22: a 7.5 km weekday is 7500 meters',
  public.t_state('22', public.t_today('UTC') + 1), 'pending/7.5 km/7500/0');
select public.t_eq('22: the other weekdays keep 5 km as 5000 meters',
  public.t_state('22', public.t_today('UTC') + 2), 'pending/5 km/5000/0');

select public.t_sign_targets('23', 'e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3', 'UTC', -1, 2, 'week',
  '5 reps', null, null, null, '{1,2,3,4,5,6,7}',
  (select jsonb_object_agg(d::text, (5 * d)::text || ' reps') from generate_series(1, 7) d));
select public.t_eq('23: a self-reported Icon gets text targets and no value',
  public.t_state('23', public.t_today('UTC') + 1),
  'pending/' || (5 * public.t_dow('UTC', 1)::integer)::text || ' reps/0');

select public.t_sign_targets('24', 'e4e4e4e4-e4e4-e4e4-e4e4-e4e4e4e4e4e4', 'UTC', 0, 1, 'week',
  '8000 steps', 'steps', 8000, 'count', '{1,2,3,4,5,6,7}',
  (select jsonb_object_agg(d::text, '8000 steps') from generate_series(1, 7) d));
select public.t_eq('24: the same target on every day is stored as none',
  (select icon_day_targets from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000024'), null::jsonb);
select public.t_eq('24: its days hold the signed target',
  public.t_state('24', public.t_today('UTC') + 1), 'pending/8000 steps/8000/0');

select public.t_sign_targets('25', 'e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5', 'UTC', -1, 3, 'day',
  '6000 steps', 'steps', 6000, 'count', '{1,2,3,4,5,6,7}',
  (select jsonb_object_agg(d::text, case when d = 1 then '6000 steps' else '7000 steps' end) from generate_series(1, 7) d));
select public.t_sign_targets('26', 'e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6', 'UTC', -1, 3, 'week',
  '4000 steps', 'steps', 4000, 'count', '{3,1}', '{"1": "4000 steps", "3": "6000 steps"}');
select public.t_eq('26: Monday and Wednesday days hold their targets',
  (select count(*) from public.icon_days
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000026'
     and target_text <> case extract(isodow from day) when 1 then '4000 steps' else '6000 steps' end),
  0::bigint);

-- Refused terms: nothing is written.
select public.t_eq('a missing weekday is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,3}', '{"1": "4000 steps"}')$q$),
  'icon_day_targets must hold one target for each Icon weekday');
select public.t_eq('a weekday outside the Icon is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1}', '{"1": "4000 steps", "2": "5000 steps"}')$q$),
  'icon_day_targets must hold one target for each Icon weekday');
select public.t_eq('another unit is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '{"1": "4000 steps", "2": "5 km"}')$q$),
  'icon_day_targets must be positive targets in steps, written as the web writes them');
select public.t_eq('above the unit''s maximum is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '{"1": "4000 steps", "2": "50001 steps"}')$q$),
  'icon_day_targets must be positive targets in steps, written as the web writes them');
select public.t_eq('zero is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '{"1": "4000 steps", "2": "0 steps"}')$q$),
  'icon_day_targets must be positive targets in steps, written as the web writes them');
select public.t_eq('a decimal the unit does not allow is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '{"1": "4000 steps", "2": "4000.5 steps"}')$q$),
  'icon_day_targets must be positive targets in steps, written as the web writes them');
select public.t_eq('two decimals of km are refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '5 km', 'distance_walking_running', 5000, 'meters', '{1,2}', '{"1": "5 km", "2": "5.25 km"}')$q$),
  'icon_day_targets must be positive targets in km, written as the web writes them');
select public.t_eq('a number not written as the web writes it is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '{"1": "4000 steps", "2": "5000.0 steps"}')$q$),
  'icon_day_targets must be positive targets in steps, written as the web writes them');
select public.t_eq('a target that is not text is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '{"1": "4000 steps", "2": 5000}')$q$),
  'icon_day_targets must be positive targets in steps, written as the web writes them');
select public.t_eq('primary_target must be the first weekday''s',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '5000 steps', 'steps', 5000, 'count', '{1,2}', '{"1": "4000 steps", "2": "5000 steps"}')$q$),
  'primary_target must be the first Icon weekday''s target');
select public.t_eq('a target that is not "<number> <unit>" cannot hold weekday targets',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    'a long walk', null, null, null, '{1,2}', '{"1": "a long walk", "2": "a run"}')$q$),
  'icon_day_targets needs primary_target written as "<number> <unit>"');
select public.t_eq('not an object is refused',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '4000 steps', 'steps', 4000, 'count', '{1,2}', '["4000 steps", "5000 steps"]')$q$),
  'icon_day_targets must map ISO weekdays to targets');
select public.t_eq('a Word Tracker Icon has one target',
  public.t_err($q$select public.t_sign_targets('31', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'UTC', 0, 1, 'week',
    '500 words', null, null, null, '{1,2}', '{"1": "500 words", "2": "600 words"}', true)$q$),
  'a Word Tracker Icon has one target');
select public.t_eq('nothing was written for the refused terms',
  (select count(*) from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000031'), 0::bigint);

-- An ordinary contract never holds weekday targets.
insert into public.contracts (id, user_id, client_id, created_at, deadline, primary_type, primary_activity,
  primary_target, because, status, icon_day_targets)
values ('aaaaaaaa-0000-0000-0000-000000000032', 'e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', 'client-32', now(),
  now() + interval '1 day', 'complete', 'Run', '5 km', 'because', 'active', '{"1": "5 km"}');
select public.t_eq('an ordinary contract drops weekday targets',
  (select icon_day_targets from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000032'), null::jsonb);

-- Locked after signing, also through the web's upsert.
select set_config('request.jwt.claim.sub', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', false);
set role authenticated;
update public.contracts set icon_day_targets = '{"1": "1 steps"}' where id = 'aaaaaaaa-0000-0000-0000-000000000021';
insert into public.contracts (user_id, client_id, created_at, deadline, primary_type, primary_activity,
  primary_target, because, status, icon_weekdays, icon_start_day, icon_period_count, icon_period_unit,
  icon_deadline_time, icon_timezone, icon_day_targets)
values ('e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', 'client-21', now(), now(), 'complete', 'Icon 21',
  '5000 steps', 'because', 'active', '{1}', public.t_today('UTC'), 1, 'week', '00:00', 'UTC', '{"1": "5000 steps"}')
on conflict (user_id, client_id) do update set icon_day_targets = excluded.icon_day_targets,
  primary_target = excluded.primary_target, because = 'upserted';
reset role;
select public.t_eq('signed weekday targets cannot be changed',
  (select icon_day_targets ->> '7' from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000021'),
  '11000 steps');
select public.t_eq('the upsert went through for the free text',
  (select because from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000021'), 'upserted');

------------------------------------------------------------------------------
-- Measuring and push read the day's own target.
select set_config('request.jwt.claim.sub', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', false);
set role authenticated;
select public.t_eq('21: today is measured against today''s weekday target',
  (select target from public.icon_days_to_measure()
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021' and day = public.t_today('UTC')),
  (4000 + public.t_dow('UTC', 0)::integer * 1000)::double precision);
reset role;
select public.t_eq('21: the push job carries tomorrow''s weekday target',
  (select target from public.icon_push_jobs(
     (public.t_today('UTC') + 1)::timestamp at time zone 'UTC' + interval '8 hours 5 minutes')
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021' and job = 'morning'),
  (4000 + public.t_dow('UTC', 1)::integer * 1000)::text || ' steps');

------------------------------------------------------------------------------
-- Weekday revisions.
select set_config('request.jwt.claim.sub', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', false);
set role authenticated;

-- One weekday: today's weekday changes from next week, not today.
create temp table t_r1 as
select public.t_revs('21', '1', jsonb_build_object(public.t_dow('UTC', 0), 20000),
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w1.png') r;
select public.t_eq('r1: revision 1 from the same weekday next week',
  (select concat_ws('/', r->>'ok', r->>'revision', r->>'effectiveDay', r->>'targetText', r->>'targetValue', r->>'days') from t_r1),
  concat_ws('/', 'true', '1', (public.t_today('UTC') + 7)::text, '20000 steps', '20000', '1'));
select public.t_eq('r1: one change, with its weekday''s previous target',
  (select (r->'changes')::text from t_r1),
  jsonb_build_array(jsonb_build_object('weekday', public.t_dow('UTC', 0)::integer,
    'previousTargetText', (4000 + public.t_dow('UTC', 0)::integer * 1000)::text || ' steps',
    'previousTargetValue', 4000 + public.t_dow('UTC', 0)::integer * 1000,
    'targetText', '20000 steps', 'targetValue', 20000,
    'effectiveDay', public.t_today('UTC') + 7))::text);
select public.t_eq('r1: today keeps its target',
  public.t_state('21', public.t_today('UTC')),
  'pending/' || (4000 + public.t_dow('UTC', 0)::integer * 1000)::text || ' steps/'
    || (4000 + public.t_dow('UTC', 0)::integer * 1000)::text || '/0');
select public.t_eq('r1: next week''s day holds the revision',
  public.t_state('21', public.t_today('UTC') + 7), 'pending/20000 steps/20000/1');
select public.t_eq('r1: no other weekday changed',
  (select count(*) from public.icon_days
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021' and target_revision <> 0), 1::bigint);

-- Two weekdays under one signature.
create temp table t_r2 as
select public.t_revs('21', '2', jsonb_build_object(public.t_dow('UTC', 2), 13000, public.t_dow('UTC', 1), 12000),
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w2.png') r;
select public.t_eq('r2: revision 2, first effective tomorrow, four days',
  (select concat_ws('/', r->>'revision', r->>'effectiveDay', r->>'targetText', jsonb_array_length(r->'changes'), r->>'days') from t_r2),
  concat_ws('/', '2', (public.t_today('UTC') + 1)::text, '12000 steps', '2', '4'));
select public.t_eq('r2: the history row holds the first change and both changes',
  (select concat_ws('/', previous_target_text, target_text, effective_day, jsonb_array_length(changes))
   from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021' and revision = 2),
  concat_ws('/', (4000 + public.t_dow('UTC', 1)::integer * 1000)::text || ' steps', '12000 steps',
    (public.t_today('UTC') + 1)::text, '2'));
select public.t_eq('r2: tomorrow and a week later hold 12000',
  public.t_state('21', public.t_today('UTC') + 1) || ' ' || public.t_state('21', public.t_today('UTC') + 8),
  'pending/12000 steps/12000/2 pending/12000 steps/12000/2');
select public.t_eq('r2: the day after holds 13000',
  public.t_state('21', public.t_today('UTC') + 2), 'pending/13000 steps/13000/2');
select public.t_eq('r2: next week''s revision 1 day is untouched',
  public.t_state('21', public.t_today('UTC') + 7), 'pending/20000 steps/20000/1');

-- A retry gets the same revision back.
select public.t_eq('r2 again: the same revision, marked duplicate',
  (select concat_ws('/', r->>'duplicate', r->>'revision', jsonb_array_length(r->'changes'))
   from (select public.t_revs('21', '2', jsonb_build_object(public.t_dow('UTC', 1), 12000),
     'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w2.png') r) x),
  'true/2/2');

-- Unchanged weekdays are left out; nothing changed is refused.
select public.t_eq('the same targets again are refused as unchanged',
  public.t_revs('21', '3', jsonb_build_object(public.t_dow('UTC', 1), 12000, public.t_dow('UTC', 2), 13000),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w3.png')->>'reason', 'unchanged');
create temp table t_r3 as
select public.t_revs('21', '3', jsonb_build_object(public.t_dow('UTC', 1), 12000, public.t_dow('UTC', 3), 9500),
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w3.png') r;
select public.t_eq('r3: only the changed weekday is recorded',
  (select concat_ws('/', r->>'revision', jsonb_array_length(r->'changes'), r->'changes'->0->>'weekday', r->>'effectiveDay') from t_r3),
  concat_ws('/', '3', '1', public.t_dow('UTC', 3), (public.t_today('UTC') + 3)::text));

-- An every-day revision (revise_icon_target) and then a weekday one.
select public.t_eq('every day: revise_icon_target still revises from tomorrow',
  public.t_rev('21', '4', 15000, 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w4.png')->>'revision', '4');
select public.t_eq('every day: every pending day after today holds 15000',
  (select count(*) from public.icon_days
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021' and day > public.t_today('UTC')
     and (target_text, target_revision) is distinct from ('15000 steps', 4)), 0::bigint);
select public.t_eq('a weekday revision then starts from the every-day target',
  (select r->'changes'->0->>'previousTargetText'
   from (select public.t_revs('21', '5', jsonb_build_object(public.t_dow('UTC', 4), 16000),
     'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w5.png') r) x),
  '15000 steps');

-- Refusals.
select public.t_eq('an empty object is refused',
  public.t_revs('21', '6', '{}', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid');
select public.t_eq('an array is refused',
  public.t_revs('21', '6', '[12000]', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid');
select public.t_eq('weekday 8 is refused',
  public.t_revs('21', '6', '{"8": 12000}', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid');
select public.t_eq('a weekday name is refused',
  public.t_revs('21', '6', '{"mon": 12000}', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid');
select public.t_eq('above the maximum is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), 50001),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid_target');
select public.t_eq('zero is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), 0),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid_target');
select public.t_eq('a decimal of steps is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), 1.5),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid_target');
select public.t_eq('a number as text is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), '9000'),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'invalid_target');
select public.t_eq('a signature outside the Icon''s revisions folder is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), 9000),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-22/revisions/w1.png')->>'reason', 'invalid_signature');
select public.t_eq('a signature used before is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), 9000),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w1.png')->>'reason', 'invalid_signature');
select public.t_eq('a signature never uploaded is refused',
  public.t_revs('21', '6', jsonb_build_object(public.t_dow('UTC', 1), 9000),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/missing.png')->>'reason', 'signature_missing');
select public.t_eq('another person''s Icon is not found',
  public.t_revs('22', '6', jsonb_build_object(public.t_dow('UTC', 1), 6),
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'reason', 'not_found');
select public.t_eq('refusals wrote nothing',
  (select count(*) from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021'), 5::bigint);
reset role;

select set_config('request.jwt.claim.sub', 'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2', false);
set role authenticated;
select public.t_eq('km: two decimals are refused',
  public.t_revs('22', '1', jsonb_build_object(public.t_dow('UTC', 2), 6.25),
    'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2/client-22/revisions/w1.png')->>'reason', 'invalid_target');
select public.t_eq('km: 6.5 km is 6500 meters, from 5 km',
  (select concat_ws('/', r->'changes'->0->>'previousTargetText', r->'changes'->0->>'previousTargetValue',
     r->>'targetText', r->>'targetValue')
   from (select public.t_revs('22', '1', jsonb_build_object(public.t_dow('UTC', 2), 6.5),
     'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2/client-22/revisions/w1.png') r) x),
  '5 km/5000/6.5 km/6500');
reset role;

select set_config('request.jwt.claim.sub', 'e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3', false);
set role authenticated;
select public.t_eq('self-reported: a text target and no values',
  (select concat_ws('/', r->>'targetText', coalesce(r->>'targetValue', 'null'),
     coalesce(r->'changes'->0->>'previousTargetValue', 'null'))
   from (select public.t_revs('23', '1', jsonb_build_object(public.t_dow('UTC', 1), 40),
     'e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3/client-23/revisions/w1.png') r) x),
  '40 reps/null/null');
reset role;

select set_config('request.jwt.claim.sub', 'e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5', false);
set role authenticated;
select public.t_eq('a weekday with no Icon day left is refused',
  public.t_revs('25', '1', jsonb_build_object(public.t_dow('UTC', 2), 9000),
    'e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5/client-25/revisions/w1.png')->>'reason', 'no_future_day');
select public.t_eq('today''s weekday has no Icon day left either',
  public.t_revs('25', '1', jsonb_build_object(public.t_dow('UTC', 0), 9000),
    'e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5/client-25/revisions/w1.png')->>'reason', 'no_future_day');
reset role;

select set_config('request.jwt.claim.sub', 'e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6', false);
set role authenticated;
select public.t_eq('a weekday the Icon does not hold is refused',
  public.t_revs('26', '1', '{"2": 9000}',
    'e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6/client-26/revisions/w1.png')->>'reason', 'invalid');
select public.t_eq('Wednesday alone changes from the next Wednesday',
  (select concat_ws('/', r->>'targetText', r->'changes'->0->>'previousTargetText',
     extract(isodow from (r->>'effectiveDay')::date))
   from (select public.t_revs('26', '1', '{"3": 7000}',
     'e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6/client-26/revisions/w1.png') r) x),
  '7000 steps/6000 steps/3');
select public.t_eq('Mondays keep 4000',
  (select count(*) from public.icon_days where contract_id = 'aaaaaaaa-0000-0000-0000-000000000026'
     and extract(isodow from day) = 1 and target_text <> '4000 steps'), 0::bigint);
reset role;

select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);
set role authenticated;
select public.t_eq('a Word Tracker Icon is not supported',
  public.t_revs('4', '7', jsonb_build_object(public.t_dow('UTC', 1), 600),
    '44444444-4444-4444-4444-444444444444/client-4/revisions/w1.png')->>'reason', 'not_supported');
reset role;
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
set role authenticated;
select public.t_eq('an Icon that ended is not active',
  public.t_revs('5', '7', jsonb_build_object(public.t_dow('UTC', 1), 7000),
    '55555555-5555-5555-5555-555555555555/client-5/revisions/w1.png')->>'reason', 'not_active');
reset role;

-- History is immutable, changes included.
select public.t_eq('a revision''s changes cannot be edited',
  public.t_err($q$update public.icon_revisions set changes = null where revision = 2
    and contract_id = 'aaaaaaaa-0000-0000-0000-000000000021'$q$),
  'Icon revisions cannot be changed or deleted');
select public.t_eq('changes must be a non-empty array',
  public.t_err($q$alter table public.icon_revisions disable trigger icon_revisions_immutable;
    update public.icon_revisions set changes = '[]' where revision = 2
    and contract_id = 'aaaaaaaa-0000-0000-0000-000000000021'$q$) like '%icon_revisions_changes_array%',
  true);

-- Permissions: anon cannot revise, even with Supabase's default grants.
set role anon;
do $$
begin
  perform public.revise_icon_targets('aaaaaaaa-0000-0000-0000-000000000021', gen_random_uuid(), '{"1": 9000}', 'x.png');
  raise exception 'FAIL anon revised an Icon';
exception when insufficient_privilege then
  raise notice 'ok  anon cannot call revise_icon_targets despite the default grant';
end $$;
reset role;

------------------------------------------------------------------------------
-- Push-started cards carry the revision of their day.
select public.t_eq('push facts: a revised day carries its revision',
  public.icon_push_facts(public.t_job('21', public.t_today('UTC') + 7)) ->> 'targetRevision', '4');
select public.t_eq('push facts: today, never revised, says 0',
  public.icon_push_facts(public.t_job('21', public.t_today('UTC'))) ->> 'targetRevision', '0');
select public.t_eq('push facts: a day of another Icon''s revision 1',
  public.icon_push_facts(public.t_job('26', public.t_today('UTC') + (7 + 3 - public.t_dow('UTC', 0)::integer) % 7
    + case when public.t_dow('UTC', 0) = '3' then 7 else 0 end)) ->> 'targetRevision', '1');
select public.t_eq('push facts: no day, no key',
  public.icon_push_facts(public.t_job('21', public.t_today('UTC') + 40)) ? 'targetRevision', false);
select public.t_eq('push facts: a job without a contract id has no key and no error',
  public.icon_push_facts(public.t_job('21', public.t_today('UTC')) - 'contract_id') ? 'targetRevision', false);
select public.t_eq('push facts: a contract id that is not a uuid has no key and no error',
  public.icon_push_facts(public.t_job('21', public.t_today('UTC')) || '{"contract_id": "client-21"}') ? 'targetRevision', false);
select public.t_eq('push facts: every other key is as before',
  (select string_agg(k, ',' order by k) from jsonb_object_keys(public.icon_push_facts(public.t_job('21', public.t_today('UTC')))) k),
  'activityName,because,contractId,deadline,iconDay,sessionNumber,targetRevision,targetUnit,targetValue,totalSessions,weekday');

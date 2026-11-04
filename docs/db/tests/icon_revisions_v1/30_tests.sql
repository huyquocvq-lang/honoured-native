\set ON_ERROR_STOP on
-- After icon_revisions_v1.sql on the seed (10_seed.sql). L = an Icon's local
-- today. A: London steps, B: UTC distance, C: self-reported, D: Word
-- Tracker, E: ended early, F: last day today, G/H: either side of the date
-- line, I: no Icon day tomorrow.

------------------------------------------------------------------------------
-- M2.2: every day carries its own target.
select public.t_eq('every day carries its signed target text',
  (select count(*) from public.icon_days d join public.contracts c on c.id = d.contract_id
   where d.target_text is distinct from c.primary_target), 0::bigint);
select public.t_eq('Health days carry the signed value in the metric unit',
  (select count(*) from public.icon_days d join public.contracts c on c.id = d.contract_id
   where d.target_value is distinct from c.icon_target), 0::bigint);
select public.t_eq('self-reported and Word days carry no value',
  (select count(*) from public.icon_days d join public.contracts c on c.id = d.contract_id
   where c.icon_metric is null and d.target_value is not null), 0::bigint);
select public.t_eq('every day starts on revision 0',
  (select count(*) from public.icon_days where target_revision <> 0), 0::bigint);
select public.t_eq('the backfill leaves updated_at alone',
  (select count(*) from public.icon_days d join public.t_before b using (contract_id, day)
   where d.updated_at <> b.updated_at), 0::bigint);
select public.t_eq('B keeps 5 km as 5000 meters',
  public.t_state('2', public.t_today('UTC')), 'pending/5 km/5000/0');
select public.t_eq('ended-early days keep their target too',
  public.t_state('5', public.t_today('UTC') + 1), 'amended/6000 steps/6000/0');

-- An Icon signed after the migration starts on its signed target.
insert into auth.users (id) values ('abababab-abab-abab-abab-abababababab');
select public.t_sign('10', 'abababab-abab-abab-abab-abababababab', 'UTC', 0, 1, 'week', '3000 steps', 'steps', 3000, 'count');
select public.t_eq('a new Icon''s days carry its target',
  public.t_state('10', public.t_today('UTC') + 1), 'pending/3000 steps/3000/0');
select public.t_eq('every day of the new Icon has it',
  (select count(*) from public.icon_days where contract_id = 'aaaaaaaa-0000-0000-0000-000000000010'
     and (target_text, target_value, target_revision) is distinct from ('3000 steps', 3000::double precision, 0)), 0::bigint);

create table public.t_contracts_before as select id, updated_at, primary_target, icon_target, signature_path, status
from public.contracts;

------------------------------------------------------------------------------
-- M2.1: who may touch the history.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
do $$
begin
  insert into public.icon_revisions (contract_id, user_id, revision, request_id, previous_target_text,
    target_text, effective_day, signature_path)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 1,
    gen_random_uuid(), '10000 steps', '1 steps', current_date,
    '11111111-1111-1111-1111-111111111111/x.png');
  raise exception 'FAIL authenticated inserted a revision';
exception when insufficient_privilege then
  raise notice 'ok  authenticated cannot insert a revision';
end $$;
reset role;

set role anon;
do $$
begin
  perform public.revise_icon_target('aaaaaaaa-0000-0000-0000-000000000001', gen_random_uuid(), 12000,
    '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png');
  raise exception 'FAIL anon revised an Icon';
exception when insufficient_privilege then
  raise notice 'ok  anon cannot call revise_icon_target';
end $$;
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role authenticated;
do $$
begin
  perform public.t_rev('1', '1', 12000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png');
  raise exception 'FAIL a request without a user revised an Icon';
exception when insufficient_privilege then
  if sqlerrm <> 'authentication required' then raise; end if;
  raise notice 'ok  a request without a user is refused';
end $$;
reset role;

------------------------------------------------------------------------------
-- M2.3: A, a London steps Icon, revised up, retried, revised down.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;

select public.t_eq('A: the first revision takes effect from the next Icon day',
  public.t_rev('1', '1', 12000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png'),
  jsonb_build_object('ok', true, 'duplicate', false, 'revision', 1,
    'effectiveDay', public.t_today('Europe/London') + 1, 'targetText', '12000 steps',
    'targetValue', 12000, 'days', 10));
select public.t_eq('A: today keeps the signed target',
  public.t_state('1', public.t_today('Europe/London')), 'pending/10000 steps/10000/0');
select public.t_eq('A: tomorrow is held to the revision',
  public.t_state('1', public.t_today('Europe/London') + 1), 'pending/12000 steps/12000/1');
select public.t_eq('A: the last day too',
  public.t_state('1', public.t_today('Europe/London') + 10), 'pending/12000 steps/12000/1');
select public.t_eq('A: a BROKEN day keeps its target',
  public.t_state('1', public.t_today('Europe/London') - 1), 'broken/10000 steps/10000/0');
select public.t_eq('A: a HONOURED day keeps its target',
  public.t_state('1', public.t_today('Europe/London') - 2), 'honoured/10000 steps/10000/0');

select public.t_eq('A: a retry returns the same revision',
  public.t_rev('1', '1', 12000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png'),
  jsonb_build_object('ok', true, 'duplicate', true, 'revision', 1,
    'effectiveDay', public.t_today('Europe/London') + 1, 'targetText', '12000 steps',
    'targetValue', 12000, 'days', 0));
select public.t_eq('A: a retry with other values still returns the recorded revision',
  public.t_rev('1', '1', 13000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r2.png')->>'targetText',
  '12000 steps');
select public.t_eq('A: one revision recorded',
  (select count(*) from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1::bigint);

select public.t_eq('A: a lower target is a second revision',
  public.t_rev('1', '2', 8000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r2.png'),
  jsonb_build_object('ok', true, 'duplicate', false, 'revision', 2,
    'effectiveDay', public.t_today('Europe/London') + 1, 'targetText', '8000 steps',
    'targetValue', 8000, 'days', 10));
select public.t_eq('A: the second revision records the first as its previous target',
  (select concat_ws('/', previous_target_text, previous_target_value, target_text, target_value, effective_day - public.t_today('Europe/London'))
   from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and revision = 2),
  '12000 steps/12000/8000 steps/8000/1');
select public.t_eq('A: the first revision is unchanged',
  (select concat_ws('/', revision, previous_target_text, target_text, signature_path)
   from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and revision = 1),
  '1/10000 steps/12000 steps/11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png');
select public.t_eq('A: tomorrow now holds the second revision',
  public.t_state('1', public.t_today('Europe/London') + 1), 'pending/8000 steps/8000/2');
select public.t_eq('A: today still holds the signed target',
  public.t_state('1', public.t_today('Europe/London')), 'pending/10000 steps/10000/0');

-- Refusals: nothing is written.
select public.t_eq('A: the same target again is refused',
  public.t_rev('1', '3', 8000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png'),
  '{"ok": false, "reason": "unchanged"}'::jsonb);
select public.t_eq('A: 0 is refused', public.t_rev('1', '3', 0, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid_target');
select public.t_eq('A: a negative target is refused', public.t_rev('1', '3', -5, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid_target');
select public.t_eq('A: above the unit''s maximum is refused', public.t_rev('1', '3', 50001, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid_target');
select public.t_eq('A: a fraction of a step is refused', public.t_rev('1', '3', 9000.5, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid_target');
select public.t_eq('A: NaN is refused', public.t_rev('1', '3', 'NaN', '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid_target');
select public.t_eq('A: Infinity is refused', public.t_rev('1', '3', 'Infinity', '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid_target');
select public.t_eq('A: a missing target is invalid', public.t_rev('1', '3', null, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'invalid');
select public.t_eq('A: a signature in another person''s folder is refused',
  public.t_rev('1', '3', 9000, '22222222-2222-2222-2222-222222222222/client-2/revisions/r1.png')->>'reason', 'invalid_signature');
select public.t_eq('A: the contract''s own signature is refused',
  public.t_rev('1', '3', 9000, '11111111-1111-1111-1111-111111111111/client-1.png')->>'reason', 'invalid_signature');
select public.t_eq('A: an earlier revision''s signature is refused',
  public.t_rev('1', '3', 9000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png')->>'reason', 'invalid_signature');
select public.t_eq('A: a path climbing out of the folder is refused',
  public.t_rev('1', '3', 9000, '11111111-1111-1111-1111-111111111111/../client-1/revisions/r3.png')->>'reason', 'invalid_signature');
select public.t_eq('A: a path outside any user folder is refused',
  public.t_rev('1', '3', 9000, 'client-1/revisions/r3.png')->>'reason', 'invalid_signature');
select public.t_eq('A: a signature that was never uploaded is refused',
  public.t_rev('1', '3', 9000, '11111111-1111-1111-1111-111111111111/client-1/revisions/missing.png')->>'reason', 'signature_missing');
select public.t_eq('A: someone else''s Icon is not found',
  public.t_rev('2', '3', 9, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'not_found');
select public.t_eq('A: an unknown Icon is not found',
  public.t_rev('99', '3', 9000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'reason', 'not_found');
select public.t_eq('A: the refusals wrote nothing',
  (select count(*) from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 2::bigint);
select public.t_eq('A: nor any day',
  public.t_state('1', public.t_today('Europe/London') + 1), 'pending/8000 steps/8000/2');

-- What the person may read.
select public.t_eq('A''s owner reads A''s two revisions only',
  (select count(*) from public.icon_revisions), 2::bigint);
reset role;

-- B: distance in km, stored in meters.
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
set role authenticated;
select public.t_eq('B: 7.5 km is 7500 meters',
  public.t_rev('2', '1', 7.5, '22222222-2222-2222-2222-222222222222/client-2/revisions/r1.png'),
  jsonb_build_object('ok', true, 'duplicate', false, 'revision', 1,
    'effectiveDay', public.t_today('UTC') + 1, 'targetText', '7.5 km', 'targetValue', 7500, 'days', 4));
select public.t_eq('B: two decimals are refused',
  public.t_rev('2', '2', 7.55, '22222222-2222-2222-2222-222222222222/client-2/revisions/r2.png')->>'reason', 'invalid_target');
select public.t_eq('B: above 50 km is refused',
  public.t_rev('2', '2', 50.5, '22222222-2222-2222-2222-222222222222/client-2/revisions/r2.png')->>'reason', 'invalid_target');
select public.t_eq('B: 10.0 km is written 10 km',
  public.t_rev('2', '2', 10.0, '22222222-2222-2222-2222-222222222222/client-2/revisions/r2.png')->>'targetText', '10 km');
select public.t_eq('B: tomorrow is held to 10 km = 10000 meters',
  public.t_state('2', public.t_today('UTC') + 1), 'pending/10 km/10000/2');
select public.t_eq('B''s owner sees B''s revisions only',
  (select count(*) from public.icon_revisions), 2::bigint);
reset role;

-- C: self-reported, text only.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
set role authenticated;
select public.t_eq('C: a self-reported Icon is revised in its own unit',
  public.t_rev('3', '1', 30, '33333333-3333-3333-3333-333333333333/client-3/revisions/r1.png'),
  jsonb_build_object('ok', true, 'duplicate', false, 'revision', 1,
    'effectiveDay', public.t_today('UTC') + 1, 'targetText', '30 reps', 'targetValue', null, 'days', 4));
select public.t_eq('C: tomorrow is held to 30 reps',
  public.t_state('3', public.t_today('UTC') + 1), 'pending/30 reps/1');
reset role;

-- D, E, F: not revisable.
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);
set role authenticated;
select public.t_eq('D: a Word Tracker Icon is not revisable',
  public.t_rev('4', '1', 600, '44444444-4444-4444-4444-444444444444/client-4/revisions/r1.png')->>'reason', 'not_supported');
reset role;
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
set role authenticated;
select public.t_eq('E: an Icon that ended early is not revisable',
  public.t_rev('5', '1', 7000, '55555555-5555-5555-5555-555555555555/client-5/revisions/r1.png')->>'reason', 'not_active');
reset role;
select set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', false);
set role authenticated;
select public.t_eq('F: on its last day there is no next day to revise',
  public.t_rev('6', '1', 7000, '66666666-6666-6666-6666-666666666666/client-6/revisions/r1.png')->>'reason', 'no_future_day');
reset role;

-- G, H: the next day is the Icon's own, either side of the date line.
select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777777', false);
set role authenticated;
select public.t_eq('G: Kiritimati revises from its own tomorrow',
  (public.t_rev('7', '1', 7500, '77777777-7777-7777-7777-777777777777/client-7/revisions/r1.png')->>'effectiveDay')::date,
  public.t_today('Pacific/Kiritimati') + 1);
reset role;
select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', false);
set role authenticated;
select public.t_eq('H: Pago Pago revises from its own tomorrow',
  (public.t_rev('8', '1', 8500, '88888888-8888-8888-8888-888888888888/client-8/revisions/r1.png')->>'effectiveDay')::date,
  public.t_today('Pacific/Pago_Pago') + 1);
reset role;
select public.t_eq('G and H are on different local days',
  public.t_today('Pacific/Kiritimati') > public.t_today('Pacific/Pago_Pago'), true);
select public.t_eq('H: Pago Pago''s today keeps its target',
  public.t_state('8', public.t_today('Pacific/Pago_Pago')), 'pending/8000 steps/8000/0');

-- I: no Icon day tomorrow, so the next one.
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', false);
set role authenticated;
select public.t_eq('I: the revision starts on the next scheduled day',
  (public.t_rev('9', '1', 9500, '99999999-9999-9999-9999-999999999999/client-9/revisions/r1.png')->>'effectiveDay')::date,
  public.t_today('UTC') + 2);
reset role;

-- The contracts themselves never change, and no contract was added.
select public.t_eq('no contract changed',
  (select count(*) from public.contracts c join public.t_contracts_before b using (id)
   where (c.updated_at, c.primary_target, c.icon_target, c.signature_path, c.status)
         is distinct from (b.updated_at, b.primary_target, b.icon_target, b.signature_path, b.status)), 0::bigint);
select public.t_eq('no contract was added',
  (select count(*) from public.contracts) - (select count(*) from public.t_contracts_before), 0::bigint);

------------------------------------------------------------------------------
-- M2.1: the history is immutable, even for the service role.
set role service_role;
do $$
begin
  update public.icon_revisions set target_text = '1 steps' where revision = 1;
  raise exception 'FAIL service_role edited a revision';
exception when insufficient_privilege then
  if sqlerrm not like 'Icon revisions cannot%' then raise; end if;
  raise notice 'ok  a revision cannot be edited';
end $$;
do $$
begin
  delete from public.icon_revisions where revision = 1;
  raise exception 'FAIL service_role deleted a revision';
exception when insufficient_privilege then
  if sqlerrm not like 'Icon revisions cannot%' then raise; end if;
  raise notice 'ok  a revision cannot be deleted on its own';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
do $$
begin
  update public.icon_revisions set target_text = '1 steps';
  raise exception 'FAIL authenticated edited a revision';
exception when insufficient_privilege then
  if sqlerrm not like 'permission denied%' then raise; end if;
  raise notice 'ok  authenticated cannot edit a revision';
end $$;
do $$
begin
  delete from public.icon_revisions;
  raise exception 'FAIL authenticated deleted a revision';
exception when insufficient_privilege then
  if sqlerrm not like 'permission denied%' then raise; end if;
  raise notice 'ok  authenticated cannot delete a revision';
end $$;
reset role;

------------------------------------------------------------------------------
-- M2.4: the server readers hold each day to its own target.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('measure: today is measured against the signed target',
  (select target from public.icon_days_to_measure()
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = public.t_today('Europe/London')),
  10000::double precision);
select public.t_eq('record: 9000 today stays pending under the signed 10000',
  public.record_icon_measurements(jsonb_build_array(jsonb_build_object(
    'contractId', 'aaaaaaaa-0000-0000-0000-000000000001', 'day', public.t_today('Europe/London'),
    'value', 9000, 'measuredThrough', now())))->>'pending', '1');
reset role;

-- Yesterday as if a revision to 3000 had reached it (a day revised earlier).
update public.icon_days set target_text = '3000 steps', target_value = 3000, target_revision = 1
where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = public.t_today('Europe/London') - 1;
set role authenticated;
select public.t_eq('measure: a revised day is measured against its own target',
  (select target from public.icon_days_to_measure()
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = public.t_today('Europe/London') - 1),
  3000::double precision);
select public.t_eq('record: 5000 turns that BROKEN day HONOURED under its 3000, not the signed 10000',
  public.record_icon_measurements(jsonb_build_array(jsonb_build_object(
    'contractId', 'aaaaaaaa-0000-0000-0000-000000000001', 'day', public.t_today('Europe/London') - 1,
    'value', 5000, 'measuredThrough', now())))->>'honoured', '1');
reset role;

select public.t_eq('push: tomorrow''s morning card carries the revision',
  (select j.target from public.icon_push_jobs(
     (select morning_at + interval '1 minute' from public.icon_days
      where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = public.t_today('Europe/London') + 1)) j
   where j.contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and j.job = 'morning'),
  '8000 steps');
select public.t_eq('push: its facts say 8,000 STEPS',
  (select concat_ws(' ', f->>'targetValue', f->>'targetUnit') from (
     select public.icon_push_facts(to_jsonb(j)) f from public.icon_push_jobs(
       (select morning_at + interval '1 minute' from public.icon_days
        where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = public.t_today('Europe/London') + 1)) j
     where j.contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and j.job = 'morning') x),
  '8,000 STEPS');
select public.t_eq('push: today''s morning card keeps the signed target',
  (select j.target from public.icon_push_jobs(
     (select morning_at + interval '1 minute' from public.icon_days
      where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = public.t_today('Europe/London'))) j
   where j.contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and j.job = 'morning'),
  '10000 steps');

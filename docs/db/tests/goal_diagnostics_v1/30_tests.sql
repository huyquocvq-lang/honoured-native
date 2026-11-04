\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;

-- One goal's afternoon: crossed 17:01–17:02 by Core Motion's minutes, the data
-- readable between 16:58 and 17:03, noticed at 17:03, notification asked
-- for at once, delivered by iOS a second later, opened at 17:10.
create temp table walk as select public.record_goal_diagnostics(jsonb_build_array(
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000001', 'event', 'reading', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T05:58:00Z', 'reason', 'value', 'source', 'core_motion', 'metric', 'steps',
    'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'day', '2026-10-21', 'value', 9950, 'target', 10000,
    'details', jsonb_build_object('trigger', 'sync_pass'), 'deviceTime', '2026-10-21T05:58:00Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000002', 'event', 'goal_detected', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:03:00Z', 'source', 'core_motion', 'metric', 'steps',
    'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'day', '2026-10-21', 'value', 10050, 'target', 10000,
    'details', jsonb_build_object('trigger', 'bg_app_refresh'), 'deviceTime', '2026-10-21T06:03:00Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000003', 'event', 'notification_requested', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:03:00Z', 'reason', 'scheduled',
    'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'day', '2026-10-21',
    'details', jsonb_build_object('identifier', 'goal-aaaaaaaa-0000-0000-0000-000000000001:primary-2026-10-21'),
    'deviceTime', '2026-10-21T06:03:00Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000004', 'event', 'data_available', 'certainty', 'estimated',
    'windowStart', '2026-10-21T05:58:00Z', 'windowEnd', '2026-10-21T06:03:00Z', 'method', 'between_reads', 'source', 'core_motion',
    'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'day', '2026-10-21',
    'deviceTime', '2026-10-21T06:03:00Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000005', 'event', 'goal_crossed', 'certainty', 'estimated',
    'windowStart', '2026-10-21T06:01:00Z', 'windowEnd', '2026-10-21T06:02:00Z', 'method', 'motion_query', 'source', 'core_motion',
    'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'day', '2026-10-21', 'target', 10000,
    'deviceTime', '2026-10-21T06:03:01Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000006', 'event', 'notification_delivered', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:03:01Z', 'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'day', '2026-10-21',
    'details', jsonb_build_object('identifier', 'goal-aaaaaaaa-0000-0000-0000-000000000001:primary-2026-10-21', 'seen_in', 'notification_center'),
    'deviceTime', '2026-10-21T06:09:00Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000007', 'event', 'notification_opened', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:10:00Z', 'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary',
    'details', jsonb_build_object('identifier', 'goal-aaaaaaaa-0000-0000-0000-000000000001:primary-2026-10-21'),
    'deviceTime', '2026-10-21T06:10:00Z', 'sentAt', '2026-10-21T06:20:00Z'),
  -- The card is updated before the goal check in a wake: a second earlier
  -- it already showed the goal reached. An earlier update, not yet reached,
  -- does not count.
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000008', 'event', 'live_activity_update', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:02:59Z', 'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'metric', 'steps',
    'value', 10050, 'target', 10000, 'source', 'core_motion', 'details', jsonb_build_object('kind', 'contract', 'reached', 'true'),
    'deviceTime', '2026-10-21T06:02:59Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-00000000000a', 'event', 'live_activity_update', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:01:30Z', 'activityId', 'aaaaaaaa-0000-0000-0000-000000000001:primary', 'metric', 'steps',
    'value', 9990, 'target', 10000, 'source', 'core_motion', 'details', jsonb_build_object('kind', 'contract', 'reached', 'false'),
    'deviceTime', '2026-10-21T06:01:30Z', 'sentAt', '2026-10-21T06:20:00Z'),
  jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000009', 'event', 'app_ran', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:03:00Z', 'reason', 'bg_app_refresh',
    'details', jsonb_build_object('protected_data', 'locked', 'low_power', 'false'),
    'deviceTime', '2026-10-21T06:03:00Z', 'sentAt', '2026-10-21T06:20:00Z')
)) as r;
select public.t_eq('a day of lines is stored', (select r from walk), '{"inserted": 10, "duplicates": 0, "skipped": 0}'::jsonb);
select public.t_eq('lines belong to the caller', (select count(*) from public.goal_diagnostics where user_id = '11111111-1111-1111-1111-111111111111'), 10::bigint);

-- Uploading the same lines again stores nothing new.
select public.t_eq('a line sent twice is kept once',
  public.record_goal_diagnostics(jsonb_build_array(jsonb_build_object('id', 'a0000000-0000-0000-0000-000000000002',
    'event', 'goal_detected', 'certainty', 'recorded', 'occurredAt', '2026-10-21T06:03:00Z', 'deviceTime', '2026-10-21T06:03:00Z'))),
  '{"inserted": 0, "duplicates": 1, "skipped": 0}'::jsonb);

-- Lines that break the rules are skipped; the rest of the batch goes in.
select public.t_eq('rule breakers are skipped', public.record_goal_diagnostics(jsonb_build_array(
  -- an estimate given as a single time
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000001', 'event', 'goal_crossed', 'certainty', 'estimated',
    'occurredAt', '2026-10-21T06:01:00Z', 'method', 'motion_query', 'deviceTime', '2026-10-21T06:03:00Z'),
  -- an estimate without its method
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000002', 'event', 'goal_crossed', 'certainty', 'estimated',
    'windowStart', '2026-10-21T06:01:00Z', 'windowEnd', '2026-10-21T06:02:00Z', 'deviceTime', '2026-10-21T06:03:00Z'),
  -- a window that runs backwards
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000003', 'event', 'goal_crossed', 'certainty', 'estimated',
    'windowStart', '2026-10-21T06:02:00Z', 'windowEnd', '2026-10-21T06:01:00Z', 'method', 'x', 'deviceTime', '2026-10-21T06:03:00Z'),
  -- recorded with no time, unknown with one
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000004', 'event', 'goal_detected', 'certainty', 'recorded', 'deviceTime', '2026-10-21T06:03:00Z'),
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000005', 'event', 'notification_delivered', 'certainty', 'unknown',
    'occurredAt', '2026-10-21T06:03:00Z', 'deviceTime', '2026-10-21T06:03:00Z'),
  -- unknown event, unknown source, broken id, no device time
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000006', 'event', 'screen_seen', 'certainty', 'recorded',
    'occurredAt', '2026-10-21T06:03:00Z', 'deviceTime', '2026-10-21T06:03:00Z'),
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000007', 'event', 'reading', 'certainty', 'recorded', 'source', 'garmin',
    'occurredAt', '2026-10-21T06:03:00Z', 'deviceTime', '2026-10-21T06:03:00Z'),
  jsonb_build_object('id', 'not-a-uuid', 'event', 'reading', 'certainty', 'recorded', 'occurredAt', '2026-10-21T06:03:00Z', 'deviceTime', '2026-10-21T06:03:00Z'),
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000008', 'event', 'reading', 'certainty', 'recorded', 'occurredAt', '2026-10-21T06:03:00Z'),
  -- and one good line
  jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000009', 'event', 'notification_delivered', 'certainty', 'unknown',
    'reason', 'not_in_notification_center', 'details', jsonb_build_object('identifier', 'goal-x-2026-10-20'), 'deviceTime', '2026-10-21T06:03:00Z')
)), '{"inserted": 1, "duplicates": 0, "skipped": 9}'::jsonb);

-- Large uploads are refused whole, so the device sends small batches.
do $$
begin
  perform public.record_goal_diagnostics((select jsonb_agg(jsonb_build_object('id', gen_random_uuid())) from generate_series(1, 51)));
  raise exception 'FAIL a batch of 51 was accepted';
exception when sqlstate '22023' then
  raise notice 'ok  a batch over 50 rows is refused';
end $$;

-- The timeline of the day.
create temp table line as select * from public.goal_diagnostics_timeline(date '2026-10-21', date '2026-10-21');
select public.t_eq('one goal that day', (select count(*) from line), 1::bigint);
select public.t_eq('crossing window and method', (select crossed_from || ' ' || crossed_to || ' ' || crossed_method from line),
  (timestamptz '2026-10-21T06:01:00Z')::text || ' ' || (timestamptz '2026-10-21T06:02:00Z')::text || ' motion_query');
select public.t_eq('noticed by a background refresh', (select detected_trigger from line), 'bg_app_refresh');
select public.t_eq('notification scheduled and delivered as recorded', (select notification || '/' || delivery from line), 'scheduled/recorded');
select public.t_eq('noticed 60–120 s after the crossing', (select detected_after_crossing_min_s || '/' || detected_after_crossing_max_s from line), '60/120');
select public.t_eq('delivered 61–121 s after the crossing', (select delivered_after_crossing_min_s || '/' || delivered_after_crossing_max_s from line), '61/121');
select public.t_eq('delivered 1 s after it was noticed', (select delivered_after_detected_s from line), 1::float8);
select public.t_eq('opened at 17:10', (select opened_at from line), timestamptz '2026-10-21T06:10:00Z');
select public.t_eq('the card showed it reached a second before the check', (select first_card_update_at from line), timestamptz '2026-10-21T06:02:59Z');
select public.t_eq('the Icon day stamp is the server''s', (select icon_stamped_at from line), timestamptz '2026-10-21 17:09:00+11');
select public.t_eq('data readable between two reads', (select data_available_from || ' ' || data_available_to from line),
  (timestamptz '2026-10-21T05:58:00Z')::text || ' ' || (timestamptz '2026-10-21T06:03:00Z')::text);
select public.t_eq('device clock offset is shown', (select device_clock_offset_s is not null from line), true);
reset role;

-- Someone else sees none of it and cannot write it.
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
set role authenticated;
select public.t_eq('another account sees no lines', (select count(*) from public.goal_diagnostics), 0::bigint);
select public.t_eq('another account gets no timeline', (select count(*) from public.goal_diagnostics_timeline()), 0::bigint);
do $$
begin
  insert into public.goal_diagnostics (user_id, id, event, certainty, occurred_at, device_time)
  values ('11111111-1111-1111-1111-111111111111', gen_random_uuid(), 'reading', 'recorded', now(), now());
  raise exception 'FAIL a line for another account was accepted';
exception when insufficient_privilege then
  raise notice 'ok  a line for another account is refused';
end $$;
reset role;

-- Lines are never changed or removed by the app.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
do $$
begin
  update public.goal_diagnostics set value = 1;
  raise exception 'FAIL a line was changed';
exception when insufficient_privilege then
  raise notice 'ok  lines cannot be changed';
end $$;
do $$
begin
  delete from public.goal_diagnostics;
  raise exception 'FAIL a line was removed';
exception when insufficient_privilege then
  raise notice 'ok  lines cannot be removed';
end $$;
do $$
begin
  perform public.purge_goal_diagnostics(interval '1 day');
  raise exception 'FAIL the app could purge';
exception when insufficient_privilege then
  raise notice 'ok  the app cannot purge';
end $$;
reset role;

-- The purge keeps what is younger than its argument.
update public.goal_diagnostics set received_at = now() - interval '100 days'
where id = 'a0000000-0000-0000-0000-000000000009';
select public.t_eq('purge removes old lines only', public.purge_goal_diagnostics(interval '90 days'), 1);
select public.t_eq('the rest stay', (select count(*) from public.goal_diagnostics), 10::bigint);

-- Not callable without a signed-in user.
select set_config('request.jwt.claim.sub', '', false);
set role authenticated;
do $$
begin
  perform public.record_goal_diagnostics('[]'::jsonb);
  raise exception 'FAIL anonymous call was accepted';
exception when sqlstate '42501' then
  raise notice 'ok  anonymous call refused';
end $$;
reset role;

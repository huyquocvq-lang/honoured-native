-- Icons signed before icon_revisions_v1.sql, one owner each (an owner can
-- hold one running Icon a day). Dates are relative to now() in each Icon's
-- time zone; created_at is backdated so the past days exist.
--   A steps "10000 steps", daily, Europe/London, morning 08:00 / evening 20:00
--   B distance "5 km" (5000 meters), daily, UTC
--   C self-reported "20 reps", daily, UTC
--   D Word Tracker "500 words", daily, UTC
--   E steps, ended early (status amended)
--   F steps, whose last day is today
--   G / H steps, daily, Pacific/Kiritimati (UTC+14) / Pacific/Pago_Pago (UTC-11)
--   I steps, every weekday but tomorrow's, UTC
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333'), ('44444444-4444-4444-4444-444444444444'),
  ('55555555-5555-5555-5555-555555555555'), ('66666666-6666-6666-6666-666666666666'),
  ('77777777-7777-7777-7777-777777777777'), ('88888888-8888-8888-8888-888888888888'),
  ('99999999-9999-9999-9999-999999999999');

create function public.t_sign(
  p_id text, p_user text, p_tz text, p_start_offset integer, p_count integer, p_unit text,
  p_target text, p_metric text, p_value double precision, p_icon_unit text,
  p_weekdays smallint[] default '{1,2,3,4,5,6,7}'
) returns void
language plpgsql as $$
declare
  v_today date := (now() at time zone p_tz)::date;
begin
  insert into public.contracts (
    id, user_id, client_id, created_at, deadline, primary_type, primary_activity, primary_target,
    because, signature_path, status, icon_weekdays, icon_start_day, icon_period_count,
    icon_period_unit, icon_deadline_time, icon_timezone, icon_morning_time, icon_evening_time,
    icon_metric, icon_target, icon_unit
  ) values (
    ('aaaaaaaa-0000-0000-0000-' || lpad(p_id, 12, '0'))::uuid, p_user::uuid, 'client-' || p_id,
    now() - make_interval(days => -p_start_offset + 1), now(), 'complete', 'Icon ' || p_id, p_target,
    'because', p_user || '/client-' || p_id || '.png', 'active', p_weekdays, v_today + p_start_offset,
    p_count, p_unit, '00:00', p_tz, '08:00', '20:00', p_metric, p_value, p_icon_unit
  );
end $$;

select public.t_sign('1', '11111111-1111-1111-1111-111111111111', 'Europe/London', -3, 2, 'week', '10000 steps', 'steps', 10000, 'count');
select public.t_sign('2', '22222222-2222-2222-2222-222222222222', 'UTC', -2, 1, 'week', '5 km', 'distance_walking_running', 5000, 'meters');
select public.t_sign('3', '33333333-3333-3333-3333-333333333333', 'UTC', -2, 1, 'week', '20 reps', null, null, null);
select public.t_sign('5', '55555555-5555-5555-5555-555555555555', 'UTC', -2, 1, 'week', '6000 steps', 'steps', 6000, 'count');
select public.t_sign('6', '66666666-6666-6666-6666-666666666666', 'UTC', -2, 3, 'day', '6000 steps', 'steps', 6000, 'count');
select public.t_sign('7', '77777777-7777-7777-7777-777777777777', 'Pacific/Kiritimati', -1, 1, 'week', '7000 steps', 'steps', 7000, 'count');
select public.t_sign('8', '88888888-8888-8888-8888-888888888888', 'Pacific/Pago_Pago', -1, 1, 'week', '8000 steps', 'steps', 8000, 'count');
select public.t_sign('9', '99999999-9999-9999-9999-999999999999', 'UTC', -1, 2, 'week', '9000 steps', 'steps', 9000, 'count',
  array(select d from generate_series(1, 7) d
        where d <> extract(isodow from (now() at time zone 'UTC')::date + 1))::smallint[]);

-- D: a Word Tracker Icon.
insert into public.contracts (
  id, user_id, client_id, created_at, deadline, primary_type, primary_activity, primary_target,
  because, signature_path, status, icon_weekdays, icon_start_day, icon_period_count,
  icon_period_unit, icon_deadline_time, icon_timezone, word_source_id, word_source_kind, word_target
) values (
  'aaaaaaaa-0000-0000-0000-000000000004', '44444444-4444-4444-4444-444444444444', 'client-4',
  now() - interval '3 days', now(), 'complete', 'Write', '500 words', 'because',
  '44444444-4444-4444-4444-444444444444/client-4.png', 'active', '{1,2,3,4,5,6,7}',
  (now() at time zone 'UTC')::date - 2, 1, 'week', '00:00', 'UTC', 'source-1', 'word', 500
);

-- E ends early.
update public.contracts set status = 'amended', resolved_at = now()
where id = 'aaaaaaaa-0000-0000-0000-000000000005';

-- A's past days: two days ago HONOURED, yesterday BROKEN (missed).
update public.icon_days set status = 'honoured', resolution = 'target_met', measured_value = 10500,
  measured_source = 'healthkit', scored_at = now()
where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and day = (now() at time zone 'Europe/London')::date - 2;
update public.icon_days set status = 'broken', resolution = 'target_missed', measured_value = 4000,
  measured_source = 'healthkit', scored_at = now()
where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and day = (now() at time zone 'Europe/London')::date - 1;

-- updated_at before the migration, to show the backfill leaves it alone.
create table public.t_before as select contract_id, day, updated_at from public.icon_days;

-- Signatures already uploaded (the storage object exists).
insert into storage.objects (bucket_id, name, owner, owner_id)
select 'signatures', p, split_part(p, '/', 1)::uuid, split_part(p, '/', 1) from unnest(array[
  '11111111-1111-1111-1111-111111111111/client-1.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/r2.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/c1.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/c2.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/c3.png',
  '22222222-2222-2222-2222-222222222222/client-2/revisions/r1.png',
  '22222222-2222-2222-2222-222222222222/client-2/revisions/r2.png',
  '33333333-3333-3333-3333-333333333333/client-3/revisions/r1.png',
  '44444444-4444-4444-4444-444444444444/client-4/revisions/r1.png',
  '55555555-5555-5555-5555-555555555555/client-5/revisions/r1.png',
  '66666666-6666-6666-6666-666666666666/client-6/revisions/r1.png',
  '77777777-7777-7777-7777-777777777777/client-7/revisions/r1.png',
  '88888888-8888-8888-8888-888888888888/client-8/revisions/r1.png',
  '99999999-9999-9999-9999-999999999999/client-9/revisions/r1.png'
]) p;

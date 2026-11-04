-- Helpers for the weekday target checks, created after
-- icon_weekday_targets_v1.sql (they write its column). The revision suite's
-- 20_helpers.sql comes first: t_state, t_today and t_rev.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1'), ('e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2'),
  ('e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3'), ('e4e4e4e4-e4e4-e4e4-e4e4-e4e4e4e4e4e4'),
  ('e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5'), ('e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6'),
  ('e7e7e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7'), ('e8e8e8e8-e8e8-e8e8-e8e8-e8e8e8e8e8e8');

-- An Icon signed with weekday targets, like t_sign (10_seed.sql).
create function public.t_sign_targets(
  p_id text, p_user text, p_tz text, p_start_offset integer, p_count integer, p_unit text,
  p_target text, p_metric text, p_value double precision, p_icon_unit text,
  p_weekdays smallint[], p_day_targets jsonb, p_word boolean default false
) returns void
language plpgsql as $$
declare
  v_today date := (now() at time zone p_tz)::date;
begin
  insert into public.contracts (
    id, user_id, client_id, created_at, deadline, primary_type, primary_activity, primary_target,
    because, signature_path, status, icon_weekdays, icon_start_day, icon_period_count,
    icon_period_unit, icon_deadline_time, icon_timezone, icon_morning_time, icon_evening_time,
    icon_metric, icon_target, icon_unit, icon_day_targets,
    word_source_id, word_source_kind, word_target
  ) values (
    ('aaaaaaaa-0000-0000-0000-' || lpad(p_id, 12, '0'))::uuid, p_user::uuid, 'client-' || p_id,
    now() - make_interval(days => -p_start_offset + 1), now(), 'complete', 'Icon ' || p_id, p_target,
    'because', p_user || '/client-' || p_id || '.png', 'active', p_weekdays, v_today + p_start_offset,
    p_count, p_unit, '00:00', p_tz, '08:00', '20:00', p_metric, p_value, p_icon_unit, p_day_targets,
    case when p_word then 'source-' || p_id end, case when p_word then 'word' end,
    case when p_word then 500 end
  );
end $$;

-- The error a statement raises, or 'no error'.
create function public.t_err(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlerrm;
end $$;

-- ISO weekday (as text) of today + p_offset in p_tz.
create function public.t_dow(p_tz text, p_offset integer) returns text
language sql as $$ select extract(isodow from public.t_today(p_tz) + p_offset)::integer::text $$;

create function public.t_revs(p_contract text, p_request text, p_targets jsonb, p_path text) returns jsonb
language sql as $$
  select public.revise_icon_targets(
    ('aaaaaaaa-0000-0000-0000-' || lpad(p_contract, 12, '0'))::uuid,
    ('cccccccc-0000-0000-0000-' || lpad(p_request, 12, '0'))::uuid,
    p_targets, p_path)
$$;

-- A push job for a day of a seeded contract, as icon_push_jobs() hands it on.
create function public.t_job(p_contract text, p_day date) returns jsonb
language sql as $$
  select jsonb_build_object(
    'client_id', 'client-' || p_contract,
    'contract_id', ('aaaaaaaa-0000-0000-0000-' || lpad(p_contract, 12, '0'))::uuid,
    'day', p_day, 'session_number', 3, 'total_sessions', 14, 'target', '12000 steps',
    'activity', 'Walking', 'because', 'because', 'deadline_at', now())
$$;

-- Signatures already uploaded.
insert into storage.objects (bucket_id, name, owner, owner_id)
select 'signatures', p, split_part(p, '/', 1)::uuid, split_part(p, '/', 1) from unnest(array[
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w1.png',
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w2.png',
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w3.png',
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w4.png',
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w5.png',
  'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png',
  'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2/client-22/revisions/w1.png',
  'e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3/client-23/revisions/w1.png',
  'e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5/client-25/revisions/w1.png',
  'e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6/client-26/revisions/w1.png',
  '44444444-4444-4444-4444-444444444444/client-4/revisions/w1.png',
  '55555555-5555-5555-5555-555555555555/client-5/revisions/w1.png'
]) p;

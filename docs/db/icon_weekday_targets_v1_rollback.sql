-- Rollback of icon_weekday_targets_v1.sql: contracts_icon_guard() and
-- icon_push_facts() get production's bodies back verbatim, contracts_icon_days()
-- its icon_revisions_v1.sql body, revise_icon_targets() goes, and so do
-- contracts.icon_day_targets and icon_revisions.changes.
-- Icon days keep the targets they hold, so scoring and cards are unchanged;
-- what is lost is the record of the signed weekday targets and of each
-- weekday revision's changes beyond its first (the revision row stays). When
-- either is held the rollback refuses, unless the session first runs
--   set honoured.discard_icon_weekday_targets = 'yes';
-- (export them before that). Re-running is harmless. icon_revisions_v1.sql
-- and icon_revisions_v1_1.sql stay in place.
begin;

do $$
declare
  v_guard text := md5(pg_get_functiondef(to_regprocedure('public.contracts_icon_guard()')));
  v_days text := md5(pg_get_functiondef(to_regprocedure('public.contracts_icon_days()')));
  v_facts text := md5(pg_get_functiondef(to_regprocedure('public.icon_push_facts(jsonb)')));
  v_contracts bigint := 0;
  v_revisions bigint := 0;
begin
  if to_regclass('public.icon_revisions') is null then
    raise exception 'icon_revisions_v1 is not in place; nothing for icon_weekday_targets_v1_rollback.sql to undo';
  end if;
  -- This file's bodies, or production's after a rollback.
  if v_guard not in ('05d2aad1b81f327fe38fe69dfcbe2ec6', 'b29e8ef41fc29f0d55c48092acf7c5f3')
     or v_days not in ('bc7b184a1d698d49ca70dfe3dbf5f9dc', 'dbc8968992cb54558dd4f097d16ed221')
     or v_facts not in ('3d396c2e252e2793768c9a73e02a7fdb', 'ec9b2ae4012553c2945e80c6f0de8b58') then
    raise exception 'contracts_icon_guard(), contracts_icon_days() or icon_push_facts() is not the expected version (md5 % / % / %); not overwriting it',
      v_guard, v_days, v_facts;
  end if;
  -- Held to the end: a signing or revision committing meanwhile is counted.
  lock table public.contracts, public.icon_revisions in share row exclusive mode;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'contracts' and column_name = 'icon_day_targets') then
    execute 'select count(*) from public.contracts where icon_day_targets is not null' into v_contracts;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'icon_revisions' and column_name = 'changes') then
    execute 'select count(*) from public.icon_revisions where changes is not null' into v_revisions;
  end if;
  if (v_contracts > 0 or v_revisions > 0)
     and coalesce(current_setting('honoured.discard_icon_weekday_targets', true), '') <> 'yes' then
    raise exception '% Icons hold weekday targets and % revisions weekday changes; set honoured.discard_icon_weekday_targets = ''yes'' to discard them',
      v_contracts, v_revisions;
  end if;
end $$;

drop function if exists public.revise_icon_targets(uuid, uuid, jsonb, text);

CREATE OR REPLACE FUNCTION public.contracts_icon_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  canonical_unit text;
  final_deadline timestamptz;
begin
  if tg_op = 'UPDATE' and old.icon_weekdays is not null then
    -- Signed terms are locked for the whole period. Only the reminder times
    -- may change, and a resolved Icon never becomes active again.
    new.icon_weekdays := old.icon_weekdays;
    new.icon_start_day := old.icon_start_day;
    new.icon_period_count := old.icon_period_count;
    new.icon_period_unit := old.icon_period_unit;
    new.icon_end_day := old.icon_end_day;
    new.icon_deadline_time := old.icon_deadline_time;
    new.icon_timezone := old.icon_timezone;
    new.icon_metric := old.icon_metric;
    new.icon_target := old.icon_target;
    new.icon_unit := old.icon_unit;
    new.primary_type := old.primary_type;
    new.primary_activity := old.primary_activity;
    new.primary_target := old.primary_target;
    new.created_at := old.created_at;
    new.deadline := old.deadline;
    new.standing := false;
    if old.status <> 'active' then
      new.status := old.status;
      new.resolved_at := old.resolved_at;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' or new.icon_weekdays is null then
    -- Icon terms are attached when the contract is signed, never later.
    new.icon_weekdays := null;
    new.icon_start_day := null;
    new.icon_period_count := null;
    new.icon_period_unit := null;
    new.icon_end_day := null;
    new.icon_deadline_time := null;
    new.icon_timezone := null;
    new.icon_morning_time := null;
    new.icon_evening_time := null;
    new.icon_metric := null;
    new.icon_target := null;
    new.icon_unit := null;
    return new;
  end if;

  -- The web upserts every change, so BEFORE INSERT also sees rows that
  -- already exist. ON CONFLICT turns those into an update that keeps the
  -- stored terms, so they are not validated again here.
  if exists (
    select 1 from public.contracts c
    where c.user_id = new.user_id and c.client_id = new.client_id
  ) then
    return new;
  end if;

  -- A new Icon contract.
  new.icon_weekdays := array(
    select distinct d from unnest(new.icon_weekdays) d where d is not null order by d
  );
  if cardinality(new.icon_weekdays) = 0
     or exists (select 1 from unnest(new.icon_weekdays) d where d not between 1 and 7) then
    raise exception 'icon_weekdays must hold ISO weekdays 1 to 7' using errcode = '22023';
  end if;
  if new.standing then
    raise exception 'an Icon cannot be a Standing contract' using errcode = '22023';
  end if;
  if new.icon_start_day is null or new.icon_deadline_time is null then
    raise exception 'icon_start_day and icon_deadline_time are required' using errcode = '22023';
  end if;
  if new.icon_timezone is null
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = new.icon_timezone) then
    raise exception 'icon_timezone must be an IANA time zone' using errcode = '22023';
  end if;
  if new.icon_period_unit is null
     or new.icon_period_unit not in ('day', 'week', 'month', 'year')
     or new.icon_period_count is null or new.icon_period_count < 1 then
    raise exception 'icon period must be a positive count of day, week, month or year' using errcode = '22023';
  end if;

  -- Calendar arithmetic clamps to the end of a shorter month, as the web does.
  new.icon_end_day := (new.icon_start_day + case new.icon_period_unit
    when 'day' then make_interval(days => new.icon_period_count)
    when 'week' then make_interval(weeks => new.icon_period_count)
    when 'month' then make_interval(months => new.icon_period_count)
    else make_interval(years => new.icon_period_count)
  end)::date;
  if new.icon_end_day - new.icon_start_day < 2
     or new.icon_end_day > (new.icon_start_day + interval '1 year')::date then
    raise exception 'icon period must last from 2 days to 1 year' using errcode = '22023';
  end if;

  if new.icon_morning_time is not null and new.icon_evening_time is not null
     and new.icon_morning_time >= new.icon_evening_time then
    raise exception 'the morning reminder must be earlier than the evening reminder' using errcode = '22023';
  end if;

  if (new.icon_metric is null) <> (new.icon_target is null)
     or (new.icon_metric is null) <> (new.icon_unit is null) then
    raise exception 'icon_metric, icon_target and icon_unit are set together' using errcode = '22023';
  end if;
  if new.icon_metric is not null then
    canonical_unit := case new.icon_metric
      when 'steps' then 'count'
      when 'distance_walking_running' then 'meters'
      when 'distance_cycling' then 'meters'
      when 'distance_swimming' then 'meters'
      when 'active_energy' then 'kcal'
      when 'exercise_minutes' then 'minutes'
    end;
    if canonical_unit is null then
      raise exception 'icon_metric % cannot verify an Icon', new.icon_metric using errcode = '22023';
    end if;
    -- Postgres sorts NaN above Infinity, so one upper bound rejects both.
    if new.icon_unit <> canonical_unit
       or new.icon_target <= 0 or new.icon_target >= 'Infinity'::double precision then
      raise exception 'icon_target must be a positive number of %', canonical_unit using errcode = '22023';
    end if;
  end if;

  -- The contract lasts until the cut-off of its last Icon day.
  select max(s.deadline_at) into final_deadline
  from public.icon_schedule(
    new.icon_start_day, new.icon_end_day, new.icon_weekdays,
    new.icon_deadline_time, new.icon_timezone, new.created_at
  ) s;
  if final_deadline is null then
    raise exception 'the Icon has no scheduled day' using errcode = '22023';
  end if;
  new.deadline := final_deadline;
  return new;
end;
$function$;
revoke all on function public.contracts_icon_guard from public;
grant execute on function public.contracts_icon_guard to service_role;

CREATE OR REPLACE FUNCTION public.contracts_icon_days()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.icon_weekdays is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    if new.status = 'active' then
      insert into public.icon_days (
        contract_id, user_id, day, session_number, deadline_at, morning_at, evening_at,
        target_text, target_value
      )
      select new.id, new.user_id, s.day, s.session_number, s.deadline_at,
             case when new.icon_morning_time is null then null
                  else (s.day + new.icon_morning_time) at time zone new.icon_timezone end,
             case when new.icon_evening_time is null then null
                  else (s.day + new.icon_evening_time) at time zone new.icon_timezone end,
             new.primary_target, new.icon_target
      from public.icon_schedule(
        new.icon_start_day, new.icon_end_day, new.icon_weekdays,
        new.icon_deadline_time, new.icon_timezone, new.created_at
      ) s
      on conflict (contract_id, day) do nothing;
    end if;
    return null;
  end if;

  -- New reminder times apply to the days still ahead.
  if new.icon_morning_time is distinct from old.icon_morning_time
     or new.icon_evening_time is distinct from old.icon_evening_time then
    update public.icon_days d
    set morning_at = case when new.icon_morning_time is null then null
                          else (d.day + new.icon_morning_time) at time zone new.icon_timezone end,
        evening_at = case when new.icon_evening_time is null then null
                          else (d.day + new.icon_evening_time) at time zone new.icon_timezone end
    where d.contract_id = new.id
      and d.status = 'pending'
      and d.deadline_at > now();
  end if;

  -- Early exit: every day still ahead is amended. A day whose cut-off has
  -- passed stays pending until it is scored from its data.
  if new.status = 'amended' and old.status = 'active' then
    update public.icon_days d
    set status = 'amended', resolution = 'amended', scored_at = now()
    where d.contract_id = new.id
      and d.status = 'pending'
      and d.deadline_at > now();
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.icon_push_facts(p_job jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'contractId', p_job->>'client_id',
    'iconDay', p_job->>'day',
    'weekday', upper(to_char((p_job->>'day')::date, 'Dy')),
    'sessionNumber', s.session_number,
    'totalSessions', greatest(s.session_number, coalesce((p_job->>'total_sessions')::integer, s.session_number)),
    'targetValue', public.icon_cut(t.value, 16),
    'targetUnit', upper(public.icon_cut(t.unit, 16)),
    'activityName', public.icon_cut(p_job->>'activity', 40),
    'because', public.icon_cut(p_job->>'because', 120),
    'deadline', floor(extract(epoch from (p_job->>'deadline_at')::timestamptz))::bigint
  )
  from (select greatest(coalesce((p_job->>'session_number')::integer, 1), 1) as session_number) s,
       public.icon_target_split(p_job->>'target') t
$function$;
revoke all on function public.icon_push_facts from public;
grant execute on function public.icon_push_facts to service_role;

alter table public.icon_revisions drop constraint if exists icon_revisions_changes_array;
alter table public.icon_revisions drop column if exists changes;
alter table public.contracts drop column if exists icon_day_targets;
comment on column public.icon_days.target_text is
  'The target this day is held to, as the contract writes it ("<number> <unit>"): the signed primary_target, or the revision named by target_revision.';

commit;

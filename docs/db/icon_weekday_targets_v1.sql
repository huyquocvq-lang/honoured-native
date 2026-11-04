-- Icon weekday targets v1 (Phase 4 change request, 1 Nov 2026): an Icon may
-- hold a different target on each of its weekdays, set when it is signed, and
-- a running Icon may revise the targets of chosen weekdays together, under one
-- new signature, without changing the activity.
--   * contracts.icon_day_targets: the signed target of each scheduled weekday,
--     {"1": "10000 steps", "2": "7000 steps", ...} (ISO weekdays), written like
--     primary_target in the same unit. primary_target is the first weekday's.
--     Null: the same target every day, as before. Locked after signing like
--     every other Icon term. Not for Word Tracker Icons.
--   * contracts_icon_guard() validates it on the first write and locks it;
--     contracts_icon_days() starts each Icon day on its weekday's target.
--   * revise_icon_targets(): the weekday revision. Each chosen weekday takes
--     its new target from its own next Icon day (today and finished days keep
--     theirs); one icon_revisions row holds every change in `changes`, and its
--     top-level target and effective day are those of the first change.
--     revise_icon_target() (every day, icon_revisions_v1_1.sql) stays for
--     older web bundles.
--   * icon_push_facts(): push-started cards carry the day's targetRevision,
--     so the card shows the signature of the revision its day is held to. A
--     weekday revision is not in force on every day after its effective day,
--     which is what the app falls back to without it.
-- Readers of icon_days (scoring, measuring, push) already use each day's own
-- target, and the app and web read targetRevision and icon_days, so nothing
-- else changes. Expand-compatible: until a client writes icon_day_targets or
-- calls revise_icon_targets() everything reads as before.
-- On top of icon_revisions_v1_1.sql (checked below). Re-running is harmless.
-- Rollback: icon_weekday_targets_v1_rollback.sql.
begin;

do $$
declare
  v_revise text := md5(pg_get_functiondef(to_regprocedure('public.revise_icon_target(uuid, uuid, numeric, text)')));
  v_immutable text := md5(pg_get_functiondef(to_regprocedure('public.icon_revisions_immutable()')));
  v_guard text := md5(pg_get_functiondef(to_regprocedure('public.contracts_icon_guard()')));
  v_days text := md5(pg_get_functiondef(to_regprocedure('public.contracts_icon_days()')));
  v_facts text := md5(pg_get_functiondef(to_regprocedure('public.icon_push_facts(jsonb)')));
begin
  if v_revise is distinct from 'aca7ea9cee15c372aa2f0c9b9787f280'
     or v_immutable is distinct from 'aaa8d362ce4f89601261e219c7864e31' then
    raise exception 'icon_weekday_targets_v1.sql needs icon_revisions_v1_1.sql applied first';
  end if;
  -- Production's bodies (28 Oct 2026), or this file's own.
  if v_guard not in ('05d2aad1b81f327fe38fe69dfcbe2ec6', 'b29e8ef41fc29f0d55c48092acf7c5f3')
     or v_days not in ('bc7b184a1d698d49ca70dfe3dbf5f9dc', 'dbc8968992cb54558dd4f097d16ed221')
     or v_facts not in ('3d396c2e252e2793768c9a73e02a7fdb', 'ec9b2ae4012553c2945e80c6f0de8b58') then
    raise exception 'contracts_icon_guard(), contracts_icon_days() or icon_push_facts() is not the expected version (md5 % / % / %); not overwriting it',
      v_guard, v_days, v_facts;
  end if;
end $$;

alter table public.contracts add column if not exists icon_day_targets jsonb;
comment on column public.contracts.icon_day_targets is
  'Icons with a different target per weekday: ISO weekday ("1" = Monday ... "7" = Sunday) to its signed target, written like primary_target ("<number> <unit>", same unit), one per icon_weekdays; primary_target is the first weekday''s. Null: primary_target every day. Locked after signing.';

alter table public.icon_revisions add column if not exists changes jsonb;
alter table public.icon_revisions drop constraint if exists icon_revisions_changes_array;
alter table public.icon_revisions add constraint icon_revisions_changes_array
  check (changes is null or (jsonb_typeof(changes) = 'array' and jsonb_array_length(changes) > 0));
comment on column public.icon_revisions.changes is
  'Weekday revisions (revise_icon_targets): one entry per revised weekday, by weekday, {weekday, previousTargetText, previousTargetValue, targetText, targetValue, effectiveDay}; the row''s own target and effective_day are the first change''s. Null: a revision of every day from effective_day (revise_icon_target).';
comment on column public.icon_days.target_text is
  'The target this day is held to, as the contract writes it ("<number> <unit>"): the signed target of its weekday (icon_day_targets, else primary_target), or the revision named by target_revision.';

-- Signed terms: icon_day_targets is checked on the first write and locked
-- afterwards. Production's body with only those lines added.
CREATE OR REPLACE FUNCTION public.contracts_icon_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  canonical_unit text;
  final_deadline timestamptz;
  target_unit text;
  target_max numeric;
  target_decimals integer;
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
    new.icon_day_targets := old.icon_day_targets;
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
    new.icon_day_targets := null;
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

  -- Weekday targets: one per Icon weekday, each "<number> <unit>" as the web
  -- writes it (target-units.ts) in primary_target's unit, and the first
  -- weekday's equal to primary_target. The same target every day is none.
  if new.icon_day_targets is not null then
    if new.word_source_id is not null or new.word_target is not null then
      raise exception 'a Word Tracker Icon has one target' using errcode = '22023';
    end if;
    if jsonb_typeof(new.icon_day_targets) <> 'object' then
      raise exception 'icon_day_targets must map ISO weekdays to targets' using errcode = '22023';
    end if;
    target_unit := substring(new.primary_target from '^[0-9]+(?:\.[0-9]+)? ([a-z]+)$');
    select u.max_value, u.decimals into target_max, target_decimals
    from (values ('min', 120, 0), ('hrs', 24, 0), ('km', 50, 1), ('mi', 30, 1),
                 ('steps', 50000, 0), ('kcal', 2000, 0), ('reps', 500, 0))
         as u(unit, max_value, decimals)
    where u.unit = target_unit;
    if not found then
      raise exception 'icon_day_targets needs primary_target written as "<number> <unit>"' using errcode = '22023';
    end if;
    if (select array_agg(k order by k) from jsonb_object_keys(new.icon_day_targets) k)
       is distinct from (select array_agg(d::text order by d) from unnest(new.icon_weekdays) d) then
      raise exception 'icon_day_targets must hold one target for each Icon weekday' using errcode = '22023';
    end if;
    if exists (
      select 1
      from jsonb_each(new.icon_day_targets) e
      cross join lateral (
        select substring(e.value #>> '{}' from '^([0-9]+(?:\.[0-9]+)?) [a-z]+$')::numeric as n
      ) x
      where jsonb_typeof(e.value) <> 'string'
         or x.n is null or x.n <= 0 or x.n > target_max
         or x.n * power(10::numeric, target_decimals) <> trunc(x.n * power(10::numeric, target_decimals))
         or e.value #>> '{}' <> (case when x.n = trunc(x.n) then trunc(x.n)::text
                                      else round(x.n, 1)::text end) || ' ' || target_unit
    ) then
      raise exception 'icon_day_targets must be positive targets in %, written as the web writes them', target_unit
        using errcode = '22023';
    end if;
    if new.icon_day_targets ->> new.icon_weekdays[1]::text <> new.primary_target then
      raise exception 'primary_target must be the first Icon weekday''s target' using errcode = '22023';
    end if;
    if (select count(distinct e.value) from jsonb_each(new.icon_day_targets) e) = 1 then
      new.icon_day_targets := null;
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

-- New Icon days start on their weekday's signed target. Health Icons keep it
-- in the metric's unit in the proportion of primary_target to icon_target.
-- icon_revisions_v1.sql's body with only the targets changed.
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
             coalesce(t.target, new.primary_target),
             case when t.target is null or new.icon_target is null then new.icon_target
                  else (new.icon_target::numeric
                        * substring(t.target from '^([0-9]+(?:\.[0-9]+)?) ')::numeric
                        / substring(new.primary_target from '^([0-9]+(?:\.[0-9]+)?) ')::numeric)::double precision end
      from public.icon_schedule(
        new.icon_start_day, new.icon_end_day, new.icon_weekdays,
        new.icon_deadline_time, new.icon_timezone, new.created_at
      ) s
      cross join lateral (
        select new.icon_day_targets ->> extract(isodow from s.day)::integer::text as target
      ) t
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

-- Push-started cards: the facts carry the revision the card's day is held to
-- (icon_days.target_revision, 0 = the signing), read by the app as
-- IconCardFacts.targetRevision. Production's body plus that one key; it is
-- left out when the day cannot be found, and read through to_jsonb() so the
-- facts still build if the column is ever dropped.
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
  ) || coalesce((
    select jsonb_strip_nulls(jsonb_build_object('targetRevision', to_jsonb(d) -> 'target_revision'))
    from public.icon_days d
    where d.contract_id = case
            when p_job->>'contract_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            then (p_job->>'contract_id')::uuid end
      and d.day = (p_job->>'day')::date
  ), '{}'::jsonb)
  from (select greatest(coalesce((p_job->>'session_number')::integer, 1), 1) as session_number) s,
       public.icon_target_split(p_job->>'target') t
$function$;
revoke all on function public.icon_push_facts from public;
grant execute on function public.icon_push_facts to service_role;

-- Revise the targets of chosen weekdays of a running Icon under one new
-- signature. p_targets maps ISO weekdays to the new number in the unit the
-- target is written in, {"6": 12000, "2": 8000}; a weekday whose target
-- already is that number is left as it is. Each weekday changes from its own
-- next Icon day after today, in the Icon's time zone. p_request_id is the
-- client's id for this revision, so a retry returns the same revision;
-- p_signature_path is the new signature, already uploaded to
-- <uid>/<client_id>/revisions/. Answers { ok: true, revision, effectiveDay,
-- targetText, targetValue, changes, days, duplicate } (effectiveDay and the
-- target are the first change's) or { ok: false, reason }.
create or replace function public.revise_icon_targets(
  p_contract_id uuid,
  p_request_id uuid,
  p_targets jsonb,
  p_signature_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  v_contract public.contracts%rowtype;
  v_done public.icon_revisions%rowtype;
  v_signed_number numeric;
  v_unit text;
  v_max numeric;
  v_decimals integer;
  v_today date;
  v_key text;
  v_weekday integer;
  v_target numeric;
  v_day date;
  v_current_text text;
  v_current_value double precision;
  v_text text;
  v_value double precision;
  v_changes jsonb := '[]'::jsonb;
  v_first jsonb;
  v_change jsonb;
  v_folder text;
  v_revision integer;
  v_count integer;
  v_days integer := 0;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_contract_id is null or p_request_id is null or p_targets is null or p_signature_path is null
     or jsonb_typeof(p_targets) <> 'object' or p_targets = '{}'::jsonb then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  -- Revisions of one Icon queue here, so each sees the one before it.
  select * into v_contract
  from public.contracts c
  where c.id = p_contract_id
    and c.user_id = caller_id
    and c.icon_weekdays is not null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- A retry of a revision that went through gets it back, unchanged.
  select * into v_done
  from public.icon_revisions r
  where r.contract_id = p_contract_id and r.request_id = p_request_id;
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'revision', v_done.revision,
      'effectiveDay', v_done.effective_day, 'targetText', v_done.target_text,
      'targetValue', v_done.target_value, 'changes', v_done.changes, 'days', 0);
  end if;

  if v_contract.status <> 'active' then
    return jsonb_build_object('ok', false, 'reason', 'not_active');
  end if;
  if v_contract.word_source_id is not null then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;

  -- Every weekday's target is written "<number> <unit>" in the signed unit
  -- (target-units.ts); only the number changes, within the unit's rules.
  v_unit := substring(v_contract.primary_target from '^[0-9]+(?:\.[0-9]+)? ([a-z]+)$');
  v_signed_number := substring(v_contract.primary_target from '^([0-9]+(?:\.[0-9]+)?) [a-z]+$')::numeric;
  if v_unit is null or v_signed_number is null or v_signed_number <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;
  select u.max_value, u.decimals into v_max, v_decimals
  from (values ('min', 120, 0), ('hrs', 24, 0), ('km', 50, 1), ('mi', 30, 1),
               ('steps', 50000, 0), ('kcal', 2000, 0), ('reps', 500, 0))
       as u(unit, max_value, decimals)
  where u.unit = v_unit;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;

  -- Today is read now, after the row lock, not at the start of the transaction.
  v_today := (clock_timestamp() at time zone v_contract.icon_timezone)::date;

  for v_key in select k from jsonb_object_keys(p_targets) k order by k loop
    if v_key !~ '^[1-7]$' or not (v_key::integer = any (v_contract.icon_weekdays)) then
      return jsonb_build_object('ok', false, 'reason', 'invalid');
    end if;
    v_weekday := v_key::integer;
    if jsonb_typeof(p_targets -> v_key) <> 'number' then
      return jsonb_build_object('ok', false, 'reason', 'invalid_target');
    end if;
    v_target := (p_targets ->> v_key)::numeric;
    if v_target <= 0 or v_target > v_max
       or v_target * power(10::numeric, v_decimals) <> trunc(v_target * power(10::numeric, v_decimals)) then
      return jsonb_build_object('ok', false, 'reason', 'invalid_target');
    end if;
    v_text := case when v_target = trunc(v_target) then trunc(v_target)::text
                   else round(v_target, 1)::text end || ' ' || v_unit;

    -- The weekday's next Icon day: today's day, closed days and days past
    -- their cut-off keep their target. Its target is the one in force.
    select d.day, coalesce(d.target_text, v_contract.primary_target), coalesce(d.target_value, v_contract.icon_target)
      into v_day, v_current_text, v_current_value
    from public.icon_days d
    where d.contract_id = p_contract_id
      and d.status = 'pending'
      and d.day > v_today
      and extract(isodow from d.day) = v_weekday
    order by d.day
    limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'reason', 'no_future_day');
    end if;
    if v_text = v_current_text then
      continue;
    end if;
    -- Health Icons also carry the target in the metric's unit, in the same
    -- proportion as the signed one (10 km is 10000 meters).
    v_value := case when v_contract.icon_metric is not null
                    then (v_contract.icon_target::numeric * v_target / v_signed_number)::double precision end;
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'weekday', v_weekday,
      'previousTargetText', v_current_text,
      'previousTargetValue', case when v_contract.icon_metric is not null then v_current_value end,
      'targetText', v_text,
      'targetValue', v_value,
      'effectiveDay', v_day));
  end loop;
  if jsonb_array_length(v_changes) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'unchanged');
  end if;

  -- The new signature: a file of its own in this Icon's revisions folder,
  -- uploaded by the caller.
  v_folder := caller_id::text || '/' || v_contract.client_id || '/revisions/';
  if v_contract.client_id !~ '^[A-Za-z0-9_-]{1,128}$'
     or left(p_signature_path, length(v_folder)) <> v_folder
     or substr(p_signature_path, length(v_folder) + 1) !~ '^[A-Za-z0-9_-]{1,128}\.png$'
     or exists (select 1 from public.icon_revisions r where r.signature_path = p_signature_path) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_signature');
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'signatures' and o.name = p_signature_path
      and (o.owner_id = caller_id::text or o.owner = caller_id)
  ) then
    return jsonb_build_object('ok', false, 'reason', 'signature_missing');
  end if;

  select coalesce(max(r.revision), 0) + 1 into v_revision
  from public.icon_revisions r
  where r.contract_id = p_contract_id;

  -- The row's own target and effective day: the first change.
  select c into v_first
  from jsonb_array_elements(v_changes) c
  order by c ->> 'effectiveDay', (c ->> 'weekday')::integer
  limit 1;

  begin
    insert into public.icon_revisions (
      contract_id, user_id, revision, request_id,
      previous_target_text, previous_target_value, target_text, target_value,
      effective_day, signature_path, changes
    ) values (
      p_contract_id, caller_id, v_revision, p_request_id,
      v_first ->> 'previousTargetText', (v_first ->> 'previousTargetValue')::double precision,
      v_first ->> 'targetText', (v_first ->> 'targetValue')::double precision,
      (v_first ->> 'effectiveDay')::date, p_signature_path, v_changes
    );
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'invalid_signature');
  end;

  for v_change in select c from jsonb_array_elements(v_changes) c loop
    update public.icon_days d
    set target_text = v_change ->> 'targetText',
        target_value = (v_change ->> 'targetValue')::double precision,
        target_revision = v_revision
    where d.contract_id = p_contract_id
      and d.status = 'pending'
      and d.day >= (v_change ->> 'effectiveDay')::date
      and extract(isodow from d.day) = (v_change ->> 'weekday')::integer;
    get diagnostics v_count = row_count;
    v_days := v_days + v_count;
  end loop;

  return jsonb_build_object('ok', true, 'duplicate', false, 'revision', v_revision,
    'effectiveDay', v_first ->> 'effectiveDay', 'targetText', v_first ->> 'targetText',
    'targetValue', v_first -> 'targetValue', 'changes', v_changes, 'days', v_days);
end;
$$;

revoke all on function public.revise_icon_targets(uuid, uuid, jsonb, text) from public, anon;
grant execute on function public.revise_icon_targets(uuid, uuid, jsonb, text) to authenticated, service_role;

commit;

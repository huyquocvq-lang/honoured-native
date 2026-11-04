-- Rollback of icon_revisions_v1.sql: production's contracts_icon_days(),
-- icon_days_to_measure(), icon_push_jobs() and record_icon_measurements()
-- (icon_scoring_v4.sql) bodies come back verbatim, revise_icon_target() and
-- icon_revisions go, and so do the per-day target columns.
-- Revisions are lost with it: days revised to another target are scored
-- against the signed target again. When icon_revisions holds any row the
-- rollback refuses, unless the session first runs
--   set honoured.discard_icon_revisions = 'yes';
-- (export the table before that). Re-running is harmless. It also undoes
-- icon_revisions_v1_1.sql, and refuses while icon_weekday_targets_v1.sql is
-- in place: roll that back first.
begin;

do $$
declare
  v_revisions bigint := 0;
begin
  if to_regprocedure('public.revise_icon_targets(uuid, uuid, jsonb, text)') is not null then
    raise exception 'icon_weekday_targets_v1.sql is in place; run icon_weekday_targets_v1_rollback.sql first';
  end if;
  if to_regclass('public.icon_revisions') is not null then
    -- Held to the end: a revision committing meanwhile is counted, not dropped.
    execute 'lock table public.icon_revisions in share row exclusive mode';
    execute 'select count(*) from public.icon_revisions' into v_revisions;
  end if;
  if v_revisions > 0
     and coalesce(current_setting('honoured.discard_icon_revisions', true), '') <> 'yes' then
    raise exception 'icon_revisions holds % revisions; set honoured.discard_icon_revisions = ''yes'' to discard them', v_revisions;
  end if;
end $$;

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
        contract_id, user_id, day, session_number, deadline_at, morning_at, evening_at
      )
      select new.id, new.user_id, s.day, s.session_number, s.deadline_at,
             case when new.icon_morning_time is null then null
                  else (s.day + new.icon_morning_time) at time zone new.icon_timezone end,
             case when new.icon_evening_time is null then null
                  else (s.day + new.icon_evening_time) at time zone new.icon_timezone end
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

CREATE OR REPLACE FUNCTION public.icon_days_to_measure()
 RETURNS TABLE(contract_id uuid, day date, starts_at timestamp with time zone, deadline_at timestamp with time zone, metric text, target double precision, unit text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select d.contract_id,
         d.day,
         d.day::timestamp at time zone c.icon_timezone,
         d.deadline_at,
         c.icon_metric,
         c.icon_target,
         c.icon_unit
  from public.icon_days d
  join public.contracts c on c.id = d.contract_id
  where d.user_id = (select auth.uid())
    and c.icon_metric is not null
    and d.day::timestamp at time zone c.icon_timezone <= now()
    and (
      (d.status = 'pending' and d.deadline_at + interval '24 hours' > now())
      or (d.status in ('honoured', 'broken')
          and d.resolution in ('target_met', 'target_missed', 'no_data')
          and d.deadline_at + interval '30 days' > now())
    )
  order by d.deadline_at, d.contract_id
$function$;

CREATE OR REPLACE FUNCTION public.record_icon_measurements(rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id uuid := (select auth.uid());
  settle constant interval := interval '1 hour';
  item jsonb;
  v_contract uuid;
  v_day date;
  v_value double precision;
  v_through timestamptz;
  v_source text;
  v_deadline timestamptz;
  v_target double precision;
  v_status text;
  v_measured double precision;
  v_measured_source text;
  honoured_count integer := 0;
  broken_count integer := 0;
  pending_count integer := 0;
  updated_count integer := 0;
  unchanged_count integer := 0;
  skipped_count integer := 0;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if rows is null or jsonb_typeof(rows) <> 'array' then
    raise exception 'rows must be a JSON array' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(rows) loop
    begin
      v_contract := (item->>'contractId')::uuid;
      v_day := (item->>'day')::date;
      v_value := (item->>'value')::double precision;
      v_through := (item->>'measuredThrough')::timestamptz;
      v_source := coalesce(item->>'source', 'healthkit');
    exception when others then
      skipped_count := skipped_count + 1;
      continue;
    end;
    if v_contract is null or v_day is null or v_through is null
       or v_value is null or v_value < 0 or v_value >= 'Infinity'::double precision
       or v_source not in ('healthkit', 'healthkit_iphone', 'core_motion') then
      skipped_count := skipped_count + 1;
      continue;
    end if;

    select d.deadline_at, c.icon_target, d.status, d.measured_value, coalesce(d.measured_source, 'healthkit')
      into v_deadline, v_target, v_status, v_measured, v_measured_source
    from public.icon_days d
    join public.contracts c on c.id = d.contract_id
    where d.contract_id = v_contract
      and d.day = v_day
      and d.user_id = caller_id
      and c.icon_metric is not null
      and (
        -- Past the 24-hour window a pending day belongs to expire_icon_days().
        (d.status = 'pending' and d.deadline_at + interval '24 hours' > now())
        or (d.status in ('honoured', 'broken')
            and d.resolution in ('target_met', 'target_missed', 'no_data')
            and d.deadline_at + interval '30 days' > now())
      )
    for update of d;
    if not found then
      skipped_count := skipped_count + 1;
      continue;
    end if;

    -- A reading can never claim to cover time that has not happened yet.
    v_through := least(v_through, now(), v_deadline);

    if v_status <> 'pending' then
      if v_measured is not null and v_value = v_measured then
        -- The same total, perhaps from the other source: only the label moves.
        if v_source <> v_measured_source then
          update public.icon_days
          set measured_source = v_source
          where contract_id = v_contract and day = v_day;
        end if;
        unchanged_count := unchanged_count + 1;
      elsif v_measured is not null and v_value < v_measured and v_source = v_measured_source then
        unchanged_count := unchanged_count + 1;
      elsif v_status = 'broken' and v_value >= v_target then
        update public.icon_days
        set status = 'honoured', resolution = 'target_met',
            measured_value = v_value, measured_source = v_source, scored_at = now()
        where contract_id = v_contract and day = v_day;
        honoured_count := honoured_count + 1;
      else
        -- Higher from the same source, or any total from another source.
        update public.icon_days
        set measured_value = v_value, measured_source = v_source,
            resolution = case when resolution = 'no_data' then 'target_missed' else resolution end
        where contract_id = v_contract and day = v_day;
        updated_count := updated_count + 1;
      end if;
    elsif v_value >= v_target then
      update public.icon_days
      set status = 'honoured', resolution = 'target_met',
          measured_value = v_value, measured_source = v_source, scored_at = now()
      where contract_id = v_contract and day = v_day;
      honoured_count := honoured_count + 1;
    elsif v_through >= v_deadline and now() >= v_deadline + settle then
      update public.icon_days
      set status = 'broken', resolution = 'target_missed',
          measured_value = v_value, measured_source = v_source, scored_at = now()
      where contract_id = v_contract and day = v_day;
      broken_count := broken_count + 1;
    else
      update public.icon_days
      set measured_value = v_value, measured_source = v_source
      where contract_id = v_contract and day = v_day;
      pending_count := pending_count + 1;
    end if;
  end loop;

  -- honoured / broken: days newly stamped by this report (a BROKEN day that
  -- became HONOURED counts as honoured). updated: stamped days whose total
  -- changed, raised or replaced by another source's. unchanged: stamped days
  -- whose total stayed.
  return jsonb_build_object(
    'honoured', honoured_count,
    'broken', broken_count,
    'pending', pending_count,
    'updated', updated_count,
    'unchanged', unchanged_count,
    'skipped', skipped_count
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.icon_push_jobs(p_now timestamp with time zone DEFAULT now(), p_window interval DEFAULT '00:15:00'::interval)
 RETURNS TABLE(job text, user_id uuid, contract_id uuid, client_id text, day date, session_number integer, total_sessions integer, deadline_at timestamp with time zone, evening_at timestamp with time zone, status text, activity text, target text, because text, timezone text, morning_channel text, measured_value double precision, tokens jsonb, installation_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with days as (
    select d.contract_id, d.user_id, d.day, d.session_number, d.deadline_at,
           d.morning_at, d.evening_at, d.status, d.measured_value,
           c.client_id, c.primary_activity, c.primary_target, c.because, c.icon_timezone,
           (select max(x.session_number) from public.icon_days x where x.contract_id = d.contract_id) as total
    from public.icon_days d
    join public.contracts c on c.id = d.contract_id
    where c.status = 'active'
      and d.deadline_at > p_now - p_window
  ),
  jobs as (
    select 'morning'::text as job, null::uuid as installation_id, s.* from days s
      where s.status = 'pending' and s.morning_at <= p_now and s.morning_at > p_now - p_window and s.deadline_at > p_now
    union all
    select 'evening', null, s.* from days s
      where s.status = 'pending' and s.evening_at <= p_now and s.evening_at > p_now - p_window and s.deadline_at > p_now
    union all
    select 'result', null, s.* from days s
      where s.status = 'honoured' and s.deadline_at > p_now
    union all
    select 'end', null, s.* from days s
      where s.deadline_at <= p_now
    union all
    -- A fresh card 20 minutes before iOS ends the running one at 8 hours,
    -- when it would otherwise run out before the cut-off and no evening card
    -- comes first. The card started when its token first arrived or when this
    -- job started it, whichever is later; the slot names that start, so each
    -- card is renewed once.
    select 'renew-' || floor(extract(epoch from c.since))::bigint, c.installation_id, s.*
    from days s
    cross join lateral (
      select x.installation_id, max(x.since) as since
      from (
        select t.installation_id, t.token_since as since
        from public.push_tokens t
        where t.user_id = s.user_id and t.kind = 'activity'
          and t.contract_client_id = s.client_id and t.icon_day = s.day
        union all
        select e.installation_id, e.created_at
        from public.icon_push_sends e
        where e.contract_id = s.contract_id and e.day = s.day and e.installation_id is not null
          and e.channel = 'live_activity_start' and e.outcome = 'sent'
      ) x
      group by x.installation_id
    ) c
    where s.status in ('pending', 'honoured')
      and s.deadline_at > p_now
      and c.since <= p_now - interval '7 hours 40 minutes'
      and c.since + interval '8 hours' < s.deadline_at
      and not (s.status = 'pending' and s.evening_at > p_now and s.evening_at <= c.since + interval '8 hours')
  )
  select j.job, j.user_id, j.contract_id, j.client_id, j.day, j.session_number, j.total,
         j.deadline_at, j.evening_at, j.status, j.primary_activity, j.primary_target, j.because,
         j.icon_timezone,
         (select l.channel from public.icon_push_log l
          where l.contract_id = j.contract_id and l.day = j.day and l.slot = 'morning'),
         j.measured_value,
         coalesce((
           select jsonb_agg(jsonb_build_object(
             'installationId', t.installation_id, 'kind', t.kind, 'token', t.token,
             'environment', t.environment, 'topic', t.topic, 'osVersion', t.os_version,
             'liveActivitiesEnabled', t.live_activities_enabled
           ) order by t.updated_at desc)
           from public.push_tokens t
           where t.user_id = j.user_id
             and (t.kind in ('device', 'push_to_start')
                  or (t.kind = 'activity' and t.contract_client_id = j.client_id and t.icon_day = j.day))
         ), '[]'::jsonb),
         j.installation_id
  from jobs j
  where not exists (
    select 1 from public.icon_push_log l
    where l.contract_id = j.contract_id and l.day = j.day and l.slot = j.job
  )
  order by j.deadline_at, j.contract_id, j.job
$function$;

drop function if exists public.revise_icon_target(uuid, uuid, numeric, text);
drop table if exists public.icon_revisions;
drop function if exists public.icon_revisions_immutable();

alter table public.icon_days drop constraint if exists icon_days_target_value_positive;
alter table public.icon_days drop constraint if exists icon_days_target_revision_nonnegative;
alter table public.icon_days drop column if exists target_revision;
alter table public.icon_days drop column if exists target_value;
alter table public.icon_days drop column if exists target_text;

commit;

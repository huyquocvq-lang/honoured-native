-- Icon target revisions v1 (Phase 4 M2.1-M2.4,
-- docs/phase4/phase4-two-milestone-implementation-plan.vi.md, section 4.3).
-- A running Health or self-reported Icon may change its target number and be
-- signed again. The signed contract never changes (contracts_icon_guard still
-- locks it): each revision is a new, immutable row in icon_revisions with the
-- old and new target, the day it takes effect and its own signature, and the
-- Icon days from that day on carry the new target.
--   * Only the number changes: same activity, metric, unit, schedule and
--     deadline. Word Tracker Icons are not revisable (not in the 30 hours).
--   * A revision takes effect from the next Icon day: today's day, closed days
--     and days past their cut-off keep the target they had.
--   * Increase or decrease, any number of times; no free session is spent.
--   * The UI says "Revised" / "Revision"; status 'amended' still means an Icon
--     ended early, so the table is not called icon_amendments as the plan
--     drafted.
-- What changes:
--   * icon_days.target_text / target_value / target_revision: each day's own
--     target (backfilled from the contract; revision 0 is the signing).
--   * icon_revisions: the history, readable by its owner, written only by
--     revise_icon_target(), never updated, deleted only with its contract or
--     account.
--   * revise_icon_target(): validates, is idempotent per request id and
--     serialises revisions of one Icon on the contract row.
--   * The server readers use the day's target: contracts_icon_days() writes
--     it, icon_days_to_measure(), record_icon_measurements() (v4) and
--     icon_push_jobs() read it, falling back to the contract. Each body is
--     production's with only those lines changed. record_word_reading() keeps
--     reading contracts.word_target: Word Tracker Icons are never revised.
-- Expand-compatible: until a client calls revise_icon_target() every day's
-- target equals its contract's, so current apps and the current web read the
-- same targets as before. On top of icon_scoring_v4.sql (checked below).
-- Re-running is harmless. Rollback: icon_revisions_v1_rollback.sql.
begin;

do $$
begin
  if position('healthkit_iphone' in pg_get_functiondef('public.record_icon_measurements(jsonb)'::regprocedure)) = 0 then
    raise exception 'icon_revisions_v1.sql needs icon_scoring_v4.sql applied first';
  end if;
end $$;

-- M2.2: each Icon day keeps its own target.
alter table public.icon_days add column if not exists target_text text;
alter table public.icon_days add column if not exists target_value double precision;
alter table public.icon_days add column if not exists target_revision integer not null default 0;
alter table public.icon_days drop constraint if exists icon_days_target_value_positive;
alter table public.icon_days add constraint icon_days_target_value_positive
  check (target_value is null or (target_value > 0 and target_value < 'Infinity'::double precision));
alter table public.icon_days drop constraint if exists icon_days_target_revision_nonnegative;
alter table public.icon_days add constraint icon_days_target_revision_nonnegative
  check (target_revision >= 0);

comment on column public.icon_days.target_text is
  'The target this day is held to, as the contract writes it ("<number> <unit>"): the signed primary_target, or the revision named by target_revision.';
comment on column public.icon_days.target_value is
  'Health Icons: target_text in the metric''s canonical unit (icon_target or its revision); null for self-reported and Word Tracker Icons.';
comment on column public.icon_days.target_revision is
  '0: the target signed with the contract; n: icon_revisions.revision n of this contract.';

-- Backfill days still on the signed target. Their updated_at stays: the
-- target did not change for anyone reading them.
alter table public.icon_days disable trigger update_icon_days_updated_at;
update public.icon_days d
set target_text = c.primary_target,
    target_value = c.icon_target
from public.contracts c
where c.id = d.contract_id
  and d.target_revision = 0
  and (d.target_text is distinct from c.primary_target
       or d.target_value is distinct from c.icon_target);
alter table public.icon_days enable trigger update_icon_days_updated_at;

-- New Icon days start on the signed target.
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

-- M2.1: the revision history.
create table if not exists public.icon_revisions (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  revision integer not null,
  request_id uuid not null,
  previous_target_text text not null,
  previous_target_value double precision,
  target_text text not null,
  target_value double precision,
  effective_day date not null,
  signature_path text not null,
  created_at timestamptz not null default now(),
  constraint icon_revisions_revision_positive check (revision >= 1),
  constraint icon_revisions_contract_revision_key unique (contract_id, revision),
  constraint icon_revisions_contract_request_key unique (contract_id, request_id),
  constraint icon_revisions_signature_path_key unique (signature_path),
  constraint icon_revisions_target_changed check (target_text <> previous_target_text),
  constraint icon_revisions_values_together check ((target_value is null) = (previous_target_value is null)),
  constraint icon_revisions_value_positive
    check (target_value is null or (target_value > 0 and target_value < 'Infinity'::double precision)),
  constraint icon_revisions_signature_owned check (split_part(signature_path, '/', 1) = user_id::text)
);
create index if not exists icon_revisions_user_id_idx on public.icon_revisions (user_id);

comment on table public.icon_revisions is
  'Target revisions of running Icons (Phase 4 M2): one immutable row per revision, written only by revise_icon_target(). The contract keeps the signed target; icon_days carry each day''s target.';
comment on column public.icon_revisions.effective_day is
  'The first Icon day held to target_text: the next pending day after the revision''s local day.';
comment on column public.icon_revisions.signature_path is
  'Path in the signatures bucket of the signature given with this revision; never the contract''s own.';

alter table public.icon_revisions enable row level security;
drop policy if exists "Users can view their own Icon revisions" on public.icon_revisions;
create policy "Users can view their own Icon revisions" on public.icon_revisions
  for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.icon_revisions from public, anon, authenticated;
grant select on public.icon_revisions to authenticated;
grant all on public.icon_revisions to service_role;

-- A revision is history: never edited, and removed only together with its
-- contract or account (the cascade runs inside the parent's delete trigger).
create or replace function public.icon_revisions_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    return old;
  end if;
  raise exception 'Icon revisions cannot be changed or deleted' using errcode = '42501';
end;
$$;
revoke all on function public.icon_revisions_immutable() from public, anon, authenticated;

drop trigger if exists icon_revisions_immutable on public.icon_revisions;
create trigger icon_revisions_immutable before update or delete on public.icon_revisions
  for each row execute function public.icon_revisions_immutable();

-- M2.3: revise a running Icon's target from its next Icon day.
-- p_target is the new number in the unit the target is written in (the
-- number the person types); p_request_id is the client's id for this
-- revision, so a retry returns the same revision; p_signature_path is the new
-- signature, already uploaded under the caller's folder. Answers
-- { ok: true, revision, effectiveDay, targetText, targetValue, days,
-- duplicate } or { ok: false, reason }.
create or replace function public.revise_icon_target(
  p_contract_id uuid,
  p_request_id uuid,
  p_target numeric,
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
  v_current_text text;
  v_current_value double precision;
  v_signed_number numeric;
  v_unit text;
  v_max numeric;
  v_decimals integer;
  v_text text;
  v_value double precision;
  v_effective date;
  v_revision integer;
  v_days integer;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_contract_id is null or p_request_id is null or p_target is null or p_signature_path is null then
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
      'targetValue', v_done.target_value, 'days', 0);
  end if;

  if v_contract.status <> 'active' then
    return jsonb_build_object('ok', false, 'reason', 'not_active');
  end if;
  if v_contract.word_source_id is not null then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;

  -- The terms in force: the latest revision, or the signing.
  select r.target_text, r.target_value into v_current_text, v_current_value
  from public.icon_revisions r
  where r.contract_id = p_contract_id
  order by r.revision desc
  limit 1;
  if not found then
    v_current_text := v_contract.primary_target;
    v_current_value := v_contract.icon_target;
  end if;

  -- Targets are written "<number> <unit>" (target-units.ts); only the number
  -- changes, within the unit's rules there.
  v_unit := substring(v_current_text from '^[0-9]+(?:\.[0-9]+)? ([a-z]+)$');
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
  -- NaN and Infinity sort above every number, so the upper bound rejects them.
  if p_target <= 0 or p_target > v_max
     or p_target * power(10::numeric, v_decimals) <> trunc(p_target * power(10::numeric, v_decimals)) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_target');
  end if;
  v_text := case when p_target = trunc(p_target) then trunc(p_target)::text
                 else round(p_target, 1)::text end || ' ' || v_unit;
  if v_text = v_current_text then
    return jsonb_build_object('ok', false, 'reason', 'unchanged');
  end if;
  -- Health Icons also carry the target in the metric's unit, in the same
  -- proportion as the signed one (10 km is 10000 meters).
  if v_contract.icon_metric is not null then
    v_value := (v_contract.icon_target::numeric * p_target / v_signed_number)::double precision;
  end if;

  -- From the next Icon day in the Icon's own time zone: today's day, closed
  -- days and days past their cut-off keep their target.
  select min(d.day) into v_effective
  from public.icon_days d
  where d.contract_id = p_contract_id
    and d.status = 'pending'
    and d.day > (now() at time zone v_contract.icon_timezone)::date;
  if v_effective is null then
    return jsonb_build_object('ok', false, 'reason', 'no_future_day');
  end if;

  -- The new signature: a file of its own in the caller's folder, uploaded.
  if p_signature_path !~ ('^' || caller_id::text || '/[A-Za-z0-9_-]{1,128}(/[A-Za-z0-9_-]{1,128}){0,2}\.png$')
     or p_signature_path is not distinct from v_contract.signature_path
     or exists (select 1 from public.icon_revisions r where r.signature_path = p_signature_path) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_signature');
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'signatures' and o.name = p_signature_path
  ) then
    return jsonb_build_object('ok', false, 'reason', 'signature_missing');
  end if;

  select coalesce(max(r.revision), 0) + 1 into v_revision
  from public.icon_revisions r
  where r.contract_id = p_contract_id;

  insert into public.icon_revisions (
    contract_id, user_id, revision, request_id,
    previous_target_text, previous_target_value, target_text, target_value,
    effective_day, signature_path
  ) values (
    p_contract_id, caller_id, v_revision, p_request_id,
    v_current_text, v_current_value, v_text, v_value,
    v_effective, p_signature_path
  );

  update public.icon_days d
  set target_text = v_text,
      target_value = v_value,
      target_revision = v_revision
  where d.contract_id = p_contract_id
    and d.status = 'pending'
    and d.day >= v_effective;
  get diagnostics v_days = row_count;

  return jsonb_build_object('ok', true, 'duplicate', false, 'revision', v_revision,
    'effectiveDay', v_effective, 'targetText', v_text, 'targetValue', v_value, 'days', v_days);
end;
$$;

revoke all on function public.revise_icon_target(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.revise_icon_target(uuid, uuid, numeric, text) to authenticated, service_role;

-- M2.4: the server readers hold each day to its own target.
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
         coalesce(d.target_value, c.icon_target),
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

    select d.deadline_at, coalesce(d.target_value, c.icon_target), d.status, d.measured_value, coalesce(d.measured_source, 'healthkit')
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
           c.client_id, c.primary_activity, coalesce(d.target_text, c.primary_target) as primary_target,
           c.because, c.icon_timezone,
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

commit;

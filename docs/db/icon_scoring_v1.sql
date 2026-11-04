-- Icon scoring v1 (V1.2 M2-05): HONOURED / BROKEN / pending for each Icon
-- day, on top of icon_v1.sql. Applied externally to Lovable Cloud and mirrored
-- here; no build runs this file.
--
-- A measured Icon is scored from what the iPhone reads in HealthKit for the
-- Icon day up to its cut-off (source-deduplicated, with the person's source
-- preference). The device reports; the server decides:
--   * target met                       -> HONOURED at once, even before the cut-off
--   * cut-off passed, reading covers it,
--     and the settle hour has elapsed  -> BROKEN (target_missed)
--   * still pending 24 h after cut-off -> BROKEN (target_missed if anything was
--                                         read, no_data otherwise)
-- An unmeasured Icon (no icon_metric) is self-reported by the person.
-- A stamped day is final: only pending days are ever written.
begin;

-- 1. What the device should measure now: the caller's pending days of
-- measured Icons that have started and are still inside the 24-hour window.
create or replace function public.icon_days_to_measure()
returns table (
  contract_id uuid,
  day date,
  starts_at timestamptz,
  deadline_at timestamptz,
  metric text,
  target double precision,
  unit text
)
language sql
stable
security invoker
set search_path = ''
as $$
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
    and d.status = 'pending'
    and c.icon_metric is not null
    and d.day::timestamp at time zone c.icon_timezone <= now()
    and d.deadline_at + interval '24 hours' > now()
  order by d.deadline_at, d.contract_id
$$;

-- 2. Device readings. Each row: { contractId, day, value, measuredThrough },
-- where value is the total from the start of the Icon day to measuredThrough
-- (at most the cut-off). Unknown, foreign, stamped or unmeasured days are
-- skipped, never an error, so one stale row cannot fail the batch.
create or replace function public.record_icon_measurements(rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  settle constant interval := interval '1 hour';
  item jsonb;
  v_contract uuid;
  v_day date;
  v_value double precision;
  v_through timestamptz;
  v_deadline timestamptz;
  v_target double precision;
  honoured_count integer := 0;
  broken_count integer := 0;
  pending_count integer := 0;
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
    exception when others then
      skipped_count := skipped_count + 1;
      continue;
    end;
    if v_contract is null or v_day is null or v_through is null
       or v_value is null or v_value < 0 or v_value >= 'Infinity'::double precision then
      skipped_count := skipped_count + 1;
      continue;
    end if;

    select d.deadline_at, c.icon_target
      into v_deadline, v_target
    from public.icon_days d
    join public.contracts c on c.id = d.contract_id
    where d.contract_id = v_contract
      and d.day = v_day
      and d.user_id = caller_id
      and d.status = 'pending'
      and c.icon_metric is not null
      -- Past the 24-hour window the day belongs to expire_icon_days().
      and d.deadline_at + interval '24 hours' > now()
    for update of d;
    if not found then
      skipped_count := skipped_count + 1;
      continue;
    end if;

    -- A reading can never claim to cover time that has not happened yet.
    v_through := least(v_through, now(), v_deadline);

    if v_value >= v_target then
      update public.icon_days
      set status = 'honoured', resolution = 'target_met',
          measured_value = v_value, scored_at = now()
      where contract_id = v_contract and day = v_day;
      honoured_count := honoured_count + 1;
    elsif v_through >= v_deadline and now() >= v_deadline + settle then
      update public.icon_days
      set status = 'broken', resolution = 'target_missed',
          measured_value = v_value, scored_at = now()
      where contract_id = v_contract and day = v_day;
      broken_count := broken_count + 1;
    else
      update public.icon_days
      set measured_value = v_value
      where contract_id = v_contract and day = v_day;
      pending_count := pending_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'honoured', honoured_count,
    'broken', broken_count,
    'pending', pending_count,
    'skipped', skipped_count
  );
end;
$$;

-- 3. Self-report for an Icon Health cannot measure: allowed from the start of
-- the Icon day until 24 hours after its cut-off, once.
create or replace function public.self_report_icon_day(
  p_contract_id uuid,
  p_day date,
  p_honoured boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  v_starts timestamptz;
  v_deadline timestamptz;
  v_status text;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_contract_id is null or p_day is null or p_honoured is null then
    raise exception 'contract, day and result are required' using errcode = '22023';
  end if;

  select d.day::timestamp at time zone c.icon_timezone, d.deadline_at, d.status
    into v_starts, v_deadline, v_status
  from public.icon_days d
  join public.contracts c on c.id = d.contract_id
  where d.contract_id = p_contract_id
    and d.day = p_day
    and d.user_id = caller_id
    and c.icon_metric is null
  for update of d;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if v_status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'already_stamped', 'status', v_status);
  end if;
  if now() < v_starts then
    return jsonb_build_object('ok', false, 'reason', 'not_started');
  end if;
  if now() >= v_deadline + interval '24 hours' then
    return jsonb_build_object('ok', false, 'reason', 'window_closed');
  end if;

  update public.icon_days
  set status = case when p_honoured then 'honoured' else 'broken' end,
      resolution = 'self_reported',
      scored_at = now()
  where contract_id = p_contract_id and day = p_day;

  return jsonb_build_object('ok', true, 'status', case when p_honoured then 'honoured' else 'broken' end);
end;
$$;

-- 4. The 24-hour rule, for days nobody reported.
create or replace function public.expire_icon_days()
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    update public.icon_days d
    set status = 'broken',
        resolution = case when d.measured_value is null then 'no_data' else 'target_missed' end,
        scored_at = now()
    where d.status = 'pending'
      and d.deadline_at + interval '24 hours' <= now()
    returning 1
  )
  select count(*)::integer from expired
$$;

create index if not exists icon_days_pending_deadline_idx
  on public.icon_days (deadline_at) where status = 'pending';

revoke all on function public.icon_days_to_measure() from public, anon;
revoke all on function public.record_icon_measurements(jsonb) from public, anon;
revoke all on function public.self_report_icon_day(uuid, date, boolean) from public, anon;
revoke all on function public.expire_icon_days() from public, anon, authenticated;
grant execute on function public.icon_days_to_measure() to authenticated;
grant execute on function public.record_icon_measurements(jsonb) to authenticated;
grant execute on function public.self_report_icon_day(uuid, date, boolean) to authenticated;

-- Every 15 minutes; re-running this file replaces the job.
select cron.schedule('icon-days-expire', '*/15 * * * *', $cron$select public.expire_icon_days()$cron$);

commit;

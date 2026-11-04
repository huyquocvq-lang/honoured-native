-- Icon scoring v2 (client request, 16 Oct 2026): an Icon day shows the whole
-- day's total, and a total that arrives late can still honour the day. On top
-- of icon_scoring_v1.sql; replaces icon_days_to_measure() and
-- record_icon_measurements() only. Applied to Lovable Cloud on 21 Oct 2026,
-- after the client approved it, and followed at once by icon_scoring_v3.sql,
-- which replaces record_icon_measurements() again. No build runs this file.
-- Rollback: icon_scoring_v2_rollback.sql (roll back v3 first).
--
-- v1 froze a day at its first stamp. HONOURED kept the reading that first met
-- the target (10,183 steps at 10:15), so every later step was missing from
-- History, and a day nobody read inside the 24-hour window kept a stale
-- reading after HealthKit caught up. Now, for a measured Icon:
--   * the device keeps measuring a day stamped from Health readings
--     (HONOURED target_met, BROKEN target_missed or no_data) until 30 days
--     after its cut-off, the same as a pending day before it;
--   * a reading of a stamped day only ever raises measured_value, so another
--     device or a narrower source choice cannot lower a recorded total;
--   * HONOURED stays HONOURED and keeps its scored_at;
--   * BROKEN becomes HONOURED (target_met, scored_at = now()) once a reading
--     meets the target; below the target the higher total is kept, and a
--     no_data day that gets a reading becomes target_missed.
-- Pending days are scored exactly as in v1. Self-reported days (unmeasured
-- Icons), Word Tracker days and amended days are never measured.
-- expire_icon_days() is unchanged.
begin;

-- 1. What the device should measure now: the caller's started days of
-- measured Icons that are pending inside the 24-hour window, or stamped from
-- Health readings inside the 30-day window.
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
    and c.icon_metric is not null
    and d.day::timestamp at time zone c.icon_timezone <= now()
    and (
      (d.status = 'pending' and d.deadline_at + interval '24 hours' > now())
      or (d.status in ('honoured', 'broken')
          and d.resolution in ('target_met', 'target_missed', 'no_data')
          and d.deadline_at + interval '30 days' > now())
    )
  order by d.deadline_at, d.contract_id
$$;

-- 2. Device readings. Each row: { contractId, day, value, measuredThrough },
-- where value is the total from the start of the Icon day to measuredThrough
-- (at most the cut-off). Unknown, foreign, unmeasured or closed days are
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
  v_status text;
  v_measured double precision;
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
    exception when others then
      skipped_count := skipped_count + 1;
      continue;
    end;
    if v_contract is null or v_day is null or v_through is null
       or v_value is null or v_value < 0 or v_value >= 'Infinity'::double precision then
      skipped_count := skipped_count + 1;
      continue;
    end if;

    select d.deadline_at, c.icon_target, d.status, d.measured_value
      into v_deadline, v_target, v_status, v_measured
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
      if v_measured is not null and v_value <= v_measured then
        unchanged_count := unchanged_count + 1;
      elsif v_status = 'broken' and v_value >= v_target then
        update public.icon_days
        set status = 'honoured', resolution = 'target_met',
            measured_value = v_value, scored_at = now()
        where contract_id = v_contract and day = v_day;
        honoured_count := honoured_count + 1;
      else
        update public.icon_days
        set measured_value = v_value,
            resolution = case when resolution = 'no_data' then 'target_missed' else resolution end
        where contract_id = v_contract and day = v_day;
        updated_count := updated_count + 1;
      end if;
    elsif v_value >= v_target then
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

  -- honoured / broken: days newly stamped by this report (a BROKEN day that
  -- became HONOURED counts as honoured). updated: stamped days whose total
  -- went up. unchanged: stamped days the reading did not raise.
  return jsonb_build_object(
    'honoured', honoured_count,
    'broken', broken_count,
    'pending', pending_count,
    'updated', updated_count,
    'unchanged', unchanged_count,
    'skipped', skipped_count
  );
end;
$$;

revoke all on function public.icon_days_to_measure() from public, anon;
revoke all on function public.record_icon_measurements(jsonb) from public, anon;
grant execute on function public.icon_days_to_measure() to authenticated;
grant execute on function public.record_icon_measurements(jsonb) to authenticated;

commit;

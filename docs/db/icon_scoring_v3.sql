-- Icon scoring v3 (Phase 3 M2, docs/phase3/core-motion-plan.vi.md): each
-- Icon reading names its source, so a day measured from the source the person
-- now reads shows that source's whole-day total. On top of
-- icon_scoring_v2.sql, which must be applied first (checked below); adds
-- icon_days.measured_source and replaces record_icon_measurements() only.
-- Applied to Lovable Cloud on 21 Oct 2026, right after v2; the deployed
-- functions match this file and v2 byte for byte (pg_get_functiondef md5).
-- No build runs this file. Rollback: icon_scoring_v3_rollback.sql.
--
-- The device sends `source` with each reading: 'healthkit' (Apple Health,
-- whichever HealthKit source the person picked) or 'core_motion' (the
-- iPhone's own pedometer). A row without one is 'healthkit', which is what
-- every build before v3 read, and so is a stamped day with no
-- measured_source yet. For a day stamped from Health readings:
--   * a reading from the source the day was measured with only ever raises
--     measured_value, as in v2;
--   * a reading from another source replaces measured_value and
--     measured_source even when it is lower, so History shows the chosen
--     source's total and never a mix of two;
--   * HONOURED stays HONOURED and keeps its scored_at, whatever the total;
--   * BROKEN becomes HONOURED (target_met, scored_at = now()) once a reading
--     meets the target, from either source, as in v2;
--   * a no_data day that gets a reading becomes target_missed.
-- Confirmed on 21 Oct 2026: a source switch may turn a BROKEN day HONOURED,
-- and a HONOURED day may then show a total below its target.
-- Pending days are scored as in v1 and v2 and record the source too. Two
-- devices of one account reading different sources replace each other's
-- totals on stamped days; a status still never moves backwards.
-- icon_days_to_measure() and expire_icon_days() are unchanged.
begin;

do $$
begin
  if position('30 days' in pg_get_functiondef('public.icon_days_to_measure()'::regprocedure)) = 0 then
    raise exception 'icon_scoring_v3.sql needs icon_scoring_v2.sql applied first';
  end if;
end $$;

alter table public.icon_days add column if not exists measured_source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'icon_days_measured_source_check' and conrelid = 'public.icon_days'::regclass
  ) then
    alter table public.icon_days add constraint icon_days_measured_source_check
      check (measured_source is null or measured_source in ('healthkit', 'core_motion'));
  end if;
end $$;

comment on column public.icon_days.measured_source is
  'Source of measured_value: healthkit or core_motion (icon_scoring_v3.sql). Null for values recorded before v3, which came from HealthKit.';

-- Device readings. Each row: { contractId, day, value, measuredThrough,
-- source? }, where value is the total from the start of the Icon day to
-- measuredThrough (at most the cut-off). Unknown, foreign, unmeasured or
-- closed days, and an unknown source, are skipped, never an error, so one
-- stale row cannot fail the batch.
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
       or v_source not in ('healthkit', 'core_motion') then
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
$$;

revoke all on function public.record_icon_measurements(jsonb) from public, anon;
grant execute on function public.record_icon_measurements(jsonb) to authenticated;

commit;

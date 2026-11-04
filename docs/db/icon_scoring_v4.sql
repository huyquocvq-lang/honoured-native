-- Icon scoring v4 (Phase 4 M1.7, docs/phase4/phase4-two-milestone-implementation-plan.vi.md):
-- Health & Tracking offers "iPhone", the Apple Health samples this iPhone
-- recorded. Those readings are HealthKit too, so under v3 they shared the
-- `healthkit` label with the combined total: after a switch from Automatic
-- to iPhone a lower iPhone total was ignored and History kept the higher of
-- the two. v4 adds the label `healthkit_iphone`, so a switch in either
-- direction replaces the total of a stamped day exactly as a switch to or
-- from Core Motion does in v3. Every other rule is v3's, unchanged:
--   * a reading from the source the day was measured with only ever raises
--     measured_value;
--   * a reading from another source replaces measured_value and
--     measured_source, lower too;
--   * HONOURED stays HONOURED and keeps its scored_at;
--   * BROKEN becomes HONOURED once a reading meets the target.
-- On top of icon_scoring_v3.sql, which must be applied first (checked
-- below); widens icon_days_measured_source_check and replaces
-- record_icon_measurements() only, whose body differs from v3 in the one
-- line listing the accepted sources. Builds before this one never send
-- `healthkit_iphone`; v3 skips such a row, so deploy v4 before shipping the
-- build that sends it. Re-running is harmless.
-- Rollback: icon_scoring_v4_rollback.sql.
begin;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'icon_days' and column_name = 'measured_source'
  ) or position('core_motion' in pg_get_functiondef('public.record_icon_measurements(jsonb)'::regprocedure)) = 0 then
    raise exception 'icon_scoring_v4.sql needs icon_scoring_v3.sql applied first';
  end if;
end $$;

alter table public.icon_days drop constraint if exists icon_days_measured_source_check;
alter table public.icon_days add constraint icon_days_measured_source_check
  check (measured_source is null or measured_source in ('healthkit', 'healthkit_iphone', 'core_motion'));

comment on column public.icon_days.measured_source is
  'Source of measured_value: healthkit (combined or a picked source), healthkit_iphone (this iPhone''s own samples, v4) or core_motion. Null for values recorded before v3, which came from HealthKit.';

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
$$;

revoke all on function public.record_icon_measurements(jsonb) from public, anon;
grant execute on function public.record_icon_measurements(jsonb) to authenticated;

commit;

-- Rollback of icon_scoring_v2.sql: restores the v1 definitions of
-- icon_days_to_measure() and record_icon_measurements() as deployed on Lovable
-- Cloud before v2 (checked against pg_get_functiondef on 16 Oct 2026). Days
-- v2 raised or turned HONOURED keep their values; from then on only pending
-- days are measured again.
begin;

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

commit;

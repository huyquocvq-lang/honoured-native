-- Icon v1 (V1.2 M2-03): the Icon schedule, per-day results, timezone and
-- reminder times. Applied externally to Lovable Cloud and mirrored here; no
-- build runs this file.
--
-- An Icon is a contract signed with `icon_*` terms. The web app keeps syncing
-- the row through `public.contracts` as before; the triggers below validate
-- the terms when the contract is first written, lock them afterwards, and keep
-- one server-owned `public.icon_days` row per scheduled Icon day.
begin;

-- 1. Icon terms on the contract. All null for an ordinary contract.
alter table public.contracts
  add column if not exists icon_weekdays smallint[],
  add column if not exists icon_start_day date,
  add column if not exists icon_period_count integer,
  add column if not exists icon_period_unit text,
  add column if not exists icon_end_day date,
  add column if not exists icon_deadline_time time,
  add column if not exists icon_timezone text,
  add column if not exists icon_morning_time time,
  add column if not exists icon_evening_time time,
  add column if not exists icon_metric text,
  add column if not exists icon_target double precision,
  add column if not exists icon_unit text;

comment on column public.contracts.icon_weekdays is
  'ISO weekdays of the Icon (1 = Monday ... 7 = Sunday), sorted and distinct. Null for an ordinary contract.';
comment on column public.contracts.icon_start_day is
  'First local day of the Icon period, in icon_timezone.';
comment on column public.contracts.icon_end_day is
  'Exclusive local end of the period: icon_start_day plus the period. Computed by the server.';
comment on column public.contracts.icon_deadline_time is
  'Daily local cut-off on every Icon day.';
comment on column public.contracts.icon_timezone is
  'IANA zone the schedule is computed in, captured at signing.';
comment on column public.contracts.icon_morning_time is
  'Morning reminder, local time; null when off. Editable after signing.';
comment on column public.contracts.icon_evening_time is
  'Evening reminder, local time; null when off. Editable after signing.';
comment on column public.contracts.icon_metric is
  'Canonical Health metric the Icon is verified against; null when the activity cannot be measured.';

-- 2. One row per scheduled Icon day. Written only by the server.
create table if not exists public.icon_days (
  contract_id uuid not null references public.contracts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  session_number integer not null,
  deadline_at timestamptz not null,
  morning_at timestamptz,
  evening_at timestamptz,
  status text not null default 'pending',
  resolution text,
  measured_value double precision,
  scored_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (contract_id, day),
  constraint icon_days_session_number_check check (session_number >= 1),
  constraint icon_days_status_check check (
    status in ('pending', 'honoured', 'broken', 'amended')
  ),
  constraint icon_days_resolution_check check (
    (status = 'pending' and resolution is null and scored_at is null)
    or (status = 'honoured' and resolution in ('target_met', 'self_reported') and scored_at is not null)
    or (status = 'broken' and resolution in ('target_missed', 'no_data', 'self_reported') and scored_at is not null)
    or (status = 'amended' and resolution = 'amended' and scored_at is not null)
  )
);

create index if not exists icon_days_user_day_idx on public.icon_days (user_id, day);

drop trigger if exists update_icon_days_updated_at on public.icon_days;
create trigger update_icon_days_updated_at
  before update on public.icon_days
  for each row execute function public.update_updated_at_column();

alter table public.icon_days enable row level security;

drop policy if exists "Users can view their own Icon days" on public.icon_days;
create policy "Users can view their own Icon days"
  on public.icon_days for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.icon_days from public, anon, authenticated;
grant select on table public.icon_days to authenticated;

-- 3. The scheduled days of a set of terms: every selected weekday from the
-- start day up to the exclusive end, skipping a day whose cut-off had already
-- passed when the contract was signed. Pure; also usable to preview a count.
create or replace function public.icon_schedule(
  p_start_day date,
  p_end_day date,
  p_weekdays smallint[],
  p_deadline_time time,
  p_timezone text,
  p_signed_at timestamptz
)
returns table (day date, session_number integer, deadline_at timestamptz)
language sql
stable
set search_path = ''
as $$
  select s.day,
         (row_number() over (order by s.day))::integer,
         s.deadline_at
  from (
    select gs::date as day,
           (gs::date + p_deadline_time) at time zone p_timezone as deadline_at
    from generate_series(p_start_day::timestamp, (p_end_day - 1)::timestamp, interval '1 day') gs
  ) s
  where extract(isodow from s.day)::smallint = any (p_weekdays)
    and s.deadline_at > p_signed_at
$$;

revoke all on function public.icon_schedule(date, date, smallint[], time, text, timestamptz) from public, anon;
grant execute on function public.icon_schedule(date, date, smallint[], time, text, timestamptz) to authenticated;

-- 4. Validation on first write, lock-in afterwards.
create or replace function public.contracts_icon_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
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
$$;

-- 5. Keep icon_days in step with the contract.
create or replace function public.contracts_icon_days()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.contracts_icon_guard() from public, anon, authenticated;
revoke all on function public.contracts_icon_days() from public, anon, authenticated;

drop trigger if exists contracts_icon_guard on public.contracts;
create trigger contracts_icon_guard
  before insert or update on public.contracts
  for each row execute function public.contracts_icon_guard();

drop trigger if exists contracts_icon_days on public.contracts;
create trigger contracts_icon_days
  after insert or update on public.contracts
  for each row execute function public.contracts_icon_days();

commit;

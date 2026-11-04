-- Icon day exclusivity (V1.2 M2-15). Applied externally to Lovable Cloud and
-- mirrored here; no build runs this file. Needs icon_v1.sql.
--
-- Rules (docs/phase2/M2-15-icon-day-exclusivity.md):
-- 1. Each scheduled day of an active Icon is reserved: the whole calendar day
--    in the Icon's time zone, stamped or not, until the Icon ends. Days an
--    early exit marks AMENDED are released.
-- 2. A contract cannot be signed if the time it covers, from signing to its
--    deadline, touches a reserved day (a legacy Standing contract covers every
--    day from signing).
-- 3. An Icon cannot be signed if any of its days is a reserved day of another
--    active Icon; the whole Icon is refused.
-- 4. An Icon cannot be signed while an active ordinary contract covers any of
--    its days; an active Standing contract covers every day.
--
-- The web app checks before signing; this is the same check when a contract
-- row is first written, so a second device or an old app cannot get around
-- it. A refusal is an exception whose DETAIL the web app matches:
--   icon_day_reserved      "Icon already set for this day. Finish your Icon first."
--   contract_day_reserved  "Contract already set for this day. Finish your contract first."
begin;

-- The days an active Icon holds, as time ranges [starts_at, ends_at).
create or replace function public.icon_reserved_days(p_user_id uuid)
returns table (contract_id uuid, day date, starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, d.day,
         (d.day::timestamp) at time zone c.icon_timezone,
         ((d.day + 1)::timestamp) at time zone c.icon_timezone
  from public.contracts c
  join public.icon_days d on d.contract_id = c.id
  where c.user_id = p_user_id
    and c.status = 'active'
    and c.icon_weekdays is not null
    and d.status <> 'amended'
$$;

-- Runs after contracts_icon_guard (triggers fire in name order), so a new
-- Icon's terms are validated and icon_end_day is set.
create or replace function public.contracts_icon_reserve()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  icon_conflict boolean;
  contract_conflict boolean;
begin
  -- Only a contract being signed: the web upserts every change, so rows that
  -- already exist, and resolved contracts arriving from history, pass.
  if new.status <> 'active' then
    return new;
  end if;
  -- One signing at a time per person, so two devices cannot both pass.
  perform pg_advisory_xact_lock(hashtextextended('contracts_icon_reserve:' || new.user_id::text, 0));
  if exists (
    select 1 from public.contracts c
    where c.user_id = new.user_id and c.client_id = new.client_id
  ) then
    return new;
  end if;

  if new.icon_weekdays is null then
    if exists (
      select 1 from public.icon_reserved_days(new.user_id) r
      where r.ends_at > new.created_at
        and (new.standing or r.starts_at < new.deadline)
    ) then
      raise exception 'Icon already set for this day. Finish your Icon first.'
        using errcode = 'P0001', detail = 'icon_day_reserved';
    end if;
    return new;
  end if;

  with mine as (
    select (s.day::timestamp) at time zone new.icon_timezone as starts_at,
           ((s.day + 1)::timestamp) at time zone new.icon_timezone as ends_at
    from public.icon_schedule(
      new.icon_start_day, new.icon_end_day, new.icon_weekdays,
      new.icon_deadline_time, new.icon_timezone, new.created_at
    ) s
  )
  select
    exists (
      select 1 from mine m
      join public.icon_reserved_days(new.user_id) r
        on r.starts_at < m.ends_at and r.ends_at > m.starts_at
    ),
    exists (
      select 1 from mine m
      join public.contracts o
        on o.user_id = new.user_id
       and o.status = 'active'
       and o.icon_weekdays is null
       and (o.standing or (o.created_at < m.ends_at and o.deadline > m.starts_at))
    )
  into icon_conflict, contract_conflict;

  if icon_conflict then
    raise exception 'Icon already set for this day. Finish your Icon first.'
      using errcode = 'P0001', detail = 'icon_day_reserved';
  end if;
  if contract_conflict then
    raise exception 'Contract already set for this day. Finish your contract first.'
      using errcode = 'P0001', detail = 'contract_day_reserved';
  end if;
  return new;
end;
$$;

revoke all on function public.icon_reserved_days(uuid) from public, anon, authenticated;
revoke all on function public.contracts_icon_reserve() from public, anon, authenticated;

drop trigger if exists contracts_icon_reserve on public.contracts;
create trigger contracts_icon_reserve
  before insert on public.contracts
  for each row execute function public.contracts_icon_reserve();

commit;

-- Icon v1.1 (V1.2 M2-03 fix): a cut-off of 00:00 is the midnight that ends
-- the Icon day, not the midnight that starts it. Applied externally to
-- Lovable Cloud on top of icon_v1.sql; no build runs this file.
--
-- The web app's default deadline is the person's day reset hour, 0 unless
-- they changed it, so most Icons are signed with a 00:00 cut-off. Under
-- icon_v1.sql each such day had a zero-length window from its own midnight
-- to its own midnight: nothing could ever be measured, every day would expire
-- as BROKEN (no_data), and the signing day was skipped.
begin;

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
           (gs::date + p_deadline_time
              + case when p_deadline_time = time '00:00' then interval '1 day' else interval '0' end
           ) at time zone p_timezone as deadline_at
    from generate_series(p_start_day::timestamp, (p_end_day - 1)::timestamp, interval '1 day') gs
  ) s
  where extract(isodow from s.day)::smallint = any (p_weekdays)
    and s.deadline_at > p_signed_at
$$;

-- Rebuild the schedule of active Icons signed under the old rule, but only
-- while none of their days has been stamped or measured, so no result is lost.
-- The lock-in trigger keeps `deadline` fixed on update, so it is paused for
-- this one correction.
create temporary table icon_fix on commit drop as
select c.id
from public.contracts c
where c.icon_weekdays is not null
  and c.status = 'active'
  and c.icon_deadline_time = time '00:00'
  and not exists (
    select 1 from public.icon_days d
    where d.contract_id = c.id
      and (d.status <> 'pending' or d.measured_value is not null)
  );

delete from public.icon_days d using icon_fix f where d.contract_id = f.id;

insert into public.icon_days (contract_id, user_id, day, session_number, deadline_at, morning_at, evening_at)
select c.id, c.user_id, s.day, s.session_number, s.deadline_at,
       case when c.icon_morning_time is null then null
            else (s.day + c.icon_morning_time) at time zone c.icon_timezone end,
       case when c.icon_evening_time is null then null
            else (s.day + c.icon_evening_time) at time zone c.icon_timezone end
from public.contracts c
join icon_fix f on f.id = c.id
cross join lateral public.icon_schedule(
  c.icon_start_day, c.icon_end_day, c.icon_weekdays,
  c.icon_deadline_time, c.icon_timezone, c.created_at
) s;

alter table public.contracts disable trigger contracts_icon_guard;
update public.contracts c
set deadline = (select max(d.deadline_at) from public.icon_days d where d.contract_id = c.id)
from icon_fix f
where c.id = f.id
  and exists (select 1 from public.icon_days d where d.contract_id = c.id);
alter table public.contracts enable trigger contracts_icon_guard;

commit;

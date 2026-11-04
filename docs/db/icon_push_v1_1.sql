-- Icon push v1.1 (V1.2 M2-06 and M2-07), applied after icon_push_v1.sql.
-- Applied externally to Lovable Cloud and mirrored here; no build runs this file.
--
-- 1. Signing out removes an install's tokens without a session. The
--    installation id is a random UUID the app keeps in its Keychain (this
--    device only); presenting it is enough to stop pushes to that install. So
--    sign-out works offline and after the web app has revoked the session: the
--    app retries until the call succeeds.
-- 2. A token belongs to the install that registered it last.
-- 3. icon_push_jobs also returns the contract's time zone (the alert's cut-off
--    time) and the channel the morning slot used.
-- 4. One APNs provider token shared by every run of the icon-push function:
--    APNs refuses a new one more often than every 20 minutes.
begin;

-- 1.
create or replace function public.unregister_push_tokens(p_installation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  if p_installation_id is null then
    raise exception 'installation id is required' using errcode = '22023';
  end if;
  delete from public.push_tokens where installation_id = p_installation_id;
  get diagnostics removed = row_count;
  return jsonb_build_object('ok', true, 'removed', removed);
end;
$$;

revoke all on function public.unregister_push_tokens(uuid) from public;
grant execute on function public.unregister_push_tokens(uuid) to anon, authenticated;

-- 2.
create or replace function public.register_push_token(
  p_installation_id uuid,
  p_kind text,
  p_token text,
  p_environment text,
  p_topic text,
  p_os_version text default null,
  p_live_activities_enabled boolean default null,
  p_contract_client_id text default null,
  p_icon_day date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_installation_id is null then
    raise exception 'installation id is required' using errcode = '22023';
  end if;

  delete from public.push_tokens
  where installation_id = p_installation_id and user_id <> caller_id;
  delete from public.push_tokens
  where token = lower(p_token) and installation_id <> p_installation_id;

  insert into public.push_tokens (
    user_id, installation_id, kind, token, environment, topic,
    contract_client_id, icon_day, os_version, live_activities_enabled
  ) values (
    caller_id, p_installation_id, p_kind, lower(p_token), p_environment, p_topic,
    case when p_kind = 'activity' then p_contract_client_id end,
    case when p_kind = 'activity' then p_icon_day end,
    left(p_os_version, 32), p_live_activities_enabled
  )
  on conflict (installation_id, kind, (coalesce(contract_client_id, '')), (coalesce(icon_day, date '0001-01-01')))
  do update set
    user_id = excluded.user_id,
    token = excluded.token,
    environment = excluded.environment,
    topic = excluded.topic,
    os_version = excluded.os_version,
    live_activities_enabled = excluded.live_activities_enabled;

  -- The Live Activities switch and the OS version describe the install, not
  -- one token: keep every row of this install in step.
  if p_kind in ('device', 'push_to_start') then
    update public.push_tokens
    set os_version = coalesce(left(p_os_version, 32), os_version),
        live_activities_enabled = coalesce(p_live_activities_enabled, live_activities_enabled)
    where installation_id = p_installation_id and kind in ('device', 'push_to_start');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- 3.
drop function if exists public.icon_push_jobs(timestamptz, interval);
create function public.icon_push_jobs(
  p_now timestamptz default now(),
  p_window interval default interval '15 minutes'
)
returns table (
  job text,
  user_id uuid,
  contract_id uuid,
  client_id text,
  day date,
  session_number integer,
  total_sessions integer,
  deadline_at timestamptz,
  evening_at timestamptz,
  status text,
  activity text,
  target text,
  because text,
  timezone text,
  morning_channel text,
  tokens jsonb
)
language sql
stable
set search_path = ''
as $$
  with days as (
    select d.contract_id, d.user_id, d.day, d.session_number, d.deadline_at,
           d.morning_at, d.evening_at, d.status,
           c.client_id, c.primary_activity, c.primary_target, c.because, c.icon_timezone,
           (select max(x.session_number) from public.icon_days x where x.contract_id = d.contract_id) as total
    from public.icon_days d
    join public.contracts c on c.id = d.contract_id
    where c.status = 'active'
      and d.deadline_at > p_now - p_window
  ),
  jobs as (
    select 'morning'::text as job, s.* from days s
      where s.status = 'pending' and s.morning_at <= p_now and s.morning_at > p_now - p_window and s.deadline_at > p_now
    union all
    select 'evening', s.* from days s
      where s.status = 'pending' and s.evening_at <= p_now and s.evening_at > p_now - p_window and s.deadline_at > p_now
    union all
    select 'result', s.* from days s
      where s.status = 'honoured' and s.deadline_at > p_now
    union all
    select 'end', s.* from days s
      where s.deadline_at <= p_now
  )
  select j.job, j.user_id, j.contract_id, j.client_id, j.day, j.session_number, j.total,
         j.deadline_at, j.evening_at, j.status, j.primary_activity, j.primary_target, j.because,
         j.icon_timezone,
         (select l.channel from public.icon_push_log l
          where l.contract_id = j.contract_id and l.day = j.day and l.slot = 'morning'),
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
         ), '[]'::jsonb)
  from jobs j
  where not exists (
    select 1 from public.icon_push_log l
    where l.contract_id = j.contract_id and l.day = j.day and l.slot = j.job
  )
  order by j.deadline_at, j.contract_id, j.job
$$;

revoke all on function public.icon_push_jobs(timestamptz, interval) from public, anon, authenticated;
grant execute on function public.icon_push_jobs(timestamptz, interval) to service_role;

-- 4.
create table if not exists public.apns_provider_tokens (
  key_id text primary key,
  token text not null,
  issued_at timestamptz not null
);
alter table public.apns_provider_tokens enable row level security;
revoke all on table public.apns_provider_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.apns_provider_tokens to service_role;

commit;

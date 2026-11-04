-- Icon push v1 (V1.2 M2-06 and M2-07): APNs tokens and the work list for the
-- `icon-push` Edge Function. Applied externally to Lovable Cloud and
-- mirrored here; no build runs this file.
--
-- M2-06: each app install registers its tokens through register_push_token:
--   device         the APNs device token (standard push fallback)
--   push_to_start  ActivityKit's push-to-start token (iOS 17.2+)
--   activity       the update token of one running Icon card (contract + day)
-- An install belongs to one account at a time; signing out removes its rows.
--
-- M2-07: every minute pg_cron calls the Edge Function, which asks
-- icon_push_jobs() what is due, sends it to APNs with the key in the project's
-- secrets, and records each result in icon_push_log so nothing is sent twice.
begin;

-- 1. Tokens.
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  kind text not null,
  token text not null,
  environment text not null,
  topic text not null,
  contract_client_id text,
  icon_day date,
  os_version text,
  live_activities_enabled boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_tokens_kind_check check (kind in ('device', 'push_to_start', 'activity')),
  constraint push_tokens_token_check check (token ~ '^[0-9a-f]{32,}$' and length(token) <= 512),
  constraint push_tokens_environment_check check (environment in ('sandbox', 'production')),
  constraint push_tokens_topic_check check (topic ~ '^[A-Za-z0-9.-]{3,155}$'),
  constraint push_tokens_activity_check check (
    (kind = 'activity') = (contract_client_id is not null and icon_day is not null)
  )
);

create unique index if not exists push_tokens_slot_idx on public.push_tokens (
  installation_id, kind, coalesce(contract_client_id, ''), coalesce(icon_day, date '0001-01-01')
);
create index if not exists push_tokens_user_kind_idx on public.push_tokens (user_id, kind);

drop trigger if exists update_push_tokens_updated_at on public.push_tokens;
create trigger update_push_tokens_updated_at
  before update on public.push_tokens
  for each row execute function public.update_updated_at_column();

alter table public.push_tokens enable row level security;
drop policy if exists "Users can view their own push tokens" on public.push_tokens;
create policy "Users can view their own push tokens"
  on public.push_tokens for select
  to authenticated
  using ((select auth.uid()) = user_id);
revoke all on table public.push_tokens from public, anon, authenticated;
grant select on table public.push_tokens to authenticated;

-- An install registers or refreshes one token. Taking over an install (a new
-- account signed in on that phone) removes everything the previous account
-- had there.
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

-- Signing out: the install stops receiving anything for this account.
create or replace function public.unregister_push_tokens(p_installation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  delete from public.push_tokens
  where installation_id = p_installation_id and user_id = (select auth.uid());
  get diagnostics removed = row_count;
  return jsonb_build_object('ok', true, 'removed', removed);
end;
$$;

revoke all on function public.register_push_token(uuid, text, text, text, text, text, boolean, text, date) from public, anon;
revoke all on function public.unregister_push_tokens(uuid) from public, anon;
grant execute on function public.register_push_token(uuid, text, text, text, text, text, boolean, text, date) to authenticated;
grant execute on function public.unregister_push_tokens(uuid) to authenticated;

-- 2. What was sent: one row per Icon day and slot, so a slot is never sent twice.
create table if not exists public.icon_push_log (
  contract_id uuid not null references public.contracts(id) on delete cascade,
  day date not null,
  slot text not null,
  channel text not null,
  status text not null,
  apns_status integer,
  apns_reason text,
  recorded_at timestamptz not null default now(),
  primary key (contract_id, day, slot),
  constraint icon_push_log_slot_check check (slot in ('morning', 'evening', 'result', 'end')),
  constraint icon_push_log_channel_check check (
    channel in ('live_activity_start', 'live_activity_update', 'live_activity_end', 'alert', 'none')
  ),
  constraint icon_push_log_status_check check (status in ('sent', 'failed', 'skipped'))
);
alter table public.icon_push_log enable row level security;
revoke all on table public.icon_push_log from public, anon, authenticated;

-- 3. The work list. A reminder is sent only inside its window, so a missed
-- run never sends stale reminders later.
--   morning / evening  the reminder of a pending day
--   result             a day stamped HONOURED before its cut-off (update the card)
--   end                the cut-off has passed (close the card)
create or replace function public.icon_push_jobs(
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
  tokens jsonb
)
language sql
stable
set search_path = ''
as $$
  with days as (
    select d.contract_id, d.user_id, d.day, d.session_number, d.deadline_at,
           d.morning_at, d.evening_at, d.status,
           c.client_id, c.primary_activity, c.primary_target, c.because,
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

create or replace function public.icon_push_record(
  p_contract_id uuid, p_day date, p_slot text, p_channel text, p_status text,
  p_apns_status integer default null, p_apns_reason text default null
)
returns void
language sql
set search_path = ''
as $$
  insert into public.icon_push_log (contract_id, day, slot, channel, status, apns_status, apns_reason)
  values (p_contract_id, p_day, p_slot, p_channel, p_status, p_apns_status, left(p_apns_reason, 120))
  on conflict (contract_id, day, slot) do nothing
$$;

-- APNs said the token is gone (410, BadDeviceToken, Unregistered).
create or replace function public.icon_push_drop_token(p_token text)
returns void
language sql
set search_path = ''
as $$
  delete from public.push_tokens where token = lower(p_token)
$$;

-- Old card tokens and log rows.
create or replace function public.icon_push_cleanup()
returns void
language sql
set search_path = ''
as $$
  delete from public.push_tokens where kind = 'activity' and icon_day < current_date - 3;
  delete from public.icon_push_log where day < current_date - 60;
$$;

-- 4. The shared secret the cron call presents to the Edge Function.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'icon_push_cron_secret') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'icon_push_cron_secret',
      'Presented by the icon-push cron call to the icon-push Edge Function'
    );
  end if;
end $$;

create or replace function public.icon_push_secret_ok(p_secret text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_secret, '') <> '' and exists (
    select 1 from vault.decrypted_secrets
    where name = 'icon_push_cron_secret' and decrypted_secret = p_secret
  )
$$;

revoke all on function public.icon_push_jobs(timestamptz, interval) from public, anon, authenticated;
revoke all on function public.icon_push_record(uuid, date, text, text, text, integer, text) from public, anon, authenticated;
revoke all on function public.icon_push_drop_token(text) from public, anon, authenticated;
revoke all on function public.icon_push_cleanup() from public, anon, authenticated;
revoke all on function public.icon_push_secret_ok(text) from public, anon, authenticated;
grant execute on function public.icon_push_jobs(timestamptz, interval) to service_role;
grant execute on function public.icon_push_record(uuid, date, text, text, text, integer, text) to service_role;
grant execute on function public.icon_push_drop_token(text) to service_role;
grant execute on function public.icon_push_cleanup() to service_role;
grant execute on function public.icon_push_secret_ok(text) to service_role;

commit;

-- After the icon-push Edge Function is deployed (separate step, see
-- docs/phase2/icon-push.md), schedule the call:
--
-- select cron.schedule('icon-push', '* * * * *', $cron$
--   select net.http_post(
--     url := 'https://<project ref>.supabase.co/functions/v1/icon-push',
--     headers := jsonb_build_object(
--       'Content-Type', 'application/json',
--       'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'icon_push_cron_secret')
--     ),
--     body := '{}'::jsonb,
--     timeout_milliseconds := 25000
--   )
-- $cron$);

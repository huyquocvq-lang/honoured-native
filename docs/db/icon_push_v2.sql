-- Icon push v2 (V1.2 M2-07): the database sends the Icon card pushes itself.
-- Applied externally to Lovable Cloud and mirrored here; no build runs this
-- file. Needs icon_push_v1.sql and icon_push_v1_1.sql.
--
-- The Lovable project cannot host a Supabase Edge Function, and APNs only
-- speaks HTTP/2. pg_net does (Oct 4: APNs answered a dummy request over it
-- with 403 InvalidProviderToken). So pg_cron runs icon_push_tick() every
-- minute: it reads the replies to the previous requests, then sends what is
-- due. The one thing Postgres cannot do is sign the ES256 provider token: the
-- web app's /api/internal/apns-token route mints it from the APNS_* secrets
-- and stores it here, with the allowed bundle ids and gateways. The tick asks
-- for a new one when the current one is 40 minutes old (APNs accepts a token
-- for an hour and refuses renewals more often than every 20 minutes).
--
-- icon_push_plan() is the SQL port of docs/phase2/icon-push/plan.ts, which
-- stays the reference: its Deno tests describe the decisions, and the SQL is
-- checked against JSON fixtures generated from it.
begin;

-- 1. State.
alter table public.apns_provider_tokens
  add column if not exists team_id text,
  add column if not exists topics text[] not null default '{}',
  add column if not exists environments text[] not null default '{}',
  add column if not exists rejected_at timestamptz;

create table if not exists public.icon_push_state (
  id boolean primary key default true check (id),
  token_url text,
  token_requested_at timestamptz,
  token_request_id bigint
);
insert into public.icon_push_state (id, token_url)
values (true, 'https://honour-your-word.lovable.app/api/internal/apns-token')
on conflict (id) do nothing;
alter table public.icon_push_state enable row level security;
revoke all on table public.icon_push_state from public, anon, authenticated;

-- One row per APNs request (the pg_net request id) until its slot is logged.
create table if not exists public.icon_push_sends (
  request_id bigint primary key,
  contract_id uuid not null references public.contracts(id) on delete cascade,
  day date not null,
  slot text not null,
  installation_id uuid,
  channel text not null,
  token text not null,
  created_at timestamptz not null default now(),
  outcome text,
  apns_status integer,
  apns_reason text,
  processed boolean not null default false,
  constraint icon_push_sends_outcome_check check (
    outcome in ('sent', 'drop-token', 'new-provider-token', 'retry', 'failed')
  )
);
create index if not exists icon_push_sends_slot_idx on public.icon_push_sends (contract_id, day, slot);
alter table public.icon_push_sends enable row level security;
revoke all on table public.icon_push_sends from public, anon, authenticated;

-- 2. Words and card facts, as the app's IconCopy and IconCardFacts.
create or replace function public.icon_cut(p_text text, p_limit integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when char_length(t) <= p_limit then t
    else btrim(left(t, p_limit - 1), E' \t\n\r') || '…'
  end
  from (select btrim(coalesce(p_text, ''), E' \t\n\r') as t) s
$$;

-- `10000 steps` → `10,000` and `STEPS`; text with no leading number stays whole.
create or replace function public.icon_target_split(p_target text, out value text, out unit text)
language plpgsql
immutable
set search_path = ''
as $$
declare
  t text := btrim(coalesce(p_target, ''), E' \t\n\r');
  num text := substring(t from '^[0-9]+(?:[.,][0-9]+)?');
begin
  if num is null then
    value := t;
    unit := '';
    return;
  end if;
  unit := upper(btrim(substr(t, char_length(num) + 1), E' \t\n\r'));
  if num ~ '[.,]' or num::numeric > 9007199254740991 then
    value := num;
    return;
  end if;
  value := regexp_replace((num::numeric)::text, '([0-9])(?=([0-9]{3})+$)', '\1,', 'g');
end;
$$;

create or replace function public.icon_copy_affirmation(p_session_number integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array[
    'You''ve got this.',
    'You''re closer than you think.',
    'Today is part of the promise.',
    'Keep your word to yourself.',
    'Small steps, kept promises.',
    'Become what you signed.',
    'Prove it again today.'
  ])[((greatest(coalesce(p_session_number, 1), 1) - 1) % 7) + 1]
$$;

-- `Due 11:59 pm`, or `Due midnight` for a cut-off at 00:00, in the Icon's time zone.
create or replace function public.icon_copy_deadline(p_deadline timestamptz, p_timezone text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  local_time timestamp;
begin
  begin
    local_time := p_deadline at time zone coalesce(nullif(p_timezone, ''), 'UTC');
  exception when others then
    return '';
  end;
  if extract(hour from local_time) = 0 and extract(minute from local_time) = 0 then
    return 'Due midnight';
  end if;
  return 'Due ' || to_char(local_time, 'FMHH12:MI') || ' ' || to_char(local_time, 'am');
end;
$$;

create or replace function public.icon_push_facts(p_job jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'contractId', p_job->>'client_id',
    'iconDay', p_job->>'day',
    'weekday', upper(to_char((p_job->>'day')::date, 'Dy')),
    'sessionNumber', s.session_number,
    'totalSessions', greatest(s.session_number, coalesce((p_job->>'total_sessions')::integer, s.session_number)),
    'targetValue', public.icon_cut(t.value, 16),
    'targetUnit', upper(public.icon_cut(t.unit, 16)),
    'activityName', public.icon_cut(p_job->>'activity', 40),
    'because', public.icon_cut(p_job->>'because', 120),
    'deadline', floor(extract(epoch from (p_job->>'deadline_at')::timestamptz))::bigint
  )
  from (select greatest(coalesce((p_job->>'session_number')::integer, 1), 1) as session_number) s,
       public.icon_target_split(p_job->>'target') t
$$;

-- 3. What each install gets for one job (icon_push_jobs row as JSON):
--   morning  push-to-start the card; without Live Activities, a quiet alert
--   evening  turn the card to the evening line; with no card yet, start one
--            (a card the morning started turns by itself at its stale date)
--   result   show HONOURED on the card
--   end      close the card at the cut-off
create or replace function public.icon_push_plan(
  p_job jsonb,
  p_now bigint,
  p_topics text[],
  p_environments text[]
)
returns table (
  installation_id text,
  channel text,
  token text,
  environment text,
  headers jsonb,
  payload jsonb
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_slot text := p_job->>'job';
  v_deadline bigint := floor(extract(epoch from (p_job->>'deadline_at')::timestamptz))::bigint;
  v_evening_at bigint := floor(extract(epoch from (p_job->>'evening_at')::timestamptz))::bigint;
  v_affirmation text := public.icon_copy_affirmation((p_job->>'session_number')::integer);
  v_morning jsonb := jsonb_build_object('phase', 'morning', 'line', v_affirmation, 'updatedAt', p_now);
  v_evening jsonb := jsonb_build_object('phase', 'evening', 'line', 'Finish what you signed.', 'updatedAt', p_now);
  v_honoured jsonb := jsonb_build_object('phase', 'result', 'line', 'HONOURED', 'result', 'honoured', 'updatedAt', p_now);
  v_target record := public.icon_target_split(p_job->>'target');
  v_install record;
  v_card jsonb;
  v_push_to_start jsonb;
  v_state jsonb;
  v_aps jsonb;
  v_line text;
begin
  for v_install in
    with t as (
      select e.value as tok, e.ordinality as n
      from jsonb_array_elements(coalesce(p_job->'tokens', '[]'::jsonb)) with ordinality as e(value, ordinality)
    )
    select t.tok->>'installationId' as id,
           min(t.n) as first_seen,
           coalesce(bool_or(t.tok->>'kind' <> 'activity' and t.tok->'liveActivitiesEnabled' = 'false'::jsonb), false) as live_activities_off,
           (array_agg(t.tok order by t.n) filter (where t.tok->>'kind' = 'device'
              and t.tok->>'topic' = any(p_topics) and t.tok->>'environment' = any(p_environments)))[1] as device,
           (array_agg(t.tok order by t.n) filter (where t.tok->>'kind' = 'push_to_start'
              and t.tok->>'topic' = any(p_topics) and t.tok->>'environment' = any(p_environments)))[1] as push_to_start,
           (array_agg(t.tok order by t.n) filter (where t.tok->>'kind' = 'activity'
              and t.tok->>'topic' = any(p_topics) and t.tok->>'environment' = any(p_environments)))[1] as card
    from t
    group by 1
    order by 2
  loop
    v_card := case when v_install.live_activities_off then null else v_install.card end;
    v_push_to_start := case when v_install.live_activities_off then null else v_install.push_to_start end;
    v_state := null;
    v_line := null;

    if v_slot = 'morning' then
      if v_card is not null then
        continue; -- the app already opened today's card
      elsif v_push_to_start is not null then
        v_aps := jsonb_build_object(
          'timestamp', p_now, 'event', 'start', 'content-state', v_morning,
          'attributes-type', 'IconActivityAttributes', 'attributes', jsonb_build_object('facts', public.icon_push_facts(p_job)),
          'alert', jsonb_build_object('title', 'Icon', 'body', v_affirmation),
          'input-push-token', 1);
        if v_evening_at > p_now then
          v_aps := v_aps || jsonb_build_object('stale-date', v_evening_at);
        end if;
        installation_id := v_install.id; channel := 'live_activity_start';
        token := v_push_to_start->>'token'; environment := v_push_to_start->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_push_to_start->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', v_deadline::text);
        payload := jsonb_build_object('aps', v_aps);
        return next;
      elsif v_install.device is not null then
        v_line := v_affirmation;
      end if;
    elsif v_slot = 'evening' then
      if v_card is not null then
        installation_id := v_install.id; channel := 'live_activity_update';
        token := v_card->>'token'; environment := v_card->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_card->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', v_deadline::text);
        payload := jsonb_build_object('aps', jsonb_build_object(
          'timestamp', p_now, 'event', 'update', 'content-state', v_evening,
          'alert', jsonb_build_object('title', 'Icon', 'body', 'Finish what you signed.')));
        return next;
      elsif v_push_to_start is not null and p_job->>'morning_channel' = 'live_activity_start' then
        null; -- the morning card shows the evening line from its stale date
      elsif v_push_to_start is not null then
        installation_id := v_install.id; channel := 'live_activity_start';
        token := v_push_to_start->>'token'; environment := v_push_to_start->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_push_to_start->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', v_deadline::text);
        payload := jsonb_build_object('aps', jsonb_build_object(
          'timestamp', p_now, 'event', 'start', 'content-state', v_evening,
          'attributes-type', 'IconActivityAttributes', 'attributes', jsonb_build_object('facts', public.icon_push_facts(p_job)),
          'alert', jsonb_build_object('title', 'Icon', 'body', 'Finish what you signed.'),
          'input-push-token', 1));
        return next;
      elsif v_install.device is not null then
        v_line := 'Finish what you signed.';
      end if;
    elsif v_slot = 'result' then
      if v_card is not null then
        installation_id := v_install.id; channel := 'live_activity_update';
        token := v_card->>'token'; environment := v_card->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_card->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', v_deadline::text);
        payload := jsonb_build_object('aps', jsonb_build_object(
          'timestamp', p_now, 'event', 'update', 'content-state', v_honoured));
        return next;
      end if;
    elsif v_slot = 'end' then
      if v_card is not null then
        installation_id := v_install.id; channel := 'live_activity_end';
        token := v_card->>'token'; environment := v_card->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_card->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', (v_deadline + 4 * 3600)::text);
        payload := jsonb_build_object('aps', jsonb_build_object(
          'timestamp', p_now, 'event', 'end',
          'content-state', case when p_job->>'status' = 'honoured' then v_honoured else v_evening end,
          'dismissal-date', p_now));
        return next;
      end if;
    end if;

    -- The fallback without Live Activities: a quiet notification.
    if v_line is not null then
      installation_id := v_install.id; channel := 'alert';
      token := v_install.device->>'token'; environment := v_install.device->>'environment';
      headers := jsonb_build_object('apns-push-type', 'alert', 'apns-topic', v_install.device->>'topic',
        'apns-priority', '10', 'apns-expiration', v_deadline::text);
      payload := jsonb_build_object(
        'aps', jsonb_build_object(
          'alert', jsonb_build_object(
            'title', 'Icon',
            'subtitle', concat_ws(' · ',
              nullif(public.icon_cut(p_job->>'activity', 40), ''),
              nullif(concat_ws(' ', nullif(v_target.value, ''), nullif(lower(v_target.unit), '')), '')),
            'body', concat_ws(' ', v_line,
              nullif(public.icon_copy_deadline(to_timestamp(v_deadline), p_job->>'timezone'), '') || '.')),
          'thread-id', 'icon-' || (p_job->>'client_id')),
        'honoured', jsonb_build_object('kind', 'icon', 'contractId', p_job->>'client_id', 'iconDay', p_job->>'day'));
      return next;
    end if;
  end loop;
end;
$$;

-- 4. Replies.
create or replace function public.icon_push_reason(p_content text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  return left(p_content::jsonb ->> 'reason', 120);
exception when others then
  return null;
end;
$$;

-- What an APNs answer means for the slot and the token.
create or replace function public.icon_push_classify(p_status integer, p_reason text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_status = 200 then 'sent'
    when p_status = 410 or p_reason in ('BadDeviceToken', 'Unregistered') then 'drop-token'
    when p_reason in ('ExpiredProviderToken', 'InvalidProviderToken', 'MissingProviderToken') then 'new-provider-token'
    when p_status is null or p_status = 0 or p_status = 429 or p_status >= 500 then 'retry'
    else 'failed'
  end
$$;

-- Reads the replies, then logs each slot once every request of it has one:
-- sent if any install got it, failed for answers a retry cannot change, and
-- nothing (so the next tick sends again) while one may still succeed.
create or replace function public.icon_push_collect(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group record;
  v_sent integer := 0;
  v_failed integer := 0;
  v_again integer := 0;
begin
  update public.icon_push_sends s
  set outcome = public.icon_push_classify(r.status_code, public.icon_push_reason(r.content)),
      apns_status = r.status_code,
      apns_reason = coalesce(public.icon_push_reason(r.content), left(r.error_msg, 120),
                             case when r.timed_out then 'timeout' end)
  from net._http_response r
  where r.id = s.request_id and s.outcome is null;

  -- pg_net keeps replies for six hours; a request without one is sent again.
  update public.icon_push_sends
  set outcome = 'retry', apns_reason = 'no reply'
  where outcome is null and created_at < p_now - interval '10 minutes';

  delete from public.push_tokens t
  using public.icon_push_sends s
  where s.outcome = 'drop-token' and not s.processed and t.token = s.token;

  update public.apns_provider_tokens
  set rejected_at = p_now
  where rejected_at is null
    and exists (select 1 from public.icon_push_sends s where s.outcome = 'new-provider-token' and not s.processed);

  for v_group in
    select s.contract_id, s.day, s.slot,
           array_agg(s.outcome) as outcomes,
           array_agg(s.channel) filter (where s.outcome = 'sent') as sent_channels,
           (array_agg(s.channel order by s.request_id))[1] as first_channel,
           (array_agg(s.apns_status order by s.request_id))[1] as first_status,
           (array_agg(s.apns_reason order by s.request_id))[1] as first_reason
    from public.icon_push_sends s
    where not s.processed
    group by s.contract_id, s.day, s.slot
    having bool_and(s.outcome is not null)
  loop
    if 'sent' = any(v_group.outcomes) then
      perform public.icon_push_record(
        v_group.contract_id, v_group.day, v_group.slot,
        (select c.channel
         from unnest(array['live_activity_start', 'live_activity_update', 'live_activity_end', 'alert'])
              with ordinality as c(channel, rank)
         where c.channel = any(v_group.sent_channels)
         order by c.rank limit 1),
        'sent', 200, null);
      v_sent := v_sent + 1;
    elsif exists (select 1 from unnest(v_group.outcomes) o where o <> 'failed') then
      v_again := v_again + 1;
    else
      perform public.icon_push_record(
        v_group.contract_id, v_group.day, v_group.slot,
        v_group.first_channel, 'failed', v_group.first_status, v_group.first_reason);
      v_failed := v_failed + 1;
    end if;
    update public.icon_push_sends
    set processed = true
    where contract_id = v_group.contract_id and day = v_group.day and slot = v_group.slot and not processed;
  end loop;

  delete from public.icon_push_sends where processed and created_at < p_now - interval '2 days';
  return jsonb_build_object('logged_sent', v_sent, 'logged_failed', v_failed, 'again', v_again);
end;
$$;

-- 5. Provider token: asks the web app for a new one, at most every 5 minutes.
create or replace function public.icon_push_request_token(p_now timestamptz default now())
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.icon_push_state%rowtype;
  v_request bigint;
begin
  select * into v_state from public.icon_push_state where id;
  if v_state.token_url is null
     or (v_state.token_requested_at is not null and v_state.token_requested_at > p_now - interval '5 minutes') then
    return null;
  end if;
  v_request := net.http_post(
    url := v_state.token_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'icon_push_cron_secret')),
    timeout_milliseconds := 20000);
  update public.icon_push_state set token_requested_at = p_now, token_request_id = v_request where id;
  return v_request;
end;
$$;

-- 6. Every minute.
create or replace function public.icon_push_tick(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_token public.apns_provider_tokens%rowtype;
  v_now bigint := floor(extract(epoch from p_now))::bigint;
  v_job record;
  v_send record;
  v_request bigint;
  v_planned integer;
  v_jobs integer := 0;
  v_requests integer := 0;
  v_skipped integer := 0;
begin
  v_result := public.icon_push_collect(p_now);

  select * into v_token from public.apns_provider_tokens order by issued_at desc limit 1;
  if v_token.key_id is null
     or v_token.issued_at < p_now - interval '40 minutes'
     or (v_token.rejected_at is not null and v_token.issued_at < p_now - interval '20 minutes') then
    perform public.icon_push_request_token(p_now);
  end if;
  if v_token.key_id is null or v_token.rejected_at is not null
     or v_token.issued_at < p_now - interval '55 minutes' or v_token.issued_at > p_now + interval '5 minutes' then
    return v_result || jsonb_build_object('waiting', 'provider token');
  end if;

  for v_job in
    select to_jsonb(j) as job, j.contract_id, j.day, j.job as slot
    from public.icon_push_jobs(p_now) j
    where not exists (
      select 1 from public.icon_push_sends s
      where s.contract_id = j.contract_id and s.day = j.day and s.slot = j.job and s.outcome is null
    )
    limit 200
  loop
    v_jobs := v_jobs + 1;
    v_planned := 0;
    for v_send in select * from public.icon_push_plan(v_job.job, v_now, v_token.topics, v_token.environments) loop
      v_request := net.http_post(
        url := case when v_send.environment = 'production'
                    then 'https://api.push.apple.com' else 'https://api.sandbox.push.apple.com' end
               || '/3/device/' || v_send.token,
        body := v_send.payload,
        headers := v_send.headers || jsonb_build_object(
          'authorization', 'bearer ' || v_token.token, 'Content-Type', 'application/json'),
        timeout_milliseconds := 10000);
      insert into public.icon_push_sends (request_id, contract_id, day, slot, installation_id, channel, token)
      values (v_request, v_job.contract_id, v_job.day, v_job.slot, v_send.installation_id::uuid, v_send.channel, v_send.token);
      v_planned := v_planned + 1;
    end loop;
    if v_planned = 0 then
      perform public.icon_push_record(v_job.contract_id, v_job.day, v_job.slot, 'none', 'skipped');
      v_skipped := v_skipped + 1;
    end if;
    v_requests := v_requests + v_planned;
  end loop;

  if extract(minute from p_now) = 0 then
    perform public.icon_push_cleanup();
  end if;
  return v_result || jsonb_build_object('jobs', v_jobs, 'requests', v_requests, 'skipped', v_skipped);
end;
$$;

-- 7. Sends to a made-up device token on both gateways; read the replies by id
-- in net._http_response. 400 BadDeviceToken means the key, team and topic
-- work; 403 InvalidProviderToken means they do not.
create or replace function public.icon_push_selftest()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token public.apns_provider_tokens%rowtype;
  v_requests jsonb := '{}'::jsonb;
  v_host text;
begin
  select * into v_token from public.apns_provider_tokens order by issued_at desc limit 1;
  if v_token.key_id is null then
    return jsonb_build_object('ok', false, 'error', 'no provider token yet');
  end if;
  foreach v_host in array array['sandbox', 'production'] loop
    v_requests := v_requests || jsonb_build_object(v_host, net.http_post(
      url := case when v_host = 'production' then 'https://api.push.apple.com' else 'https://api.sandbox.push.apple.com' end
             || '/3/device/' || repeat('0', 64),
      body := '{"aps": {"alert": {"title": "Honoured", "body": "Self-test"}}}'::jsonb,
      headers := jsonb_build_object(
        'authorization', 'bearer ' || v_token.token, 'apns-push-type', 'alert',
        'apns-topic', coalesce(v_token.topics[1], 'missing'), 'apns-priority', '5',
        'Content-Type', 'application/json'),
      timeout_milliseconds := 10000));
  end loop;
  return jsonb_build_object('ok', true, 'issued_at', v_token.issued_at, 'topics', v_token.topics,
    'environments', v_token.environments, 'requests', v_requests);
end;
$$;

-- Nothing here is for clients.
revoke all on function public.icon_cut(text, integer) from public, anon, authenticated;
revoke all on function public.icon_target_split(text) from public, anon, authenticated;
revoke all on function public.icon_copy_affirmation(integer) from public, anon, authenticated;
revoke all on function public.icon_copy_deadline(timestamptz, text) from public, anon, authenticated;
revoke all on function public.icon_push_facts(jsonb) from public, anon, authenticated;
revoke all on function public.icon_push_plan(jsonb, bigint, text[], text[]) from public, anon, authenticated;
revoke all on function public.icon_push_reason(text) from public, anon, authenticated;
revoke all on function public.icon_push_classify(integer, text) from public, anon, authenticated;
revoke all on function public.icon_push_collect(timestamptz) from public, anon, authenticated;
revoke all on function public.icon_push_request_token(timestamptz) from public, anon, authenticated;
revoke all on function public.icon_push_tick(timestamptz) from public, anon, authenticated;
revoke all on function public.icon_push_selftest() from public, anon, authenticated;
grant execute on function public.icon_push_tick(timestamptz) to service_role;
grant execute on function public.icon_push_selftest() to service_role;

commit;

-- Once the web app serves /api/internal/apns-token (published), run
-- icon_push_request_token(), wait a few seconds, run icon_push_selftest() and
-- read its replies, then schedule the tick:
--
-- select cron.schedule('icon-push', '* * * * *', 'select public.icon_push_tick()');

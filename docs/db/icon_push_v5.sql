-- Icon push v5 (Oct 6, 2026): the Icon card stays in the Dynamic Island until
-- the cut-off. iOS ends a Live Activity 8 hours after it starts ("A Live
-- Activity can be active for up to eight hours", ActivityKit), so a 05:00
-- card left the island at 13:00 and nothing replaced it before a midnight
-- cut-off (client, Oct 6). The app swaps an old card for a fresh one whenever
-- it is open (no alert); this job push-starts a fresh card for any install
-- whose card is 7 hours 40 minutes old and would run out before the cut-off.
-- Apple requires an alert to start a card by push, so a renewal lights the
-- phone briefly, silently, with the card's line.
-- On top of icon_push_v4.sql. Applied externally to Lovable Cloud and mirrored
-- here; the plan stays a byte-for-byte port of docs/phase2/icon-push/plan.ts.
begin;

-- 1. When the running card started: its update token arrives with it, so the
-- token's first registration dates the card. Re-registering the same token
-- keeps the date.
alter table public.push_tokens add column if not exists token_since timestamptz;
-- Existing rows date from their last change; the backfill must not bump
-- updated_at, which orders the tokens.
alter table public.push_tokens disable trigger update_push_tokens_updated_at;
update public.push_tokens set token_since = updated_at where token_since is null;
alter table public.push_tokens enable trigger update_push_tokens_updated_at;
alter table public.push_tokens alter column token_since set default now();
alter table public.push_tokens alter column token_since set not null;

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

  insert into public.push_tokens as t (
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
    live_activities_enabled = excluded.live_activities_enabled,
    token_since = case when t.token is distinct from excluded.token then now() else t.token_since end;

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

-- 2. Renewal slots are logged once each, like the others.
alter table public.icon_push_log drop constraint if exists icon_push_log_slot_check;
alter table public.icon_push_log add constraint icon_push_log_slot_check
  check (slot in ('morning', 'evening', 'result', 'end') or slot ~ '^renew-[0-9]{1,12}$');

-- 3. Jobs: the renewals, each for one install.
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
  measured_value double precision,
  tokens jsonb,
  installation_id uuid
)
language sql
stable
set search_path = ''
as $$
  with days as (
    select d.contract_id, d.user_id, d.day, d.session_number, d.deadline_at,
           d.morning_at, d.evening_at, d.status, d.measured_value,
           c.client_id, c.primary_activity, c.primary_target, c.because, c.icon_timezone,
           (select max(x.session_number) from public.icon_days x where x.contract_id = d.contract_id) as total
    from public.icon_days d
    join public.contracts c on c.id = d.contract_id
    where c.status = 'active'
      and d.deadline_at > p_now - p_window
  ),
  jobs as (
    select 'morning'::text as job, null::uuid as installation_id, s.* from days s
      where s.status = 'pending' and s.morning_at <= p_now and s.morning_at > p_now - p_window and s.deadline_at > p_now
    union all
    select 'evening', null, s.* from days s
      where s.status = 'pending' and s.evening_at <= p_now and s.evening_at > p_now - p_window and s.deadline_at > p_now
    union all
    select 'result', null, s.* from days s
      where s.status = 'honoured' and s.deadline_at > p_now
    union all
    select 'end', null, s.* from days s
      where s.deadline_at <= p_now
    union all
    -- A fresh card 20 minutes before iOS ends the running one at 8 hours,
    -- when it would otherwise run out before the cut-off and no evening card
    -- comes first. The card started when its token first arrived or when this
    -- job started it, whichever is later; the slot names that start, so each
    -- card is renewed once.
    select 'renew-' || floor(extract(epoch from c.since))::bigint, c.installation_id, s.*
    from days s
    cross join lateral (
      select x.installation_id, max(x.since) as since
      from (
        select t.installation_id, t.token_since as since
        from public.push_tokens t
        where t.user_id = s.user_id and t.kind = 'activity'
          and t.contract_client_id = s.client_id and t.icon_day = s.day
        union all
        select e.installation_id, e.created_at
        from public.icon_push_sends e
        where e.contract_id = s.contract_id and e.day = s.day and e.installation_id is not null
          and e.channel = 'live_activity_start' and e.outcome = 'sent'
      ) x
      group by x.installation_id
    ) c
    where s.status in ('pending', 'honoured')
      and s.deadline_at > p_now
      and c.since <= p_now - interval '7 hours 40 minutes'
      and c.since + interval '8 hours' < s.deadline_at
      and not (s.status = 'pending' and s.evening_at > p_now and s.evening_at <= c.since + interval '8 hours')
  )
  select j.job, j.user_id, j.contract_id, j.client_id, j.day, j.session_number, j.total,
         j.deadline_at, j.evening_at, j.status, j.primary_activity, j.primary_target, j.because,
         j.icon_timezone,
         (select l.channel from public.icon_push_log l
          where l.contract_id = j.contract_id and l.day = j.day and l.slot = 'morning'),
         j.measured_value,
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
         ), '[]'::jsonb),
         j.installation_id
  from jobs j
  where not exists (
    select 1 from public.icon_push_log l
    where l.contract_id = j.contract_id and l.day = j.day and l.slot = j.job
  )
  order by j.deadline_at, j.contract_id, j.job
$$;

revoke all on function public.icon_push_jobs(timestamptz, interval) from public, anon, authenticated;
grant execute on function public.icon_push_jobs(timestamptz, interval) to service_role;

-- 4. The plan: a renewal starts a fresh card.
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
  payload jsonb,
  auxiliary boolean
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
  -- The day's last reported Health total rides along for the Dynamic Island.
  v_value jsonb := case when jsonb_typeof(p_job->'measured_value') = 'number'
                        then jsonb_build_object('value', p_job->'measured_value') else '{}'::jsonb end;
  v_morning jsonb := jsonb_build_object('phase', 'morning', 'line', v_affirmation, 'updatedAt', p_now) || v_value;
  v_evening jsonb := jsonb_build_object('phase', 'evening', 'line', 'Finish what you signed.', 'updatedAt', p_now) || v_value;
  v_honoured jsonb := jsonb_build_object('phase', 'result', 'line', 'HONOURED', 'result', 'honoured', 'updatedAt', p_now) || v_value;
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
    auxiliary := false;

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
      -- A fresh card, closing the morning one: iOS ends a Live Activity 8
      -- hours after it starts, so the morning card cannot be trusted to reach
      -- the cut-off. The close is housekeeping and never decides the slot.
      if v_push_to_start is not null then
        if v_card is not null then
          installation_id := v_install.id; channel := 'live_activity_end'; auxiliary := true;
          token := v_card->>'token'; environment := v_card->>'environment';
          headers := jsonb_build_object('apns-push-type', 'liveactivity',
            'apns-topic', (v_card->>'topic') || '.push-type.liveactivity',
            'apns-priority', '10', 'apns-expiration', (v_deadline + 4 * 3600)::text);
          payload := jsonb_build_object('aps', jsonb_build_object(
            'timestamp', p_now, 'event', 'end', 'content-state', v_evening, 'dismissal-date', p_now));
          return next;
          auxiliary := false;
        end if;
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
      elsif v_card is not null then
        installation_id := v_install.id; channel := 'live_activity_update';
        token := v_card->>'token'; environment := v_card->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_card->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', v_deadline::text);
        payload := jsonb_build_object('aps', jsonb_build_object(
          'timestamp', p_now, 'event', 'update', 'content-state', v_evening,
          'alert', jsonb_build_object('title', 'Icon', 'body', 'Finish what you signed.')));
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
    elsif v_slot ~ '^renew-[0-9]+$' then
      -- For the install whose card runs out: a fresh card on the day as it
      -- stands, closing the running one. Starting by push must carry an alert
      -- (Apple); it repeats the card's line, silently. An update cannot
      -- extend the 8 hours, so nothing goes without push-to-start.
      if v_install.id = p_job->>'installation_id' and v_push_to_start is not null then
        v_state := case when p_job->>'status' = 'honoured' then v_honoured
                        when v_evening_at <= p_now then v_evening
                        else v_morning end;
        if v_card is not null then
          installation_id := v_install.id; channel := 'live_activity_end'; auxiliary := true;
          token := v_card->>'token'; environment := v_card->>'environment';
          headers := jsonb_build_object('apns-push-type', 'liveactivity',
            'apns-topic', (v_card->>'topic') || '.push-type.liveactivity',
            'apns-priority', '10', 'apns-expiration', (v_deadline + 4 * 3600)::text);
          payload := jsonb_build_object('aps', jsonb_build_object(
            'timestamp', p_now, 'event', 'end', 'content-state', v_state, 'dismissal-date', p_now));
          return next;
          auxiliary := false;
        end if;
        v_aps := jsonb_build_object(
          'timestamp', p_now, 'event', 'start', 'content-state', v_state,
          'attributes-type', 'IconActivityAttributes', 'attributes', jsonb_build_object('facts', public.icon_push_facts(p_job)),
          'alert', jsonb_build_object('title', 'Icon', 'body', v_state->>'line'),
          'input-push-token', 1);
        if v_state->>'phase' = 'morning' and v_evening_at > p_now then
          v_aps := v_aps || jsonb_build_object('stale-date', v_evening_at);
        end if;
        installation_id := v_install.id; channel := 'live_activity_start';
        token := v_push_to_start->>'token'; environment := v_push_to_start->>'environment';
        headers := jsonb_build_object('apns-push-type', 'liveactivity',
          'apns-topic', (v_push_to_start->>'topic') || '.push-type.liveactivity',
          'apns-priority', '10', 'apns-expiration', v_deadline::text);
        payload := jsonb_build_object('aps', v_aps);
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

revoke all on function public.icon_push_plan(jsonb, bigint, text[], text[]) from public, anon, authenticated;

commit;

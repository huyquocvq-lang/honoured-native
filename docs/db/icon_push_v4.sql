-- Icon push v4 (Oct 5, 2026): the Dynamic Island shows the day's Health
-- total (client request: "where the tick is, it still should give the current
-- HealthKit data"). The app writes the reading into the card whenever it runs;
-- a push replaces the card's whole content state, so the server's pushes now
-- carry the day's last reported total too (icon_days.measured_value), or a
-- HONOURED push would wipe the figure the app had just shown. Without a reading
-- the key is left out, so older apps decode the state exactly as before.
-- On top of icon_push_v3.sql. Applied externally to Lovable Cloud and mirrored
-- here; the plan stays a byte-for-byte port of docs/phase2/icon-push/plan.ts.
begin;

-- 1. Jobs carry the day's last reading (a new column, so the function is
-- recreated; icon_push_tick passes each row on as JSON).
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
  tokens jsonb
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

-- 2. The card states carry it.
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

-- Production function bodies, verbatim from pg_get_functiondef() on Lovable
-- Cloud (28 Oct 2026, after icon_scoring_v4.sql), with production's grants:
-- no PUBLIC execute, service_role everywhere, authenticated only where the
-- app calls the function. 03_baseline_check.sql compares their md5s with
-- production's. Generated; do not edit by hand.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
revoke all on function public.update_updated_at_column from public;
grant execute on function public.update_updated_at_column to service_role;

CREATE OR REPLACE FUNCTION public.icon_cut(p_text text, p_limit integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when char_length(t) <= p_limit then t
    else btrim(left(t, p_limit - 1), E' \t\n\r') || '…'
  end
  from (select btrim(coalesce(p_text, ''), E' \t\n\r') as t) s
$function$;
revoke all on function public.icon_cut from public;
grant execute on function public.icon_cut to service_role;

CREATE OR REPLACE FUNCTION public.icon_target_split(p_target text, OUT value text, OUT unit text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.icon_target_split from public;
grant execute on function public.icon_target_split to service_role;

CREATE OR REPLACE FUNCTION public.icon_copy_affirmation(p_session_number integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select (array[
    'You''ve got this.',
    'You''re closer than you think.',
    'Today is part of the promise.',
    'Keep your word to yourself.',
    'Small steps, kept promises.',
    'Become what you signed.',
    'Prove it again today.'
  ])[((greatest(coalesce(p_session_number, 1), 1) - 1) % 7) + 1]
$function$;
revoke all on function public.icon_copy_affirmation from public;
grant execute on function public.icon_copy_affirmation to service_role;

CREATE OR REPLACE FUNCTION public.icon_copy_deadline(p_deadline timestamp with time zone, p_timezone text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.icon_copy_deadline from public;
grant execute on function public.icon_copy_deadline to service_role;

CREATE OR REPLACE FUNCTION public.icon_schedule(p_start_day date, p_end_day date, p_weekdays smallint[], p_deadline_time time without time zone, p_timezone text, p_signed_at timestamp with time zone)
 RETURNS TABLE(day date, session_number integer, deadline_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.icon_schedule from public;
grant execute on function public.icon_schedule to service_role, authenticated;

CREATE OR REPLACE FUNCTION public.icon_reserved_days(p_user_id uuid)
 RETURNS TABLE(contract_id uuid, day date, starts_at timestamp with time zone, ends_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, d.day,
         (d.day::timestamp) at time zone c.icon_timezone,
         ((d.day + 1)::timestamp) at time zone c.icon_timezone
  from public.contracts c
  join public.icon_days d on d.contract_id = c.id
  where c.user_id = p_user_id
    and c.status = 'active'
    and c.icon_weekdays is not null
    and d.status <> 'amended'
$function$;
revoke all on function public.icon_reserved_days from public;
grant execute on function public.icon_reserved_days to service_role;

CREATE OR REPLACE FUNCTION public.icon_days_to_measure()
 RETURNS TABLE(contract_id uuid, day date, starts_at timestamp with time zone, deadline_at timestamp with time zone, metric text, target double precision, unit text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
    and c.icon_metric is not null
    and d.day::timestamp at time zone c.icon_timezone <= now()
    and (
      (d.status = 'pending' and d.deadline_at + interval '24 hours' > now())
      or (d.status in ('honoured', 'broken')
          and d.resolution in ('target_met', 'target_missed', 'no_data')
          and d.deadline_at + interval '30 days' > now())
    )
  order by d.deadline_at, d.contract_id
$function$;
revoke all on function public.icon_days_to_measure from public;
grant execute on function public.icon_days_to_measure to service_role, authenticated;

CREATE OR REPLACE FUNCTION public.expire_icon_days()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with expired as (
    update public.icon_days d
    set status = 'broken',
        resolution = case
          when c.word_source_id is null then
            case when d.measured_value is null then 'no_data' else 'target_missed' end
          when d.word_latest_at is not null then 'target_missed'
          else 'word_unverified'
        end,
        scored_at = now()
    from public.contracts c
    where c.id = d.contract_id
      and d.status = 'pending'
      and d.deadline_at <= now() - interval '1 hour'
      and (
        d.deadline_at <= now() - interval '24 hours'
        or (c.word_source_id is not null
            and d.word_latest_at is not null
            and d.word_latest_at <= d.deadline_at + interval '30 minutes')
      )
    returning 1
  )
  select count(*)::integer from expired
$function$;
revoke all on function public.expire_icon_days from public;
grant execute on function public.expire_icon_days to service_role;

CREATE OR REPLACE FUNCTION public.icon_push_facts(p_job jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.icon_push_facts from public;
grant execute on function public.icon_push_facts to service_role;

CREATE OR REPLACE FUNCTION public.icon_push_jobs(p_now timestamp with time zone DEFAULT now(), p_window interval DEFAULT '00:15:00'::interval)
 RETURNS TABLE(job text, user_id uuid, contract_id uuid, client_id text, day date, session_number integer, total_sessions integer, deadline_at timestamp with time zone, evening_at timestamp with time zone, status text, activity text, target text, because text, timezone text, morning_channel text, measured_value double precision, tokens jsonb, installation_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.icon_push_jobs from public;
grant execute on function public.icon_push_jobs to service_role;

CREATE OR REPLACE FUNCTION public.icon_push_plan(p_job jsonb, p_now bigint, p_topics text[], p_environments text[])
 RETURNS TABLE(installation_id text, channel text, token text, environment text, headers jsonb, payload jsonb, auxiliary boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.icon_push_plan from public;
grant execute on function public.icon_push_plan to service_role;

CREATE OR REPLACE FUNCTION public.contracts_icon_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.contracts_icon_guard from public;
grant execute on function public.contracts_icon_guard to service_role;

CREATE OR REPLACE FUNCTION public.contracts_icon_reserve()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.contracts_icon_reserve from public;
grant execute on function public.contracts_icon_reserve to service_role;

CREATE OR REPLACE FUNCTION public.contracts_icon_days()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.contracts_icon_days from public;
grant execute on function public.contracts_icon_days to service_role;

CREATE OR REPLACE FUNCTION public.contracts_word_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE' then
    -- The source and target are part of the signed terms.
    new.word_source_id := old.word_source_id;
    new.word_source_kind := old.word_source_kind;
    new.word_target := old.word_target;
    return new;
  end if;
  if new.icon_weekdays is null then
    new.word_source_id := null;
    new.word_source_kind := null;
    new.word_target := null;
  end if;
  return new;
end;
$function$;
revoke all on function public.contracts_word_guard from public;
grant execute on function public.contracts_word_guard to service_role;

CREATE OR REPLACE FUNCTION public.self_report_icon_day(p_contract_id uuid, p_day date, p_honoured boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id uuid := (select auth.uid());
  v_starts timestamptz;
  v_deadline timestamptz;
  v_status text;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_contract_id is null or p_day is null or p_honoured is null then
    raise exception 'contract, day and result are required' using errcode = '22023';
  end if;

  select d.day::timestamp at time zone c.icon_timezone, d.deadline_at, d.status
    into v_starts, v_deadline, v_status
  from public.icon_days d
  join public.contracts c on c.id = d.contract_id
  where d.contract_id = p_contract_id
    and d.day = p_day
    and d.user_id = caller_id
    and c.icon_metric is null
    and c.word_source_id is null
  for update of d;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if v_status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'already_stamped', 'status', v_status);
  end if;
  if now() < v_starts then
    return jsonb_build_object('ok', false, 'reason', 'not_started');
  end if;
  if now() >= v_deadline + interval '24 hours' then
    return jsonb_build_object('ok', false, 'reason', 'window_closed');
  end if;

  update public.icon_days
  set status = case when p_honoured then 'honoured' else 'broken' end,
      resolution = 'self_reported',
      scored_at = now()
  where contract_id = p_contract_id and day = p_day;

  return jsonb_build_object('ok', true, 'status', case when p_honoured then 'honoured' else 'broken' end);
end;
$function$;
revoke all on function public.self_report_icon_day from public;
grant execute on function public.self_report_icon_day to service_role, authenticated;

CREATE OR REPLACE FUNCTION public.record_word_reading(p_contract_id uuid, p_source_id text, p_count integer, p_read_at timestamp with time zone, p_revision text, p_modified_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id uuid := (select auth.uid());
  v_contract public.contracts%rowtype;
  v_last public.word_source_readings%rowtype;
  v_has_last boolean;
  v_day public.icon_days%rowtype;
  v_starts timestamptz;
  v_baseline integer;
  v_progress integer;
  v_status text;
  v_grace public.icon_days%rowtype;
  v_grace_starts timestamptz;
  v_grace_baseline integer;
  v_grace_progress integer;
  v_grace_status text;
  v_result jsonb;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_contract_id is null or p_source_id is null or p_count is null
     or p_read_at is null or p_revision is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if p_count < 0 or p_count > 10000000 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_count');
  end if;
  if p_read_at > now() + interval '5 minutes' or p_read_at < now() - interval '8 days' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_time');
  end if;
  -- The content cannot have changed after it was read (5 minutes of clock slack).
  if p_modified_at is not null and p_modified_at > p_read_at + interval '5 minutes' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_time');
  end if;
  if p_revision !~ '^[A-Za-z0-9_.-]{1,64}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_revision');
  end if;

  select * into v_contract
  from public.contracts c
  where c.id = p_contract_id
    and c.user_id = caller_id
    and c.word_source_id is not null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if v_contract.word_source_id <> p_source_id then
    return jsonb_build_object('ok', false, 'reason', 'source_mismatch');
  end if;

  select * into v_last
  from public.word_source_readings r
  where r.contract_id = p_contract_id;
  v_has_last := found;

  if v_has_last then
    if p_read_at = v_last.last_read_at and p_count = v_last.last_count
       and p_revision = v_last.last_revision then
      return jsonb_build_object('ok', true, 'status', 'duplicate');
    end if;
    if p_read_at <= v_last.last_read_at then
      return jsonb_build_object('ok', false, 'reason', 'stale');
    end if;
  end if;

  -- Grace window: a reading taken up to 30 minutes after a cut-off counts for
  -- that day only when the content last changed by the cut-off.
  if p_modified_at is not null then
    select d.* into v_grace
    from public.icon_days d
    where d.contract_id = p_contract_id
      and d.user_id = caller_id
      and d.status = 'pending'
      and d.deadline_at < p_read_at
      and p_read_at <= d.deadline_at + interval '30 minutes'
      and p_modified_at <= d.deadline_at
    order by d.deadline_at desc
    limit 1
    for update;
    if found then
      v_grace_starts := v_grace.day::timestamp at time zone v_contract.icon_timezone;
      v_grace_baseline := v_grace.word_baseline;
      if v_grace_baseline is null and p_modified_at <= v_grace_starts then
        v_grace_baseline := p_count;
      end if;
      if v_grace_baseline is null and v_has_last
         and v_last.last_read_at < v_grace_starts
         and v_last.last_read_at >= v_grace_starts - interval '24 hours' then
        v_grace_baseline := v_last.last_count;
      end if;
      -- No baseline at all: the day is left untouched.
      if v_grace_baseline is not null then
        v_grace_progress := greatest(p_count - v_grace_baseline, 0);
        v_grace_status := case when v_grace_progress >= v_contract.word_target then 'honoured' else 'pending' end;
        update public.icon_days
        set word_baseline = v_grace_baseline,
            word_latest_count = p_count,
            word_latest_at = p_read_at,
            word_progress = v_grace_progress,
            word_source_revision = p_revision,
            measured_value = v_grace_progress,
            status = v_grace_status,
            resolution = case when v_grace_status = 'honoured' then 'target_met' else null end,
            scored_at = case when v_grace_status = 'honoured' then now() else null end
        where contract_id = v_grace.contract_id and day = v_grace.day;
      end if;
    end if;
  end if;

  select d.* into v_day
  from public.icon_days d
  where d.contract_id = p_contract_id
    and d.user_id = caller_id
    and d.day::timestamp at time zone v_contract.icon_timezone <= p_read_at
    and p_read_at <= d.deadline_at
  order by d.deadline_at
  limit 1
  for update;

  if not found then
    v_status := 'no_day';
  elsif v_day.status <> 'pending' then
    v_status := 'settled';
  else
    v_starts := v_day.day::timestamp at time zone v_contract.icon_timezone;
    v_baseline := v_day.word_baseline;
    -- Exact start: unchanged since the day began, so this is its count at the start.
    if v_baseline is null and p_modified_at is not null and p_modified_at <= v_starts then
      v_baseline := p_count;
    end if;
    -- O-07: the stored reading is the baseline only when it was read within
    -- the 24 hours before the day started; an older one (a sparse Oath the
    -- app was not opened in) would count days of writing toward one day.
    if v_baseline is null and v_has_last
       and v_last.last_read_at < v_day.day::timestamp at time zone v_contract.icon_timezone
       and v_last.last_read_at >= (v_day.day::timestamp at time zone v_contract.icon_timezone) - interval '24 hours' then
      v_baseline := v_last.last_count;
    end if;

    if v_baseline is null then
      -- First reading of the day is only the starting point.
      update public.icon_days
      set word_baseline = p_count,
          word_latest_count = p_count,
          word_latest_at = p_read_at,
          word_progress = 0,
          word_source_revision = p_revision,
          measured_value = 0
      where contract_id = v_day.contract_id and day = v_day.day;
      v_status := 'baseline';
    else
      v_progress := greatest(p_count - v_baseline, 0);
      if v_progress >= v_contract.word_target then
        update public.icon_days
        set word_baseline = v_baseline,
            word_latest_count = p_count,
            word_latest_at = p_read_at,
            word_progress = v_progress,
            word_source_revision = p_revision,
            measured_value = v_progress,
            status = 'honoured',
            resolution = 'target_met',
            scored_at = now()
        where contract_id = v_day.contract_id and day = v_day.day;
        v_status := 'honoured';
      else
        update public.icon_days
        set word_baseline = v_baseline,
            word_latest_count = p_count,
            word_latest_at = p_read_at,
            word_progress = v_progress,
            word_source_revision = p_revision,
            measured_value = v_progress
        where contract_id = v_day.contract_id and day = v_day.day;
        v_status := 'pending';
      end if;
    end if;
  end if;

  insert into public.word_source_readings as r
    (contract_id, user_id, source_id, last_count, last_read_at, last_revision, updated_at)
  values (p_contract_id, caller_id, p_source_id, p_count, p_read_at, p_revision, now())
  on conflict (contract_id) do update
    set last_count = excluded.last_count,
        last_read_at = excluded.last_read_at,
        last_revision = excluded.last_revision,
        updated_at = now();

  v_result := jsonb_build_object('ok', true, 'status', v_status);
  if v_grace_status is not null then
    v_result := v_result || jsonb_build_object('grace', v_grace_status);
  end if;
  return v_result;
end;
$function$;
revoke all on function public.record_word_reading from public;
grant execute on function public.record_word_reading to service_role, authenticated;

CREATE OR REPLACE FUNCTION public.record_icon_measurements(rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.record_icon_measurements from public;
grant execute on function public.record_icon_measurements to service_role, authenticated;

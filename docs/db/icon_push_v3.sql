-- Icon push v3 (V1.2 M2-07/M2-09): the evening card is a fresh card.
-- Applied externally to Lovable Cloud and mirrored here; no build runs this
-- file. Needs icon_push_v2.sql.
--
-- iOS ends a Live Activity 8 hours after it starts. With the usual reminders
-- (07:00 and 20:00) the morning card is gone before the evening, so updating
-- it showed nothing. As the scope describes ("appears at the morning reminder
-- time, and again at the evening reminder time; each stays within Apple's Live
-- Activity time limit"), the evening job now closes the morning card and
-- push-starts a new one on the evening line; the evening reminder is set
-- within 8 hours of the cut-off, so that card lasts until it. Without
-- push-to-start the running card is updated, or a quiet alert sent, as before.
--
-- The close is housekeeping (icon_push_sends.auxiliary): only the slot's own
-- send decides whether it was sent, so a failed start is sent again.
-- docs/phase2/icon-push/plan.ts stays the reference (parity_fixtures.ts).
begin;

alter table public.icon_push_sends add column if not exists auxiliary boolean not null default false;

drop function if exists public.icon_push_plan(jsonb, bigint, text[], text[]);
create function public.icon_push_plan(
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
           coalesce(array_agg(s.outcome) filter (where not s.auxiliary), '{}') as outcomes,
           array_agg(s.channel) filter (where s.outcome = 'sent' and not s.auxiliary) as sent_channels,
           (array_agg(s.channel order by s.request_id) filter (where not s.auxiliary))[1] as first_channel,
           (array_agg(s.apns_status order by s.request_id) filter (where not s.auxiliary))[1] as first_status,
           (array_agg(s.apns_reason order by s.request_id) filter (where not s.auxiliary))[1] as first_reason
    from public.icon_push_sends s
    where not s.processed
    group by s.contract_id, s.day, s.slot
    having bool_and(s.outcome is not null)
  loop
    if cardinality(v_group.outcomes) = 0 then
      null; -- housekeeping only
    elsif 'sent' = any(v_group.outcomes) then
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
      insert into public.icon_push_sends (request_id, contract_id, day, slot, installation_id, channel, token, auxiliary)
      values (v_request, v_job.contract_id, v_job.day, v_job.slot, v_send.installation_id::uuid, v_send.channel, v_send.token, v_send.auxiliary);
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

revoke all on function public.icon_push_plan(jsonb, bigint, text[], text[]) from public, anon, authenticated;
revoke all on function public.icon_push_collect(timestamptz) from public, anon, authenticated;
revoke all on function public.icon_push_tick(timestamptz) from public, anon, authenticated;
grant execute on function public.icon_push_tick(timestamptz) to service_role;

commit;

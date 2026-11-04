-- Goal-latency diagnostics v1 (Phase 3 M2-B, docs/phase3/core-motion-plan.vi.md).
-- The iOS app records, for each step or walking-distance goal, when it was
-- crossed, noticed, announced and seen, and uploads the lines with
-- record_goal_diagnostics(). Every moment says how it is known:
--   * recorded: noted as it happened (occurred_at);
--   * estimated: inferred afterwards, always a window (window_start ..
--     window_end) and the method used, never a single time;
--   * unknown: no evidence, so no time at all.
-- goal_diagnostics_timeline() puts each goal's day together for reports and
-- for Phase 3 M3. Lines hold counts, times and identifiers only.
-- Applied to Lovable Cloud on 21 Oct 2026 (through the Lovable database
-- tool); no build runs this file. Rollback: goal_diagnostics_v1_rollback.sql.
-- How long lines are kept is not decided yet: purge_goal_diagnostics()
-- deletes those older than its argument, and nothing schedules it.
begin;

create table if not exists public.goal_diagnostics (
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Made on the device, so a line uploaded twice is stored once.
  id uuid not null,
  event text not null,
  certainty text not null,
  occurred_at timestamptz,
  window_start timestamptz,
  window_end timestamptz,
  method text,
  reason text,
  source text,
  metric text,
  activity_id text,
  day date,
  value double precision,
  target double precision,
  details jsonb,
  -- The device clock when the line was written, and when it was uploaded;
  -- received_at minus sent_at shows how far that clock is off.
  device_time timestamptz not null,
  sent_at timestamptz,
  received_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint goal_diagnostics_event_check check (event in (
    'app_lifecycle', 'app_ran', 'reading', 'goal_detected', 'data_available', 'goal_crossed',
    'notification_requested', 'notification_delivered', 'notification_opened', 'live_activity_update'
  )),
  constraint goal_diagnostics_certainty_check check (
    (certainty = 'recorded' and occurred_at is not null
       and window_start is null and window_end is null and method is null)
    or (certainty = 'estimated' and occurred_at is null
       and window_start is not null and window_end is not null and window_end >= window_start
       and method is not null)
    or (certainty = 'unknown' and occurred_at is null and window_start is null and window_end is null)
  ),
  constraint goal_diagnostics_source_check check (source is null or source in ('healthkit', 'core_motion')),
  constraint goal_diagnostics_value_check check (
    (value is null or (value >= 0 and value < 1e12)) and (target is null or (target >= 0 and target < 1e12))
  ),
  constraint goal_diagnostics_text_check check (
    char_length(coalesce(method, '')) <= 64 and char_length(coalesce(reason, '')) <= 64
    and char_length(coalesce(metric, '')) <= 64 and char_length(coalesce(activity_id, '')) <= 128
  ),
  constraint goal_diagnostics_details_check check (
    details is null or (jsonb_typeof(details) = 'object' and pg_column_size(details) <= 2048)
  )
);

create index if not exists goal_diagnostics_user_day_idx
  on public.goal_diagnostics (user_id, day, activity_id);
create index if not exists goal_diagnostics_received_idx
  on public.goal_diagnostics (received_at);

alter table public.goal_diagnostics enable row level security;

drop policy if exists "Users can view their own goal diagnostics" on public.goal_diagnostics;
create policy "Users can view their own goal diagnostics"
  on public.goal_diagnostics for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own goal diagnostics" on public.goal_diagnostics;
create policy "Users can insert their own goal diagnostics"
  on public.goal_diagnostics for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

-- Lines are never changed or removed by the app.
revoke all on public.goal_diagnostics from anon;
revoke update, delete, truncate, references, trigger on public.goal_diagnostics from authenticated;
grant select, insert on public.goal_diagnostics to authenticated;

-- Each row: { id, event, certainty, occurredAt?, windowStart?, windowEnd?,
-- method?, reason?, source?, metric?, activityId?, day?, value?, target?,
-- details?, deviceTime, sentAt? }. The account is always the caller's. A
-- row that breaks a rule is skipped, never an error, so one bad line cannot
-- fail the batch.
create or replace function public.record_goal_diagnostics(rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  item jsonb;
  added integer;
  inserted_count integer := 0;
  duplicate_count integer := 0;
  skipped_count integer := 0;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if rows is null or jsonb_typeof(rows) <> 'array' then
    raise exception 'rows must be a JSON array' using errcode = '22023';
  end if;
  -- Each row is checked in its own block (a subtransaction), so a call
  -- stays well under Postgres's cache of 64 of them per transaction.
  if jsonb_array_length(rows) > 50 then
    raise exception 'at most 50 rows per call' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(rows) loop
    begin
      insert into public.goal_diagnostics (
        user_id, id, event, certainty, occurred_at, window_start, window_end, method,
        reason, source, metric, activity_id, day, value, target, details, device_time, sent_at
      ) values (
        caller_id,
        (item->>'id')::uuid,
        item->>'event',
        item->>'certainty',
        (item->>'occurredAt')::timestamptz,
        (item->>'windowStart')::timestamptz,
        (item->>'windowEnd')::timestamptz,
        item->>'method',
        item->>'reason',
        item->>'source',
        item->>'metric',
        item->>'activityId',
        (item->>'day')::date,
        (item->>'value')::double precision,
        (item->>'target')::double precision,
        case when jsonb_typeof(item->'details') = 'object' then item->'details' end,
        (item->>'deviceTime')::timestamptz,
        (item->>'sentAt')::timestamptz
      )
      on conflict (user_id, id) do nothing;
      get diagnostics added = row_count;
      if added = 1 then
        inserted_count := inserted_count + 1;
      else
        duplicate_count := duplicate_count + 1;
      end if;
    exception when others then
      skipped_count := skipped_count + 1;
    end;
  end loop;

  return jsonb_build_object(
    'inserted', inserted_count,
    'duplicates', duplicate_count,
    'skipped', skipped_count
  );
end;
$$;

-- One row per goal the device saw met: when it was crossed (estimated),
-- when its data became readable (estimated), when the app noticed it, what
-- happened to the notification, when the Live Activity was first asked to
-- show it reached, and when the Icon day was stamped (server clock). Delays
-- involving an estimate are a range (min .. max seconds); a delay between
-- two recorded moments is a single figure. delivery is 'recorded',
-- 'unknown' or 'pending' (nothing settled yet); a notification counts as
-- delivered only when iOS reported it.
create or replace function public.goal_diagnostics_timeline(p_from date default null, p_to date default null)
returns table (
  day date,
  activity_id text,
  metric text,
  source text,
  target double precision,
  crossed_from timestamptz,
  crossed_to timestamptz,
  crossed_method text,
  data_available_from timestamptz,
  data_available_to timestamptz,
  detected_at timestamptz,
  detected_trigger text,
  notification text,
  delivery text,
  delivered_at timestamptz,
  opened_at timestamptz,
  first_card_update_at timestamptz,
  icon_stamped_at timestamptz,
  detected_after_crossing_min_s double precision,
  detected_after_crossing_max_s double precision,
  delivered_after_crossing_min_s double precision,
  delivered_after_crossing_max_s double precision,
  delivered_after_detected_s double precision,
  device_clock_offset_s double precision
)
language sql
stable
security invoker
set search_path = ''
as $$
  with detected as (
    select distinct on (g.day, g.activity_id)
           g.user_id, g.day, g.activity_id, g.metric, g.source, g.target, g.occurred_at,
           g.details->>'trigger' as trigger,
           'goal-' || g.activity_id || '-' || g.day::text as identifier
    from public.goal_diagnostics g
    where g.user_id = (select auth.uid())
      and g.event = 'goal_detected'
      and (p_from is null or g.day >= p_from)
      and (p_to is null or g.day <= p_to)
    order by g.day, g.activity_id, g.occurred_at
  )
  select d.day, d.activity_id, d.metric, d.source, d.target,
         crossed.window_start, crossed.window_end, crossed.method,
         available.window_start, available.window_end,
         d.occurred_at, d.trigger,
         requested.reason,
         coalesce(delivered.certainty, 'pending'),
         delivered.occurred_at,
         opened.occurred_at,
         card.first_update,
         icon.scored_at,
         extract(epoch from d.occurred_at - crossed.window_end)::double precision,
         extract(epoch from d.occurred_at - crossed.window_start)::double precision,
         extract(epoch from delivered.occurred_at - crossed.window_end)::double precision,
         extract(epoch from delivered.occurred_at - crossed.window_start)::double precision,
         extract(epoch from delivered.occurred_at - d.occurred_at)::double precision,
         clock.offset_s
  from detected d
  left join lateral (
    select x.window_start, x.window_end, x.method
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.event = 'goal_crossed'
      and x.activity_id = d.activity_id and x.day = d.day
    order by x.device_time desc
    limit 1
  ) crossed on true
  left join lateral (
    select x.window_start, x.window_end
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.event = 'data_available'
      and x.activity_id = d.activity_id and x.day = d.day
    order by x.device_time desc
    limit 1
  ) available on true
  left join lateral (
    select x.reason
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.event = 'notification_requested'
      and x.activity_id = d.activity_id and x.day = d.day
    order by x.occurred_at
    limit 1
  ) requested on true
  left join lateral (
    -- iOS's own delivery time wins over an unknown.
    select x.certainty, x.occurred_at
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.event = 'notification_delivered'
      and x.details->>'identifier' = d.identifier
    order by (x.certainty = 'recorded') desc, x.occurred_at
    limit 1
  ) delivered on true
  left join lateral (
    select min(x.occurred_at) as occurred_at
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.event = 'notification_opened'
      and x.details->>'identifier' = d.identifier
  ) opened on true
  left join lateral (
    -- The first update that showed the goal reached. In a HealthKit wake the
    -- card is updated before the goal check, so it can precede detection.
    select min(x.occurred_at) as first_update
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.event = 'live_activity_update'
      and x.activity_id = d.activity_id and x.details->>'reached' = 'true'
      and x.occurred_at >= coalesce(crossed.window_start, available.window_start, d.occurred_at - interval '1 hour')
      and x.occurred_at < d.occurred_at + interval '1 day'
  ) card on true
  left join lateral (
    select i.scored_at
    from public.icon_days i
    where i.user_id = d.user_id and i.day = d.day
      and i.contract_id::text = split_part(d.activity_id, ':', 1)
      and i.status in ('honoured', 'broken')
    limit 1
  ) icon on true
  left join lateral (
    select avg(extract(epoch from x.received_at - x.sent_at))::double precision as offset_s
    from public.goal_diagnostics x
    where x.user_id = d.user_id and x.day = d.day and x.sent_at is not null
  ) clock on true
  order by d.day, d.occurred_at
$$;

-- For a scheduled job once a retention period is agreed; not callable by
-- the app.
create or replace function public.purge_goal_diagnostics(older_than interval)
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from public.goal_diagnostics where received_at < now() - older_than returning 1
  )
  select count(*)::integer from gone
$$;

revoke all on function public.record_goal_diagnostics(jsonb) from public, anon;
revoke all on function public.goal_diagnostics_timeline(date, date) from public, anon;
revoke all on function public.purge_goal_diagnostics(interval) from public, anon, authenticated;
grant execute on function public.record_goal_diagnostics(jsonb) to authenticated;
grant execute on function public.goal_diagnostics_timeline(date, date) to authenticated;

commit;

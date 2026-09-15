begin;

create table if not exists public.health_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sample_uuid uuid not null,
  metric text not null,
  value double precision not null,
  unit text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  source_name text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, sample_uuid, metric),
  constraint health_samples_metric_check check (
    metric in (
      'steps',
      'distance_walking_running',
      'distance_cycling',
      'distance_swimming',
      'active_energy',
      'basal_energy',
      'heart_rate',
      'exercise_minutes',
      'sleep'
    )
  ),
  constraint health_samples_date_order_check check (ended_at >= started_at)
);

create index if not exists health_samples_user_metric_started_idx
  on public.health_samples (user_id, metric, started_at desc);

create table if not exists public.health_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  metric text not null,
  total double precision not null,
  unit text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, day, metric),
  constraint health_daily_metric_check check (
    metric in (
      'steps',
      'distance_walking_running',
      'distance_cycling',
      'distance_swimming',
      'active_energy',
      'basal_energy',
      'heart_rate',
      'exercise_minutes',
      'sleep'
    )
  )
);

alter table public.health_samples enable row level security;
alter table public.health_daily enable row level security;

drop policy if exists "Users can view their own health samples" on public.health_samples;
create policy "Users can view their own health samples"
  on public.health_samples for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own health samples" on public.health_samples;
create policy "Users can insert their own health samples"
  on public.health_samples for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own health samples" on public.health_samples;
create policy "Users can update their own health samples"
  on public.health_samples for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can view their own health totals" on public.health_daily;
create policy "Users can view their own health totals"
  on public.health_daily for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own health totals" on public.health_daily;
create policy "Users can insert their own health totals"
  on public.health_daily for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own health totals" on public.health_daily;
create policy "Users can update their own health totals"
  on public.health_daily for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.upsert_health_samples(batch jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  samples_count integer := 0;
  deletions_count integer := 0;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if batch is null or jsonb_typeof(batch) <> 'object' then
    raise exception 'batch must be a JSON object' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(batch->'samples', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(batch->'deletions', '[]'::jsonb)) <> 'array' then
    raise exception 'samples and deletions must be JSON arrays' using errcode = '22023';
  end if;

  insert into public.health_samples (
    user_id, sample_uuid, metric, value, unit,
    started_at, ended_at, source_name, deleted_at
  )
  select
    caller_id,
    (item->>'sampleUuid')::uuid,
    item->>'metric',
    (item->>'value')::double precision,
    item->>'unit',
    (item->>'startedAt')::timestamptz,
    (item->>'endedAt')::timestamptz,
    nullif(item->>'sourceName', ''),
    null
  from jsonb_array_elements(coalesce(batch->'samples', '[]'::jsonb)) item
  on conflict (user_id, sample_uuid, metric) do update set
    value = excluded.value,
    unit = excluded.unit,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    source_name = excluded.source_name,
    deleted_at = null;
  get diagnostics samples_count = row_count;

  update public.health_samples existing
  set deleted_at = coalesce((item->>'deletedAt')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch->'deletions', '[]'::jsonb)) item
  where existing.user_id = caller_id
    and existing.sample_uuid = (item->>'sampleUuid')::uuid
    and existing.metric = item->>'metric';
  get diagnostics deletions_count = row_count;

  return jsonb_build_object(
    'samplesUpserted', samples_count,
    'samplesDeleted', deletions_count
  );
end;
$$;

create or replace function public.upsert_health_daily(rows jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  upserted_count integer := 0;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if rows is null or jsonb_typeof(rows) <> 'array' then
    raise exception 'rows must be a JSON array' using errcode = '22023';
  end if;

  insert into public.health_daily (user_id, day, metric, total, unit, updated_at)
  select
    caller_id,
    (item->>'day')::date,
    item->>'metric',
    (item->>'total')::double precision,
    item->>'unit',
    now()
  from jsonb_array_elements(rows) item
  on conflict (user_id, day, metric) do update set
    total = excluded.total,
    unit = excluded.unit,
    updated_at = excluded.updated_at;
  get diagnostics upserted_count = row_count;

  return jsonb_build_object('rowsUpserted', upserted_count);
end;
$$;

revoke all on table public.health_samples from anon;
revoke all on table public.health_daily from anon;
grant select, insert, update on table public.health_samples to authenticated;
grant select, insert, update on table public.health_daily to authenticated;

revoke all on function public.upsert_health_samples(jsonb) from public, anon;
revoke all on function public.upsert_health_daily(jsonb) from public, anon;
grant execute on function public.upsert_health_samples(jsonb) to authenticated;
grant execute on function public.upsert_health_daily(jsonb) to authenticated;

commit;

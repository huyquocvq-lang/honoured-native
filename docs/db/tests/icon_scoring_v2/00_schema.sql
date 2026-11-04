-- Minimal Lovable Cloud stand-in: only what the Icon scoring functions touch.
-- icon_days columns, constraints, trigger and policy are copied from the
-- production catalog (16 Oct 2026); expire_icon_days() is the production body.
\set ON_ERROR_STOP on

create role authenticated nologin;
create role anon nologin;
create role service_role nologin;

create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;

create table public.contracts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  status text not null default 'active',
  icon_weekdays text[],
  icon_timezone text,
  icon_metric text,
  icon_target double precision,
  icon_unit text,
  word_source_id text
);
alter table public.contracts enable row level security;
create policy "Users can view their own contracts" on public.contracts
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.contracts to authenticated;

create function public.update_updated_at_column()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

create table public.icon_days (
  contract_id uuid not null references public.contracts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  session_number integer not null,
  deadline_at timestamptz not null,
  morning_at timestamptz,
  evening_at timestamptz,
  status text not null default 'pending',
  resolution text,
  measured_value double precision,
  scored_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  word_baseline integer,
  word_latest_count integer,
  word_latest_at timestamptz,
  word_progress integer,
  word_source_revision text,
  primary key (contract_id, day),
  constraint icon_days_resolution_check check ((((status = 'pending'::text) AND (resolution IS NULL) AND (scored_at IS NULL)) OR ((status = 'honoured'::text) AND (resolution = ANY (ARRAY['target_met'::text, 'self_reported'::text])) AND (scored_at IS NOT NULL)) OR ((status = 'broken'::text) AND (resolution = ANY (ARRAY['target_missed'::text, 'no_data'::text, 'self_reported'::text, 'word_unverified'::text])) AND (scored_at IS NOT NULL)) OR ((status = 'amended'::text) AND (resolution = 'amended'::text) AND (scored_at IS NOT NULL)))),
  constraint icon_days_session_number_check check ((session_number >= 1)),
  constraint icon_days_status_check check ((status = ANY (ARRAY['pending'::text, 'honoured'::text, 'broken'::text, 'amended'::text]))),
  constraint icon_days_word_latest_together check (((word_latest_count IS NULL) = (word_latest_at IS NULL))),
  constraint icon_days_word_nonnegative check ((((word_baseline IS NULL) OR (word_baseline >= 0)) AND ((word_latest_count IS NULL) OR (word_latest_count >= 0)) AND ((word_progress IS NULL) OR (word_progress >= 0))))
);
create trigger update_icon_days_updated_at before update on public.icon_days
  for each row execute function public.update_updated_at_column();
alter table public.icon_days enable row level security;
create policy "Users can view their own Icon days" on public.icon_days
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.icon_days to authenticated;

create or replace function public.expire_icon_days()
 returns integer
 language sql
 security definer
 set search_path to ''
as $function$
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

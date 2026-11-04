-- Lovable Cloud stand-in for the Icon revision checks: the tables the Icon
-- functions touch, with production's columns, constraints, policies and
-- grants (catalog read 28 Oct 2026, after icon_scoring_v4.sql). Functions
-- come from 01_prod_functions.sql, triggers from 02_triggers.sql.
\set ON_ERROR_STOP on

create role authenticated nologin;
create role anon nologin;
create role service_role nologin bypassrls;
grant usage on schema public to authenticated, anon, service_role;

create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon, service_role;
grant execute on function auth.uid() to authenticated, anon, service_role;

-- Supabase Storage: only what the signature checks read.
create schema storage;
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  owner uuid,
  owner_id text,
  created_at timestamptz default now()
);
create function storage.foldername(name text) returns text[]
language sql immutable
as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant usage on schema storage to authenticated, anon, service_role;

create table public.contracts (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  created_at timestamptz not null default now(),
  deadline timestamptz not null,
  resolved_at timestamptz,
  primary_type text not null,
  primary_activity text not null,
  primary_target text,
  secondary_type text,
  secondary_activity text,
  secondary_target text,
  because text not null default ''::text,
  locked boolean not null default false,
  standing boolean not null default false,
  signature_path text,
  voice_of_change_id text,
  progress numeric,
  status text not null default 'active'::text,
  updated_at timestamptz not null default now(),
  icon_weekdays smallint[],
  icon_start_day date,
  icon_period_count integer,
  icon_period_unit text,
  icon_end_day date,
  icon_deadline_time time without time zone,
  icon_timezone text,
  icon_morning_time time without time zone,
  icon_evening_time time without time zone,
  icon_metric text,
  icon_target double precision,
  icon_unit text,
  word_source_id text,
  word_source_kind text,
  word_target integer,
  constraint contracts_user_id_client_id_key unique (user_id, client_id),
  constraint contracts_word_fields_together check ((((word_source_id IS NULL) = (word_source_kind IS NULL)) AND ((word_source_id IS NULL) = (word_target IS NULL)))),
  constraint contracts_word_not_health check (((word_source_id IS NULL) OR ((icon_metric IS NULL) AND (icon_weekdays IS NOT NULL)))),
  constraint contracts_word_source_id_opaque check (((word_source_id IS NULL) OR (word_source_id ~ '^[A-Za-z0-9_-]{1,128}$'::text))),
  constraint contracts_word_source_kind_known check (((word_source_kind IS NULL) OR (word_source_kind = ANY (ARRAY['word'::text, 'text'::text, 'rich_text'::text, 'rich_text_directory'::text, 'scrivener'::text])))),
  constraint contracts_word_target_range check (((word_target IS NULL) OR ((word_target >= 100) AND (word_target <= 100000))))
);
alter table public.contracts enable row level security;
create policy "Users can create their own contracts" on public.contracts
  for insert to authenticated with check (auth.uid() = user_id);
create policy "Users can delete their own contracts" on public.contracts
  for delete to authenticated using (auth.uid() = user_id);
create policy "Users can update their own contracts" on public.contracts
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users can view their own contracts" on public.contracts
  for select to authenticated using (auth.uid() = user_id);
grant all on public.contracts to anon, authenticated, service_role;

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
  measured_source text,
  primary key (contract_id, day),
  constraint icon_days_measured_source_check check (((measured_source IS NULL) OR (measured_source = ANY (ARRAY['healthkit'::text, 'healthkit_iphone'::text, 'core_motion'::text])))),
  constraint icon_days_resolution_check check ((((status = 'pending'::text) AND (resolution IS NULL) AND (scored_at IS NULL)) OR ((status = 'honoured'::text) AND (resolution = ANY (ARRAY['target_met'::text, 'self_reported'::text])) AND (scored_at IS NOT NULL)) OR ((status = 'broken'::text) AND (resolution = ANY (ARRAY['target_missed'::text, 'no_data'::text, 'self_reported'::text, 'word_unverified'::text])) AND (scored_at IS NOT NULL)) OR ((status = 'amended'::text) AND (resolution = 'amended'::text) AND (scored_at IS NOT NULL)))),
  constraint icon_days_session_number_check check ((session_number >= 1)),
  constraint icon_days_status_check check ((status = ANY (ARRAY['pending'::text, 'honoured'::text, 'broken'::text, 'amended'::text]))),
  constraint icon_days_word_latest_together check (((word_latest_count IS NULL) = (word_latest_at IS NULL))),
  constraint icon_days_word_nonnegative check ((((word_baseline IS NULL) OR (word_baseline >= 0)) AND ((word_latest_count IS NULL) OR (word_latest_count >= 0)) AND ((word_progress IS NULL) OR (word_progress >= 0)))),
  constraint icon_days_word_revision_opaque check (((word_source_revision IS NULL) OR (word_source_revision ~ '^[A-Za-z0-9_.-]{1,64}$'::text)))
);
alter table public.icon_days enable row level security;
create policy "Users can view their own Icon days" on public.icon_days
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.icon_days to authenticated;
grant all on public.icon_days to service_role;

create table public.word_source_readings (
  contract_id uuid primary key references public.contracts(id) on delete cascade,
  user_id uuid not null,
  source_id text not null,
  last_count integer not null,
  last_read_at timestamptz not null,
  last_revision text not null,
  updated_at timestamptz not null
);

create table public.push_tokens (
  id uuid not null default gen_random_uuid() primary key,
  user_id uuid not null,
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
  token_since timestamptz not null default now()
);

create table public.icon_push_sends (
  request_id bigint not null,
  contract_id uuid not null,
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
  auxiliary boolean not null default false
);

create table public.icon_push_log (
  contract_id uuid not null,
  day date not null,
  slot text not null,
  channel text not null,
  status text not null,
  apns_status integer,
  apns_reason text,
  recorded_at timestamptz not null default now()
);

-- Test helper: raises on a mismatch, prints "ok  <label>" otherwise.
create function public.t_eq(p_label text, p_got anyelement, p_want anyelement) returns void
language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAIL %: got %, want %', p_label, p_got, p_want;
  end if;
  raise notice 'ok  %', p_label;
end $$;

-- Minimal Lovable Cloud stand-in for the email opt-in checks: auth.users,
-- profiles and trial_state as the production catalog showed them on
-- 28 Oct 2026 (columns, RLS policies, table grants, triggers), with the
-- production handle_new_user() body that email_opt_in_v1.sql replaces.
\set ON_ERROR_STOP on

create role authenticated nologin;
create role anon nologin;

create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;

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

create table public.profiles (
  id uuid primary key,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  email text,
  deleted_at timestamptz,
  purge_after timestamptz
);
create trigger update_profiles_updated_at before update on public.profiles
  for each row execute function public.update_updated_at_column();
alter table public.profiles enable row level security;
create policy "Users can insert their own profile" on public.profiles
  for insert with check (auth.uid() = id);
create policy "Users can update their own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "Users can view their own profile" on public.profiles
  for select using (auth.uid() = id);
grant select, insert, update on public.profiles to authenticated, anon;

create table public.trial_state (
  user_id uuid primary key,
  sessions_used integer not null default 0,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_session_at timestamptz,
  reset_timezone text
);

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'name', ''),
    new.email
  )
  on conflict (id) do update
    set display_name = coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'name', ''),
        email = new.email;

  insert into public.trial_state (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$function$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

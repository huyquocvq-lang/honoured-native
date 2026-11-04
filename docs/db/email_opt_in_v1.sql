-- Email opt-in (Phase 4 M1.2): the person's choice to receive Honoured
-- inspiration, updates and new features, kept on their profile.
--
-- Consent is recorded as a value, the moment it was given and where it was
-- given. It is off for every existing and new account until the person
-- ticks the box at sign-up or turns the Settings toggle on. Signing in again
-- never changes it.
--
--   * Email sign-up passes `marketing_opt_in` ('true' / 'false') in the
--     sign-up metadata; handle_new_user() records it with source
--     `signup_email`.
--   * Apple and Google sign-up cannot carry metadata, so the web app calls
--     record_signup_marketing_opt_in() right after the account exists. It
--     only applies to an account created in the last 30 minutes that has no
--     recorded choice yet, so a later sign-in cannot overwrite anything.
--   * The Settings toggle calls set_marketing_opt_in(); source `settings`.
--
-- Clients keep their table-level grants on profiles, so a trigger keeps the
-- three consent columns unchanged for any direct insert or update made as
-- `authenticated` or `anon`; only the SECURITY DEFINER functions here write
-- them. Re-running this file is harmless. Roll back with
-- email_opt_in_v1_rollback.sql.

begin;

alter table public.profiles
  add column if not exists marketing_opt_in boolean not null default false,
  add column if not exists marketing_opt_in_at timestamptz,
  add column if not exists marketing_opt_in_source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_marketing_opt_in_source_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_marketing_opt_in_source_check
      check (marketing_opt_in_source is null
             or marketing_opt_in_source in ('signup_email', 'signup_apple', 'signup_google', 'settings'));
  end if;
  -- A recorded choice always has both its time and its source; no choice
  -- recorded means not opted in.
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_marketing_opt_in_recorded'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_marketing_opt_in_recorded
      check ((marketing_opt_in_at is null) = (marketing_opt_in_source is null)
             and (marketing_opt_in_at is not null or not marketing_opt_in));
  end if;
end $$;

comment on column public.profiles.marketing_opt_in is
  'Whether the person agreed to receive Honoured inspiration, updates and new features. False until they opt in.';
comment on column public.profiles.marketing_opt_in_at is
  'When the current marketing_opt_in value was chosen; null when no choice was ever recorded.';
comment on column public.profiles.marketing_opt_in_source is
  'Where the current choice was made: signup_email, signup_apple, signup_google or settings.';

create or replace function public.profiles_marketing_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  -- Only the SECURITY DEFINER functions below, which run as their owner,
  -- may write consent. A client writing its own profile row keeps the
  -- stored values (or the defaults, for a row it inserts).
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.marketing_opt_in := false;
    new.marketing_opt_in_at := null;
    new.marketing_opt_in_source := null;
  else
    new.marketing_opt_in := old.marketing_opt_in;
    new.marketing_opt_in_at := old.marketing_opt_in_at;
    new.marketing_opt_in_source := old.marketing_opt_in_source;
  end if;
  return new;
end;
$function$;

drop trigger if exists profiles_marketing_guard on public.profiles;
create trigger profiles_marketing_guard
  before insert or update on public.profiles
  for each row execute function public.profiles_marketing_guard();

-- The production body (28 Oct 2026) plus the email sign-up choice. On a
-- conflicting profile row only the name and email are refreshed, as before;
-- consent is never touched there.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_choice text := lower(coalesce(new.raw_user_meta_data ->> 'marketing_opt_in', ''));
  v_recorded boolean := v_choice in ('true', 'false');
begin
  insert into public.profiles (id, display_name, email, marketing_opt_in, marketing_opt_in_at, marketing_opt_in_source)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'name', ''),
    new.email,
    v_choice = 'true',
    case when v_recorded then now() end,
    case when v_recorded then 'signup_email' end
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

-- Apple and Google sign-up: record the box the person saw on the sign-up
-- screen, once, for a brand-new account only.
create or replace function public.record_signup_marketing_opt_in(p_opt_in boolean, p_source text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_created timestamptz;
  v_recorded_at timestamptz;
begin
  if v_uid is null then
    raise exception 'record_signup_marketing_opt_in: not signed in' using errcode = '42501';
  end if;
  if p_opt_in is null or p_source is null
     or p_source not in ('signup_email', 'signup_apple', 'signup_google') then
    raise exception 'record_signup_marketing_opt_in: invalid choice or source' using errcode = '22023';
  end if;

  select created_at into v_created from auth.users where id = v_uid;
  select marketing_opt_in_at into v_recorded_at
    from public.profiles where id = v_uid for update;
  if not found then
    return jsonb_build_object('applied', false, 'reason', 'no_profile');
  end if;
  if v_recorded_at is not null then
    return jsonb_build_object('applied', false, 'reason', 'already_recorded');
  end if;
  if v_created is null or v_created < now() - interval '30 minutes' then
    return jsonb_build_object('applied', false, 'reason', 'not_a_new_account');
  end if;

  update public.profiles
     set marketing_opt_in = p_opt_in,
         marketing_opt_in_at = now(),
         marketing_opt_in_source = p_source
   where id = v_uid;
  return jsonb_build_object('applied', true, 'marketing_opt_in', p_opt_in, 'source', p_source);
end;
$function$;

-- The Settings toggle.
create or replace function public.set_marketing_opt_in(p_opt_in boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_at timestamptz;
begin
  if v_uid is null then
    raise exception 'set_marketing_opt_in: not signed in' using errcode = '42501';
  end if;
  if p_opt_in is null then
    raise exception 'set_marketing_opt_in: choice is required' using errcode = '22023';
  end if;

  update public.profiles
     set marketing_opt_in = p_opt_in,
         marketing_opt_in_at = now(),
         marketing_opt_in_source = 'settings'
   where id = v_uid
  returning marketing_opt_in_at into v_at;
  if not found then
    return jsonb_build_object('applied', false, 'reason', 'no_profile');
  end if;
  return jsonb_build_object('applied', true, 'marketing_opt_in', p_opt_in, 'source', 'settings', 'recorded_at', v_at);
end;
$function$;

revoke all on function public.record_signup_marketing_opt_in(boolean, text) from public, anon;
revoke all on function public.set_marketing_opt_in(boolean) from public, anon;
grant execute on function public.record_signup_marketing_opt_in(boolean, text) to authenticated;
grant execute on function public.set_marketing_opt_in(boolean) to authenticated;

commit;

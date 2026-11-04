-- Undoes email_opt_in_v1.sql: removes the consent functions, the guard and
-- the three profiles columns (and the choices recorded in them), and puts
-- back the production handle_new_user() body of 28 Oct 2026.

begin;

drop function if exists public.set_marketing_opt_in(boolean);
drop function if exists public.record_signup_marketing_opt_in(boolean, text);
drop trigger if exists profiles_marketing_guard on public.profiles;
drop function if exists public.profiles_marketing_guard();

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

alter table public.profiles
  drop constraint if exists profiles_marketing_opt_in_recorded,
  drop constraint if exists profiles_marketing_opt_in_source_check,
  drop column if exists marketing_opt_in_source,
  drop column if exists marketing_opt_in_at,
  drop column if exists marketing_opt_in;

commit;

-- Test helpers, created after icon_revisions_v1.sql (they read its columns);
-- functions are executable by PUBLIC, so authenticated can call them.
\set ON_ERROR_STOP on

create function public.t_state(p_contract text, p_day date) returns text security definer
language sql as $$
  select concat_ws('/', status, target_text, target_value, target_revision)
  from public.icon_days where contract_id = ('aaaaaaaa-0000-0000-0000-' || lpad(p_contract, 12, '0'))::uuid and day = p_day
$$;
create function public.t_today(p_tz text) returns date
language sql as $$ select (now() at time zone p_tz)::date $$;
create function public.t_rev(p_contract text, p_request text, p_target numeric, p_path text) returns jsonb
language sql as $$
  select public.revise_icon_target(
    ('aaaaaaaa-0000-0000-0000-' || lpad(p_contract, 12, '0'))::uuid,
    ('cccccccc-0000-0000-0000-' || lpad(p_request, 12, '0'))::uuid,
    p_target, p_path)
$$;

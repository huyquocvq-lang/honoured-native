\set ON_ERROR_STOP on
-- An account that existed before the migration, and one created two hours
-- before the checks (too old for a sign-up choice).
insert into auth.users (id, email, raw_user_meta_data, created_at) values
  ('00000000-0000-0000-0000-000000000000', 'old@example.com', '{"display_name":"Old"}', now() - interval '2 days');

-- Fails loudly with both sides printed.
create function public.t_eq(p_label text, p_got anyelement, p_want anyelement) returns void
language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAIL %: got %, want %', p_label, p_got, p_want;
  end if;
  raise notice 'ok  %', p_label;
end $$;
grant execute on function public.t_eq(text, anyelement, anyelement) to authenticated, anon;

-- plpgsql, so it can be created before the consent columns exist.
create function public.t_consent(p_id uuid) returns text
language plpgsql stable as $$
begin
  return (select concat_ws('|', marketing_opt_in::text,
                           case when marketing_opt_in_at is null then 'no-time' else 'time' end,
                           coalesce(marketing_opt_in_source, 'no-source'))
          from public.profiles where id = p_id);
end $$;

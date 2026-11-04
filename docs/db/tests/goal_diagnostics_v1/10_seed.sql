\set ON_ERROR_STOP on
-- U1 reports; U2 is someone else.
insert into auth.users values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');
insert into public.contracts (id, user_id, client_id, icon_weekdays, icon_timezone, icon_metric, icon_target, icon_unit, word_source_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'walk', '{mon}', 'Australia/Sydney', 'steps', 10000, 'count', null);
insert into public.icon_days (contract_id, user_id, day, session_number, deadline_at, status, resolution, measured_value, scored_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', date '2026-10-21', 1,
   timestamptz '2026-10-21 21:00:00+11', 'honoured', 'target_met', 10050, timestamptz '2026-10-21 17:09:00+11');

-- Fails loudly with both sides printed.
create function public.t_eq(p_label text, p_got anyelement, p_want anyelement) returns void
language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAIL %: got %, want %', p_label, p_got, p_want;
  end if;
  raise notice 'ok  %', p_label;
end $$;
grant execute on function public.t_eq(text, anyelement, anyelement) to authenticated;

\set ON_ERROR_STOP on
-- U1 is the person reporting; U2 owns a foreign day.
insert into auth.users values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

insert into public.contracts (id, user_id, client_id, icon_weekdays, icon_timezone, icon_metric, icon_target, icon_unit, word_source_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'steps-a', '{mon}', 'Australia/Sydney', 'steps', 10000, 'count', null),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'steps-b', '{mon}', 'Australia/Sydney', 'steps', 10000, 'count', null),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'unmeasured', '{mon}', 'Australia/Sydney', null, null, null, null),
  ('aaaaaaaa-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'word', '{mon}', 'Australia/Sydney', null, null, null, 'src-1'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'other-steps', '{mon}', 'Australia/Sydney', 'steps', 10000, 'count', null);

create table public.t_days (name text primary key, contract_id uuid not null, day date not null);
grant select on public.t_days to authenticated;

do $$
declare
  t date := (now() at time zone 'Australia/Sydney')::date;
  u1 uuid := '11111111-1111-1111-1111-111111111111';
  u2 uuid := '22222222-2222-2222-2222-222222222222';
  ca uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  cb uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  cu uuid := 'aaaaaaaa-0000-0000-0000-000000000003';
  cw uuid := 'aaaaaaaa-0000-0000-0000-000000000004';
  co uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
begin
  insert into public.t_days values
    ('A', ca, t), ('B', ca, t - 3), ('C', ca, t - 2), ('D', ca, t - 5), ('E', ca, t - 31),
    ('G', ca, t - 10), ('H', ca, t - 29), ('AM', ca, t - 7),
    ('P1', cb, t), ('P2', cb, t - 1), ('P3', cb, t - 2),
    ('S', cu, t - 1), ('W', cw, t - 1), ('O', co, t - 1);

  insert into public.icon_days (contract_id, user_id, day, session_number, deadline_at, status, resolution, measured_value, scored_at) values
    -- A: today, HONOURED at 10,183 five hours ago, cut-off still ahead.
    (ca, u1, t,      10, now() + interval '10 hours', 'honoured', 'target_met',    10183, now() - interval '5 hours'),
    -- B: BROKEN 3 days ago with a partial 8,286 (the 3 Oct case).
    (ca, u1, t - 3,   9, now() - interval '3 days',   'broken',   'target_missed',  8286, now() - interval '2 days'),
    -- C, D: BROKEN with no data.
    (ca, u1, t - 2,   8, now() - interval '2 days',   'broken',   'no_data',        null, now() - interval '1 day'),
    (ca, u1, t - 5,   7, now() - interval '5 days',   'broken',   'no_data',        null, now() - interval '4 days'),
    -- E: outside the 30-day window.
    (ca, u1, t - 31,  1, now() - interval '31 days',  'broken',   'target_missed',  5000, now() - interval '30 days'),
    -- G: HONOURED 10 days ago; H: BROKEN 29 days ago, inside the window.
    (ca, u1, t - 10,  5, now() - interval '10 days',  'honoured', 'target_met',    12000, now() - interval '10 days 3 hours'),
    (ca, u1, t - 29,  2, now() - interval '29 days',  'broken',   'target_missed',  9000, now() - interval '28 days'),
    -- AM: released by an early exit.
    (ca, u1, t - 7,   6, now() - interval '7 days',   'amended',  'amended',        null, now() - interval '8 days'),
    -- P1: pending today; P2: pending, cut-off 2 h ago; P3: pending with a
    -- stale 7,000, cut-off 25 h ago (belongs to expire_icon_days()).
    (cb, u1, t,       3, now() + interval '10 hours', 'pending',  null,             null, null),
    (cb, u1, t - 1,   2, now() - interval '2 hours',  'pending',  null,             null, null),
    (cb, u1, t - 2,   1, now() - interval '25 hours', 'pending',  null,             7000, null),
    -- S: self-reported (unmeasured Icon); W: Word Tracker; O: another person's.
    (cu, u1, t - 1,   1, now() - interval '2 hours',  'honoured', 'self_reported',  null, now() - interval '3 hours'),
    (cw, u1, t - 1,   1, now() - interval '3 hours',  'broken',   'word_unverified', null, now() - interval '1 hour'),
    (co, u2, t - 1,   1, now() - interval '2 hours',  'honoured', 'target_met',    11000, now() - interval '5 hours');
end $$;

create function public.t_row(p_name text, p_value float8, p_through timestamptz default null)
returns jsonb language sql stable as $$
  select jsonb_build_object('contractId', contract_id, 'day', day, 'value', p_value,
                            'measuredThrough', coalesce(p_through, now()))
  from public.t_days where name = p_name
$$;

create function public.t_report(p_name text, p_value float8, p_through timestamptz default null)
returns jsonb language sql volatile as $$
  select public.record_icon_measurements(jsonb_build_array(public.t_row(p_name, p_value, p_through)))
$$;

-- Read as the table owner so foreign rows are visible too.
create function public.t_get(p_name text) returns public.icon_days
language sql stable security definer as $$
  select d.* from public.icon_days d join public.t_days t using (contract_id, day) where t.name = p_name
$$;

create function public.t_measure_names() returns text
language sql stable as $$
  select string_agg(t.name, ',' order by t.name)
  from public.icon_days_to_measure() m
  join public.t_days t on t.contract_id = m.contract_id and t.day = m.day
$$;

-- Fails loudly with both sides printed.
create function public.t_eq(p_label text, p_got anyelement, p_want anyelement) returns void
language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAIL %: got %, want %', p_label, p_got, p_want;
  end if;
  raise notice 'ok  %', p_label;
end $$;

grant execute on all functions in schema public to authenticated;

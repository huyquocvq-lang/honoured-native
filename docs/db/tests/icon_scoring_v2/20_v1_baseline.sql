\set ON_ERROR_STOP on
-- v1 as deployed: a stamped day is frozen. Read-only for stamped days, so the
-- v2 run below starts from the seeded state.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('v1 lists pending days only', public.t_measure_names(), 'P1,P2');
select public.t_eq('v1 skips a later reading of a HONOURED day', public.t_report('A', 15000)->>'skipped', '1');
select public.t_eq('v1 keeps the first-stamp total', (public.t_get('A')).measured_value, 10183::float8);
select public.t_eq('v1 skips a late full total of a BROKEN day', public.t_report('B', 10500)->>'skipped', '1');
select public.t_eq('v1 leaves the BROKEN day broken', (public.t_get('B')).status, 'broken');
reset role;

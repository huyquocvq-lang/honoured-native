\set ON_ERROR_STOP on
-- After the rollback file: v1 behaviour again, v2's raised values kept.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('rollback lists pending days only', coalesce(public.t_measure_names(), ''), '');
select public.t_eq('rollback skips stamped days again', public.t_report('A', 20000)->>'skipped', '1');
select public.t_eq('rollback keeps v2 totals', (public.t_get('A')).measured_value, 16000::float8);
select public.t_eq('rollback returns the v1 keys', (select string_agg(k, ',' order by k) from jsonb_object_keys(public.record_icon_measurements('[]'::jsonb)) k), 'broken,honoured,pending,skipped');
reset role;

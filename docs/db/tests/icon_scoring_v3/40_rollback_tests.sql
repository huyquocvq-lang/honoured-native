\set ON_ERROR_STOP on
-- After the rollback file: v2 behaviour again, the totals v3 wrote kept.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('rollback removes measured_source',
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'icon_days' and column_name = 'measured_source'),
  false);
select public.t_eq('rollback keeps v3 totals', (public.t_get('A')).measured_value, 6000::float8);
select public.t_eq('rollback ignores the source: a lower total is unchanged', public.t_report_src('A', 5000, 'core_motion')->>'unchanged', '1');
select public.t_eq('rollback still raises', public.t_report_src('A', 7000, 'healthkit')->>'updated', '1');
select public.t_eq('rollback returns the v2 keys',
  (select string_agg(k, ',' order by k) from jsonb_object_keys(public.record_icon_measurements('[]'::jsonb)) k),
  'broken,honoured,pending,skipped,unchanged,updated');
reset role;

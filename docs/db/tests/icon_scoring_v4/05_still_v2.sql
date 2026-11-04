\set ON_ERROR_STOP on
-- A refused v4 changed nothing: still no measured_source, still the v2 body.
select public.t_eq('a refused v4 adds no column',
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'icon_days' and column_name = 'measured_source'),
  false);
select public.t_eq('a refused v4 leaves the v2 function',
  position('healthkit_iphone' in pg_get_functiondef('public.record_icon_measurements(jsonb)'::regprocedure)), 0);

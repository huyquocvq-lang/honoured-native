\set ON_ERROR_STOP on
select public.t_eq('a refused v3 adds no column',
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'icon_days' and column_name = 'measured_source'),
  false);

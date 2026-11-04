\set ON_ERROR_STOP on
select public.t_eq('rollback removes the table', to_regclass('public.goal_diagnostics') is null, true);
select public.t_eq('rollback removes the functions',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('record_goal_diagnostics', 'goal_diagnostics_timeline', 'purge_goal_diagnostics')),
  0::bigint);

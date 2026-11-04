-- Rollback of goal_diagnostics_v1.sql: removes the diagnostics table and its
-- functions, and with them every line uploaded so far. Builds that still
-- upload get an error from record_goal_diagnostics and keep their lines on
-- the device.
begin;

drop function if exists public.purge_goal_diagnostics(interval);
drop function if exists public.goal_diagnostics_timeline(date, date);
drop function if exists public.record_goal_diagnostics(jsonb);
drop table if exists public.goal_diagnostics;

commit;

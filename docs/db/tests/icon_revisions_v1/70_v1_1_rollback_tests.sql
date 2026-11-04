\set ON_ERROR_STOP on
-- After icon_revisions_v1_1_rollback.sql: the v1 bodies as deployed on
-- 28 Oct 2026, TRUNCATE as v1 granted it, and every revision kept.
select public.t_eq('v1.1 rollback: ' || p.proname || ' is v1 again', md5(pg_get_functiondef(p.oid)), x.md5)
from (values
  ('icon_revisions_immutable', '401d66db9cbb67bd4d8adffcf6354af6'),
  ('revise_icon_target', '80e9f0d165569ca31303b173280af22e')
) as x(proname, md5)
join pg_proc p on p.proname = x.proname and p.pronamespace = 'public'::regnamespace
order by p.proname;
select public.t_eq('v1.1 rollback: the TRUNCATE trigger is gone',
  (select count(*) from pg_trigger where tgname = 'icon_revisions_no_truncate'), 0::bigint);
select public.t_eq('v1.1 rollback: service_role holds TRUNCATE again',
  has_table_privilege('service_role', 'public.icon_revisions', 'truncate'), true);
select public.t_eq('v1.1 rollback: the revisions are kept',
  (select count(*) from public.icon_revisions) - (select count(*) from public.t_revisions_before), 0::bigint);
select public.t_eq('v1.1 rollback: the per-day targets are kept',
  (select count(*) from public.icon_days where target_revision > 0) > 0, true);

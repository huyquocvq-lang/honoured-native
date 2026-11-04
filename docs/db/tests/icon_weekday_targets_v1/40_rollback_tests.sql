\set ON_ERROR_STOP on
-- After icon_weekday_targets_v1_rollback.sql: production's guard and push
-- facts, icon_revisions_v1.sql's day trigger, no weekday revision, and every
-- Icon day still on the target it held.
select public.t_eq('rollback: ' || p.proname || ' is back', md5(pg_get_functiondef(p.oid)), x.md5)
from (values
  ('contracts_icon_guard', '05d2aad1b81f327fe38fe69dfcbe2ec6'),
  ('contracts_icon_days', 'bc7b184a1d698d49ca70dfe3dbf5f9dc'),
  ('icon_push_facts', '3d396c2e252e2793768c9a73e02a7fdb'),
  ('revise_icon_target', 'aca7ea9cee15c372aa2f0c9b9787f280')
) as x(proname, md5)
join pg_proc p on p.proname = x.proname and p.pronamespace = 'public'::regnamespace
order by p.proname;
select public.t_eq('rollback: revise_icon_targets is gone',
  to_regprocedure('public.revise_icon_targets(uuid, uuid, jsonb, text)') is null, true);
select public.t_eq('rollback: the new columns are gone',
  (select count(*) from information_schema.columns where table_schema = 'public'
     and ((table_name = 'contracts' and column_name = 'icon_day_targets')
          or (table_name = 'icon_revisions' and column_name = 'changes'))), 0::bigint);
select public.t_eq('rollback: the revisions stay',
  (select count(*) from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000021'), 5::bigint);
select public.t_eq('rollback: days keep the targets they held',
  public.t_state('21', public.t_today('UTC') + 7) || ' ' || public.t_state('21', public.t_today('UTC')),
  'pending/15000 steps/15000/4 pending/' || (4000 + public.t_dow('UTC', 0)::integer * 1000)::text || ' steps/'
    || (4000 + public.t_dow('UTC', 0)::integer * 1000)::text || '/0');
select set_config('request.jwt.claim.sub', 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', false);
set role authenticated;
select public.t_eq('rollback: an every-day revision still works',
  public.t_rev('21', '8', 17000, 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1/client-21/revisions/w6.png')->>'revision', '6');
reset role;

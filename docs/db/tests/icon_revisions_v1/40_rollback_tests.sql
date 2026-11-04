\set ON_ERROR_STOP on
-- After icon_revisions_v1_rollback.sql: production's bodies, no revisions,
-- no per-day targets, and new Icons still get their days.
select public.t_eq('rollback: ' || p.proname || ' is production''s again', md5(pg_get_functiondef(p.oid)), x.md5)
from (values
  ('contracts_icon_days', 'ba8878e4a12694e58e557769d5dd72b0'),
  ('icon_days_to_measure', 'b0df75c43f218c843a61fe4efb1ffe25'),
  ('icon_push_jobs', 'd0763dedd128fb9dbda8f759bb8f267d'),
  ('record_icon_measurements', '3e443e4f5a8ae4c80be38ce30c33e73a')
) as x(proname, md5)
join pg_proc p on p.proname = x.proname and p.pronamespace = 'public'::regnamespace
order by p.proname;
select public.t_eq('rollback: revise_icon_target is gone', to_regprocedure('public.revise_icon_target(uuid, uuid, numeric, text)') is null, true);
select public.t_eq('rollback: icon_revisions_immutable is gone', to_regprocedure('public.icon_revisions_immutable()') is null, true);
select public.t_eq('rollback: icon_revisions is gone', to_regclass('public.icon_revisions') is null, true);
select public.t_eq('rollback: the per-day target columns are gone',
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'icon_days'
     and column_name in ('target_text', 'target_value', 'target_revision')), 0::bigint);
select public.t_eq('rollback: the per-day constraints are gone',
  (select count(*) from pg_constraint where conrelid = 'public.icon_days'::regclass
     and conname in ('icon_days_target_value_positive', 'icon_days_target_revision_nonnegative')), 0::bigint);

insert into auth.users (id) values ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd');
select public.t_sign('11', 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd', 'UTC', 0, 1, 'week', '4000 steps', 'steps', 4000, 'count');
select public.t_eq('rollback: a new Icon still gets its days',
  (select count(*) from public.icon_days where contract_id = 'aaaaaaaa-0000-0000-0000-000000000011'), 7::bigint);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('rollback: A today is measured against the signed target',
  (select target from public.icon_days_to_measure()
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and day = (now() at time zone 'Europe/London')::date),
  10000::double precision);
reset role;

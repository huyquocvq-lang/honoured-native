\set ON_ERROR_STOP on
-- After icon_scoring_v4_rollback.sql: the v3 function and constraint, totals
-- kept, iPhone labels folded into healthkit.
select public.t_eq('rollback restores the v3 function',
  md5(pg_get_functiondef('public.record_icon_measurements(jsonb)'::regprocedure)), :'v3_md5');
select public.t_eq('no healthkit_iphone label is left',
  (select count(*) from public.icon_days where measured_source = 'healthkit_iphone'), 0::bigint);
select public.t_eq('B keeps its total, labelled healthkit', public.t_state('B'), 'honoured/target_met/9000/healthkit');
select public.t_eq('G keeps its total, labelled healthkit', public.t_state('G'), 'honoured/target_met/9000/healthkit');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('an iPhone reading is skipped again', public.t_report_src('A', 9000, 'healthkit_iphone')->>'skipped', '1');
select public.t_eq('Core Motion still replaces after the rollback', public.t_report_src('A', 7000, 'core_motion')->>'updated', '1');
reset role;

do $$
begin
  update public.icon_days set measured_source = 'healthkit_iphone'
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and status = 'honoured';
  raise exception 'FAIL the v3 constraint took healthkit_iphone';
exception when check_violation then
  raise notice 'ok  the v3 constraint is back';
end $$;

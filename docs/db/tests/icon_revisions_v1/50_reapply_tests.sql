\set ON_ERROR_STOP on
-- icon_revisions_v1.sql again after its rollback: every day back on its
-- signed target, and revising works.
select public.t_eq('re-apply: every day carries its signed target',
  (select count(*) from public.icon_days d join public.contracts c on c.id = d.contract_id
   where (d.target_text, d.target_value, d.target_revision) is distinct from (c.primary_target, c.icon_target, 0)), 0::bigint);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('re-apply: A can be revised again, starting at revision 1',
  public.t_rev('1', '5', 11000, '11111111-1111-1111-1111-111111111111/client-1/revisions/r3.png')->>'revision', '1');
reset role;

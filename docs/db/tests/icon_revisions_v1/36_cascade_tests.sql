\set ON_ERROR_STOP on
-- A revision goes with its contract (Reset everything) or its account.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
set role authenticated;
delete from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000003';
reset role;
select public.t_eq('deleting C removes its revision',
  (select count(*) from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000003'), 0::bigint);
delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
select public.t_eq('deleting B''s account removes its revisions',
  (select count(*) from public.icon_revisions where user_id = '22222222-2222-2222-2222-222222222222'), 0::bigint);
select public.t_eq('the other revisions stay',
  (select count(*) from public.icon_revisions), 5::bigint);

\set ON_ERROR_STOP on
-- After icon_revisions_v1_1.sql, 30_tests.sql and 36_cascade_tests.sql, on
-- the extra Icons of 60_v1_1_seed.sql, with Supabase's default privileges
-- (05_supabase_defaults.sql).

select public.t_eq('v1.1: today is read after the row lock',
  position('clock_timestamp()' in pg_get_functiondef('public.revise_icon_target(uuid, uuid, numeric, text)'::regprocedure)) > 0,
  true);

------------------------------------------------------------------------------
-- Units the v1 checks did not cover, against target-units.ts.
select set_config('request.jwt.claim.sub', 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1', false);
set role authenticated;
select public.t_eq('mi: above 30 is refused',
  public.t_rev('13', '1', 30.1, 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1/client-13/revisions/r1.png')->>'reason', 'invalid_target');
select public.t_eq('mi: two decimals are refused',
  public.t_rev('13', '1', 4.55, 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1/client-13/revisions/r1.png')->>'reason', 'invalid_target');
select public.t_eq('mi: 4.5 is kept in meters in the signed proportion',
  (select concat_ws('/', r->>'targetText', r->>'targetValue')
   from (select public.t_rev('13', '1', 4.5, 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1/client-13/revisions/r1.png') r) x),
  '4.5 mi/7242.048');
reset role;

select set_config('request.jwt.claim.sub', 'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2', false);
set role authenticated;
select public.t_eq('min: above 120 is refused',
  public.t_rev('14', '1', 121, 'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2/client-14/revisions/r1.png')->>'reason', 'invalid_target');
select public.t_eq('min: 120 is the maximum',
  (select concat_ws('/', r->>'targetText', r->>'targetValue')
   from (select public.t_rev('14', '1', 120, 'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2/client-14/revisions/r1.png') r) x),
  '120 min/120');
reset role;

select set_config('request.jwt.claim.sub', 'd3d3d3d3-d3d3-d3d3-d3d3-d3d3d3d3d3d3', false);
set role authenticated;
select public.t_eq('hrs: above 24 is refused',
  public.t_rev('15', '1', 25, 'd3d3d3d3-d3d3-d3d3-d3d3-d3d3d3d3d3d3/client-15/revisions/r1.png')->>'reason', 'invalid_target');
select public.t_eq('hrs: a self-reported Icon gets a text target and no value',
  (select concat_ws('/', r->>'targetText', coalesce(r->>'targetValue', 'null'))
   from (select public.t_rev('15', '1', 3, 'd3d3d3d3-d3d3-d3d3-d3d3-d3d3d3d3d3d3/client-15/revisions/r1.png') r) x),
  '3 hrs/null');
reset role;

select set_config('request.jwt.claim.sub', 'd4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4', false);
set role authenticated;
select public.t_eq('kcal: above 2000 is refused',
  public.t_rev('16', '1', 2001, 'd4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4/client-16/revisions/r1.png')->>'reason', 'invalid_target');
select public.t_eq('kcal: 2000 is the maximum',
  (select concat_ws('/', r->>'targetText', r->>'targetValue')
   from (select public.t_rev('16', '1', 2000, 'd4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4/client-16/revisions/r1.png') r) x),
  '2000 kcal/2000');
reset role;

------------------------------------------------------------------------------
-- The signature belongs to this Icon's revisions folder and to the caller.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('v1.1: a file in another of my Icons'' folders is refused',
  public.t_rev('1', '20', 9100, '11111111-1111-1111-1111-111111111111/client-12/revisions/x1.png')->>'reason', 'invalid_signature');
select public.t_eq('v1.1: a file outside the revisions folder is refused',
  public.t_rev('1', '20', 9100, '11111111-1111-1111-1111-111111111111/client-1/x1.png')->>'reason', 'invalid_signature');
select public.t_eq('v1.1: a file in a folder below it is refused',
  public.t_rev('1', '20', 9100, '11111111-1111-1111-1111-111111111111/client-1/revisions/a/x1.png')->>'reason', 'invalid_signature');
select public.t_eq('v1.1: a file someone else uploaded to my folder does not count',
  public.t_rev('1', '20', 9100, '11111111-1111-1111-1111-111111111111/client-1/revisions/foreign.png')->>'reason', 'signature_missing');
select public.t_eq('v1.1: none of those made a revision',
  (select count(*) from public.icon_revisions where request_id = 'cccccccc-0000-0000-0000-000000000020'), 0::bigint);

-- Each owner sees only their own revisions, while others exist.
select public.t_eq('v1.1: A sees none of the other people''s revisions',
  (select count(*) from public.icon_revisions where user_id <> '11111111-1111-1111-1111-111111111111'), 0::bigint);
reset role;
select public.t_eq('v1.1: (other people''s revisions exist)',
  (select count(*) > 0 from public.icon_revisions where user_id <> '11111111-1111-1111-1111-111111111111'), true);

------------------------------------------------------------------------------
-- Supabase grants every new table and function to anon: the migrations take
-- it back.
set role anon;
do $$
begin
  perform public.revise_icon_target('aaaaaaaa-0000-0000-0000-000000000001', gen_random_uuid(), 12000,
    '11111111-1111-1111-1111-111111111111/client-1/revisions/r1.png');
  raise exception 'FAIL anon revised an Icon';
exception when insufficient_privilege then
  raise notice 'ok  v1.1: anon cannot call revise_icon_target despite the default grant';
end $$;
do $$
begin
  perform 1 from public.icon_revisions limit 1;
  raise exception 'FAIL anon read the revisions';
exception when insufficient_privilege then
  raise notice 'ok  v1.1: anon cannot read icon_revisions despite the default grant';
end $$;
reset role;
select public.t_eq('v1.1: authenticated holds only SELECT on icon_revisions',
  (select string_agg(p, ',' order by p) from unnest(array['select', 'insert', 'update', 'delete', 'truncate']) p
   where has_table_privilege('authenticated', 'public.icon_revisions', p)), 'select');

------------------------------------------------------------------------------
-- History cannot be truncated, and a nested delete is not a cascade.
set role service_role;
do $$
begin
  truncate public.icon_revisions;
  raise exception 'FAIL service_role truncated the history';
exception when insufficient_privilege then
  if sqlerrm not like 'permission denied%' then raise; end if;
  raise notice 'ok  v1.1: service_role cannot truncate icon_revisions';
end $$;
reset role;
do $$
begin
  truncate public.icon_revisions;
  raise exception 'FAIL the table owner truncated the history';
exception when insufficient_privilege then
  if sqlerrm not like 'Icon revisions cannot%' then raise; end if;
  raise notice 'ok  v1.1: not even the table owner can truncate icon_revisions';
end $$;

create table public.t_nested (id integer);
create function public.t_nested_delete() returns trigger language plpgsql as $$
begin
  delete from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  return null;
end $$;
create trigger t_nested after insert on public.t_nested for each row execute function public.t_nested_delete();
do $$
begin
  insert into public.t_nested values (1);
  raise exception 'FAIL a delete from another trigger removed a revision';
exception when insufficient_privilege then
  if sqlerrm not like 'Icon revisions cannot%' then raise; end if;
  raise notice 'ok  v1.1: a delete from another trigger is refused while the contract exists';
end $$;
drop table public.t_nested;
drop function public.t_nested_delete();

-- The cascades still work (36_cascade_tests.sql ran on v1.1 too): M's
-- account, and L through its contract.
delete from auth.users where id = 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1';
select public.t_eq('v1.1: deleting an account still removes its revisions',
  (select count(*) from public.icon_revisions where user_id = 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1'), 0::bigint);
select set_config('request.jwt.claim.sub', 'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2', false);
set role authenticated;
delete from public.contracts where id = 'aaaaaaaa-0000-0000-0000-000000000014';
reset role;
select public.t_eq('v1.1: deleting a contract (Reset everything) still removes its revisions',
  (select count(*) from public.icon_revisions where contract_id = 'aaaaaaaa-0000-0000-0000-000000000014'), 0::bigint);

-- For 70_v1_1_rollback_tests.sql: the revisions before the v1.1 rollback.
create table public.t_revisions_before as select id from public.icon_revisions;

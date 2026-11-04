\set ON_ERROR_STOP on
-- icon_weekday_targets_v1.sql again after its rollback: signing with weekday
-- targets and revising weekdays work again.
insert into auth.users (id) values ('e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9');
insert into storage.objects (bucket_id, name, owner, owner_id) values
  ('signatures', 'e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9/client-29/revisions/w1.png',
   'e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9', 'e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9');
select public.t_sign_targets('29', 'e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9', 'UTC', 0, 1, 'week',
  '3000 steps', 'steps', 3000, 'count', '{1,2,3,4,5,6,7}',
  (select jsonb_object_agg(d::text, (2000 + d * 1000)::text || ' steps') from generate_series(1, 7) d));
select public.t_eq('re-apply: a new Icon starts on its weekday targets',
  public.t_state('29', public.t_today('UTC') + 1),
  'pending/' || (2000 + public.t_dow('UTC', 1)::integer * 1000)::text || ' steps/'
    || (2000 + public.t_dow('UTC', 1)::integer * 1000)::text || '/0');
select set_config('request.jwt.claim.sub', 'e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9', false);
set role authenticated;
select public.t_eq('re-apply: a weekday revision works',
  public.t_revs('29', '1', jsonb_build_object(public.t_dow('UTC', 1), 20000),
    'e9e9e9e9-e9e9-e9e9-e9e9-e9e9e9e9e9e9/client-29/revisions/w1.png')->>'targetText', '20000 steps');
reset role;

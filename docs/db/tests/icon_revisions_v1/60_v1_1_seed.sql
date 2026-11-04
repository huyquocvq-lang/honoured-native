-- Extra Icons for the icon_revisions_v1_1.sql checks, before the migrations:
-- A's next Icon after this one (L), one Icon per remaining unit (M: mi, N: min, O: hrs,
-- P: kcal) and a file in A's revisions folder that someone else uploaded.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('d1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1'),
  ('d2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2'),
  ('d3d3d3d3-d3d3-d3d3-d3d3-d3d3d3d3d3d3'),
  ('d4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4');

select public.t_sign('12', '11111111-1111-1111-1111-111111111111', 'UTC', 30, 1, 'week', '5000 steps', 'steps', 5000, 'count');
select public.t_sign('13', 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1', 'UTC', 0, 1, 'week', '3 mi', 'distance_walking_running', 4828.032, 'meters');
select public.t_sign('14', 'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2', 'UTC', 0, 1, 'week', '30 min', 'exercise_minutes', 30, 'minutes');
select public.t_sign('15', 'd3d3d3d3-d3d3-d3d3-d3d3-d3d3d3d3d3d3', 'UTC', 0, 1, 'week', '2 hrs', null, null, null);
select public.t_sign('16', 'd4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4', 'UTC', 0, 1, 'week', '500 kcal', 'active_energy', 500, 'kcal');

insert into storage.objects (bucket_id, name, owner, owner_id)
select 'signatures', p, split_part(p, '/', 1)::uuid, split_part(p, '/', 1) from unnest(array[
  '11111111-1111-1111-1111-111111111111/client-12/revisions/x1.png',
  '11111111-1111-1111-1111-111111111111/client-1/x1.png',
  '11111111-1111-1111-1111-111111111111/client-1/revisions/a/x1.png',
  'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1/client-13/revisions/r1.png',
  'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2/client-14/revisions/r1.png',
  'd3d3d3d3-d3d3-d3d3-d3d3-d3d3d3d3d3d3/client-15/revisions/r1.png',
  'd4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4/client-16/revisions/r1.png'
]) p;
-- In A's folder, but uploaded by someone else.
insert into storage.objects (bucket_id, name, owner, owner_id) values
  ('signatures', '11111111-1111-1111-1111-111111111111/client-1/revisions/foreign.png',
   'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1', 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1');

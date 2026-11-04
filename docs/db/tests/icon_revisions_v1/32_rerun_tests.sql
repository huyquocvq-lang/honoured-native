\set ON_ERROR_STOP on
-- icon_revisions_v1.sql run again after revisions: nothing moves.
select public.t_eq('re-run: A tomorrow keeps its revision',
  public.t_state('1', public.t_today('Europe/London') + 1), 'pending/8000 steps/8000/2');
select public.t_eq('re-run: A today keeps the signed target',
  public.t_state('1', public.t_today('Europe/London')), 'pending/10000 steps/10000/0');
select public.t_eq('re-run: the history is intact',
  (select count(*) from public.icon_revisions), 8::bigint);

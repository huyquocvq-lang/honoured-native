\set ON_ERROR_STOP on
-- One reading with an explicit source; a null source sends JSON null.
create function public.t_report_src(p_name text, p_value float8, p_source text, p_through timestamptz default null)
returns jsonb language sql volatile as $$
  select public.record_icon_measurements(jsonb_build_array(
    public.t_row(p_name, p_value, p_through) || jsonb_build_object('source', p_source)))
$$;
grant execute on function public.t_report_src(text, float8, text, timestamptz) to authenticated;
create function public.t_state(p_name text) returns text
language sql stable as $$
  select (public.t_get(p_name)).status || '/' || coalesce((public.t_get(p_name)).resolution, '-') || '/'
      || coalesce((public.t_get(p_name)).measured_value::text, '-') || '/' || coalesce((public.t_get(p_name)).measured_source, '-')
$$;
grant execute on function public.t_state(text) to authenticated;

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;

-- A: today's HONOURED day, 10,183 from before v3 (no source = HealthKit).
-- The person reads Automatic, then switches to iPhone and back.
create temp table a_before as select scored_at from public.t_get('A');
select public.t_eq('A Automatic raises', public.t_report_src('A', 12000, 'healthkit')->>'updated', '1');
select public.t_eq('A switch to iPhone replaces with a lower total', public.t_report_src('A', 7000, 'healthkit_iphone')->>'updated', '1');
select public.t_eq('A shows the iPhone total and stays honoured', public.t_state('A'), 'honoured/target_met/7000/healthkit_iphone');
select public.t_eq('A keeps scored_at', (public.t_get('A')).scored_at, (select scored_at from a_before));
select public.t_eq('A lower iPhone total is unchanged', public.t_report_src('A', 6500, 'healthkit_iphone')->>'unchanged', '1');
select public.t_eq('A higher iPhone total raises', public.t_report_src('A', 8000, 'healthkit_iphone')->>'updated', '1');
select public.t_eq('A back to Automatic replaces with a lower total', public.t_report_src('A', 7500, 'healthkit')->>'updated', '1');
select public.t_eq('A shows the Automatic total', public.t_state('A'), 'honoured/target_met/7500/healthkit');
select public.t_eq('A same total from iPhone is unchanged', public.t_report_src('A', 7500, 'healthkit_iphone')->>'unchanged', '1');
select public.t_eq('A only its label moved', (public.t_get('A')).measured_source, 'healthkit_iphone');
select public.t_eq('A a row without source counts as Automatic and replaces', public.t_report('A', 7400)->>'updated', '1');
select public.t_eq('A labelled healthkit again', public.t_state('A'), 'honoured/target_met/7400/healthkit');

-- B: BROKEN at 8,286 from HealthKit; the iPhone total is lower, then meets
-- the target; Automatic below the target never takes HONOURED away.
select public.t_eq('B lower iPhone total replaces', public.t_report_src('B', 7000, 'healthkit_iphone')->>'updated', '1');
select public.t_eq('B still broken with the iPhone total', public.t_state('B'), 'broken/target_missed/7000/healthkit_iphone');
select public.t_eq('B iPhone at the target honours', public.t_report_src('B', 10000, 'healthkit_iphone')->>'honoured', '1');
select public.t_eq('B honoured from the iPhone', public.t_state('B'), 'honoured/target_met/10000/healthkit_iphone');
select public.t_eq('B lower Automatic total replaces the number only', public.t_report_src('B', 9000, 'healthkit')->>'updated', '1');
select public.t_eq('B never goes back to broken', public.t_state('B'), 'honoured/target_met/9000/healthkit');

-- C: BROKEN with no data gets an iPhone reading below the target.
select public.t_eq('C iPhone reading counts', public.t_report_src('C', 4000, 'healthkit_iphone')->>'updated', '1');
select public.t_eq('C target_missed from the iPhone', public.t_state('C'), 'broken/target_missed/4000/healthkit_iphone');

-- G: HONOURED 10 days ago at 12,000; Core Motion still replaces as in v3.
select public.t_eq('G Core Motion still replaces', public.t_report_src('G', 11000, 'core_motion')->>'updated', '1');
select public.t_eq('G iPhone replaces Core Motion', public.t_report_src('G', 9000, 'healthkit_iphone')->>'updated', '1');
select public.t_eq('G stays honoured', public.t_state('G'), 'honoured/target_met/9000/healthkit_iphone');

-- Pending days take every reading and record its source.
select public.t_eq('P1 iPhone partial stays pending', public.t_report_src('P1', 5000, 'healthkit_iphone')->>'pending', '1');
select public.t_eq('P1 pending from the iPhone', public.t_state('P1'), 'pending/-/5000/healthkit_iphone');
select public.t_eq('P1 Automatic partial replaces it', public.t_report_src('P1', 4000, 'healthkit')->>'pending', '1');
select public.t_eq('P1 iPhone at the target honours', public.t_report_src('P1', 10001, 'healthkit_iphone')->>'honoured', '1');
select public.t_eq('P1 honoured from the iPhone', public.t_state('P1'), 'honoured/target_met/10001/healthkit_iphone');
select public.t_eq('P2 full iPhone reading breaks after the settle hour',
  public.t_report_src('P2', 3000, 'healthkit_iphone', (select deadline_at from public.t_get('P2')))->>'broken', '1');

-- Still skipped: unknown sources, foreign, closed and out-of-window days.
select public.t_eq('an unknown source is skipped', public.t_report_src('A', 9999, 'garmin')->>'skipped', '1');
select public.t_eq('A untouched by the unknown source', (public.t_get('A')).measured_value, 7400::float8);
select public.t_eq('a foreign day is skipped', public.t_report_src('O', 1, 'healthkit_iphone')->>'skipped', '1');
select public.t_eq('an early-exit day is skipped', public.t_report_src('AM', 15000, 'healthkit_iphone')->>'skipped', '1');
select public.t_eq('a day past 30 days is skipped', public.t_report_src('E', 15000, 'healthkit_iphone')->>'skipped', '1');
select public.t_eq('the summary keys are v3''s',
  (select string_agg(k, ',' order by k) from jsonb_object_keys(public.record_icon_measurements('[]'::jsonb)) k),
  'broken,honoured,pending,skipped,unchanged,updated');
reset role;

-- The table refuses any other label.
do $$
begin
  update public.icon_days set measured_source = 'apple_watch'
   where contract_id = 'aaaaaaaa-0000-0000-0000-000000000001' and status = 'honoured';
  raise exception 'FAIL an unknown label was stored';
exception when check_violation then
  raise notice 'ok  the constraint refuses unknown labels';
end $$;

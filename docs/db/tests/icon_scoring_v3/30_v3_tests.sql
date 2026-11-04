\set ON_ERROR_STOP on
-- One reading with an explicit source; a null source sends JSON null.
create function public.t_report_src(p_name text, p_value float8, p_source text, p_through timestamptz default null)
returns jsonb language sql volatile as $$
  select public.record_icon_measurements(jsonb_build_array(
    public.t_row(p_name, p_value, p_through) || jsonb_build_object('source', p_source)))
$$;
grant execute on function public.t_report_src(text, float8, text, timestamptz) to authenticated;

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;

-- Totals recorded before v3 carry no source and count as HealthKit.
select public.t_eq('seeded days have no source yet', (public.t_get('A')).measured_source, null::text);

-- A: today's HONOURED day at 10,183 from HealthKit.
create temp table a_before as select scored_at from public.t_get('A');
select public.t_eq('A higher HealthKit total raises', public.t_report_src('A', 15000, 'healthkit')->>'updated', '1');
select public.t_eq('A labelled healthkit', (public.t_get('A')).measured_source, 'healthkit');
select public.t_eq('A lower HealthKit total is unchanged', public.t_report_src('A', 14000, 'healthkit')->>'unchanged', '1');
select public.t_eq('A a row without source counts as HealthKit', public.t_report('A', 14000)->>'unchanged', '1');
select public.t_eq('A Core Motion total replaces it, lower too', public.t_report_src('A', 11000, 'core_motion')->>'updated', '1');
select public.t_eq('A shows the Core Motion total', (public.t_get('A')).measured_value || '/' || (public.t_get('A')).measured_source, '11000/core_motion');
select public.t_eq('A stays honoured', (public.t_get('A')).status || '/' || (public.t_get('A')).resolution, 'honoured/target_met');
select public.t_eq('A keeps scored_at', (public.t_get('A')).scored_at, (select scored_at from a_before));
select public.t_eq('A lower Core Motion total is unchanged', public.t_report_src('A', 10500, 'core_motion')->>'unchanged', '1');
select public.t_eq('A higher Core Motion total raises', public.t_report_src('A', 12000, 'core_motion')->>'updated', '1');
select public.t_eq('A HealthKit total below the target replaces', public.t_report_src('A', 6000, 'healthkit')->>'updated', '1');
select public.t_eq('A HONOURED survives a total below the target', (public.t_get('A')).status || '/' || (public.t_get('A')).measured_value, 'honoured/6000');
select public.t_eq('A same total from the other source is unchanged', public.t_report_src('A', 6000, 'core_motion')->>'unchanged', '1');
select public.t_eq('A only its label moved', (public.t_get('A')).measured_source, 'core_motion');

-- B: BROKEN at 8,286 from HealthKit.
select public.t_eq('B lower Core Motion total replaces', public.t_report_src('B', 7000, 'core_motion')->>'updated', '1');
select public.t_eq('B still broken with the Core Motion total',
  (public.t_get('B')).status || '/' || (public.t_get('B')).measured_value || '/' || (public.t_get('B')).measured_source, 'broken/7000/core_motion');
select public.t_eq('B Core Motion at the target honours', public.t_report_src('B', 10000, 'core_motion')->>'honoured', '1');
select public.t_eq('B honoured from core_motion',
  (public.t_get('B')).status || '/' || (public.t_get('B')).resolution || '/' || (public.t_get('B')).measured_source, 'honoured/target_met/core_motion');
select public.t_eq('B lower HealthKit total replaces the number only', public.t_report_src('B', 9000, 'healthkit')->>'updated', '1');
select public.t_eq('B never goes back to broken', (public.t_get('B')).status || '/' || (public.t_get('B')).measured_value, 'honoured/9000');

-- C: BROKEN with no data gets a Core Motion reading below the target.
select public.t_eq('C Core Motion reading counts', public.t_report_src('C', 4000, 'core_motion')->>'updated', '1');
select public.t_eq('C target_missed from core_motion',
  (public.t_get('C')).status || '/' || (public.t_get('C')).resolution || '/' || (public.t_get('C')).measured_source, 'broken/target_missed/core_motion');

-- D: BROKEN with no data, HealthKit meets the target late (v2's rule).
select public.t_eq('D HealthKit at the target honours', public.t_report_src('D', 12000, 'healthkit')->>'honoured', '1');
select public.t_eq('D labelled healthkit', (public.t_get('D')).measured_source, 'healthkit');

-- Pending days take every reading, as before, and record its source.
select public.t_eq('P1 Core Motion partial stays pending', public.t_report_src('P1', 5000, 'core_motion')->>'pending', '1');
select public.t_eq('P1 pending from core_motion', (public.t_get('P1')).measured_value || '/' || (public.t_get('P1')).measured_source, '5000/core_motion');
select public.t_eq('P1 HealthKit partial replaces it', public.t_report_src('P1', 4000, 'healthkit')->>'pending', '1');
select public.t_eq('P1 pending from healthkit', (public.t_get('P1')).measured_value || '/' || (public.t_get('P1')).measured_source, '4000/healthkit');
select public.t_eq('P1 Core Motion at the target honours', public.t_report_src('P1', 10001, 'core_motion')->>'honoured', '1');
select public.t_eq('P1 honoured from core_motion', (public.t_get('P1')).status || '/' || (public.t_get('P1')).measured_source, 'honoured/core_motion');
select public.t_eq('P2 full Core Motion reading breaks after the settle hour',
  public.t_report_src('P2', 3000, 'core_motion', (select deadline_at from public.t_get('P2')))->>'broken', '1');
select public.t_eq('P2 broken from core_motion', (public.t_get('P2')).status || '/' || (public.t_get('P2')).measured_source, 'broken/core_motion');

-- Rows that cannot be trusted are skipped, never an error.
select public.t_eq('unknown source skipped', public.t_report_src('G', 20000, 'garmin')->>'skipped', '1');
select public.t_eq('G untouched by it', (public.t_get('G')).measured_value, 12000::float8);
select public.t_eq('JSON null source counts as HealthKit', public.t_report_src('G', 13000, null)->>'updated', '1');
select public.t_eq('G labelled healthkit', (public.t_get('G')).measured_source, 'healthkit');
select public.t_eq('E outside the window skipped whatever the source', public.t_report_src('E', 20000, 'core_motion')->>'skipped', '1');
select public.t_eq('O foreign day skipped', public.t_report_src('O', 20000, 'core_motion')->>'skipped', '1');
select public.t_eq('S self-reported day skipped', public.t_report_src('S', 20000, 'core_motion')->>'skipped', '1');

-- One batch mixing sources.
create temp table batch as select public.record_icon_measurements(jsonb_build_array(
    public.t_row('H', 8000) || '{"source": "core_motion"}'::jsonb,
    public.t_row('G', 12500) || '{"source": "healthkit"}'::jsonb,
    public.t_row('G', 1) || '{"source": "fitbit"}'::jsonb
  )) as r;
select public.t_eq('mixed batch counts', (select r from batch),
  '{"broken": 0, "pending": 0, "skipped": 1, "updated": 1, "honoured": 0, "unchanged": 1}'::jsonb);
select public.t_eq('H replaced by core_motion', (public.t_get('H')).measured_value || '/' || (public.t_get('H')).measured_source, '8000/core_motion');
reset role;

-- The column takes the two sources only.
do $$
begin
  update public.icon_days set measured_source = 'garmin'
  where (contract_id, day) in (select contract_id, day from public.t_days where name = 'A');
  raise exception 'FAIL an unknown source was stored';
exception when check_violation then
  raise notice 'ok  the column refuses an unknown source';
end $$;

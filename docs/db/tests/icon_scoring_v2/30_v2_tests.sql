\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;

-- What the device is asked to read.
select public.t_eq('lists pending in 24 h and stamped-from-readings in 30 days',
  public.t_measure_names(), 'A,B,C,D,G,H,P1,P2');

-- A: today's HONOURED day keeps growing; status and scored_at stay.
create temp table a_before as select scored_at from public.t_get('A');
select public.t_eq('A higher reading counts as updated', public.t_report('A', 15000)->>'updated', '1');
select public.t_eq('A total raised', (public.t_get('A')).measured_value, 15000::float8);
select public.t_eq('A stays honoured', (public.t_get('A')).status, 'honoured');
select public.t_eq('A keeps target_met', (public.t_get('A')).resolution, 'target_met');
select public.t_eq('A keeps scored_at', (public.t_get('A')).scored_at, (select scored_at from a_before));
select public.t_eq('A lower reading is unchanged', public.t_report('A', 12000)->>'unchanged', '1');
select public.t_eq('A total never drops', (public.t_get('A')).measured_value, 15000::float8);
select public.t_eq('A equal reading is unchanged', public.t_report('A', 15000)->>'unchanged', '1');

-- B: BROKEN 8,286 (the 3 Oct case): a higher total below target is kept,
-- then a total at the target turns the day HONOURED.
create temp table b_before as select scored_at from public.t_get('B');
select public.t_eq('B below target counts as updated', public.t_report('B', 9000)->>'updated', '1');
select public.t_eq('B still broken', (public.t_get('B')).status, 'broken');
select public.t_eq('B keeps target_missed', (public.t_get('B')).resolution, 'target_missed');
select public.t_eq('B total raised', (public.t_get('B')).measured_value, 9000::float8);
select public.t_eq('B at target turns honoured', public.t_report('B', 10000)->>'honoured', '1');
select public.t_eq('B now honoured', (public.t_get('B')).status, 'honoured');
select public.t_eq('B now target_met', (public.t_get('B')).resolution, 'target_met');
select public.t_eq('B total is the late reading', (public.t_get('B')).measured_value, 10000::float8);
select public.t_eq('B scored_at moved to the flip', (public.t_get('B')).scored_at > (select scored_at from b_before), true);
select public.t_eq('B a lower reading never flips it back', public.t_report('B', 9500)->>'unchanged', '1');
select public.t_eq('B stays honoured', (public.t_get('B')).status, 'honoured');

-- C: BROKEN no_data gets a reading below target.
select public.t_eq('C reading counts as updated', public.t_report('C', 4000)->>'updated', '1');
select public.t_eq('C still broken', (public.t_get('C')).status, 'broken');
select public.t_eq('C no_data becomes target_missed', (public.t_get('C')).resolution, 'target_missed');
select public.t_eq('C total recorded', (public.t_get('C')).measured_value, 4000::float8);

-- D: BROKEN no_data gets a reading at the target.
select public.t_eq('D reading at target turns honoured', public.t_report('D', 12000)->>'honoured', '1');
select public.t_eq('D now honoured target_met', (public.t_get('D')).status || '/' || (public.t_get('D')).resolution, 'honoured/target_met');

-- E: outside the 30-day window nothing changes.
select public.t_eq('E outside the window is skipped', public.t_report('E', 20000)->>'skipped', '1');
select public.t_eq('E untouched', (public.t_get('E')).status || '/' || (public.t_get('E')).measured_value, 'broken/5000');

-- G, H: older days inside the window.
select public.t_eq('G HONOURED 10 days ago is raised', public.t_report('G', 15000)->>'updated', '1');
select public.t_eq('G lower reading unchanged', public.t_report('G', 14000)->>'unchanged', '1');
select public.t_eq('G total', (public.t_get('G')).measured_value, 15000::float8);
select public.t_eq('H BROKEN 29 days ago is raised', public.t_report('H', 9500)->>'updated', '1');
select public.t_eq('H still broken', (public.t_get('H')).status, 'broken');

-- Never measured: amended, self-reported, Word Tracker, another person's.
select public.t_eq('AM amended skipped', public.t_report('AM', 20000)->>'skipped', '1');
select public.t_eq('S self-reported skipped', public.t_report('S', 20000)->>'skipped', '1');
select public.t_eq('S untouched', (public.t_get('S')).measured_value, null::float8);
select public.t_eq('W word day skipped', public.t_report('W', 20000)->>'skipped', '1');
select public.t_eq('O foreign day skipped', public.t_report('O', 20000)->>'skipped', '1');
select public.t_eq('O untouched', (public.t_get('O')).measured_value, 11000::float8);

-- Pending days score exactly as in v1.
select public.t_eq('P1 partial reading stays pending', public.t_report('P1', 5000)->>'pending', '1');
select public.t_eq('P1 pending total', (public.t_get('P1')).status || '/' || (public.t_get('P1')).measured_value, 'pending/5000');
select public.t_eq('P1 reading at target honours', public.t_report('P1', 10001)->>'honoured', '1');
select public.t_eq('P2 full reading after the settle hour breaks',
  public.t_report('P2', 3000, (select deadline_at from public.t_get('P2')))->>'broken', '1');
select public.t_eq('P2 broken target_missed', (public.t_get('P2')).status || '/' || (public.t_get('P2')).resolution, 'broken/target_missed');
select public.t_eq('P2 late total below target is raised', public.t_report('P2', 9999)->>'updated', '1');
select public.t_eq('P2 late total at target honours', public.t_report('P2', 10000)->>'honoured', '1');

-- P3: pending past 24 h belongs to the 15-minute expiry job; once it has
-- stamped the stale 7,000, a late full total still honours the day.
select public.t_eq('P3 pending past 24 h skipped', public.t_report('P3', 10500)->>'skipped', '1');
reset role;
select public.t_eq('expiry job stamps P3', public.expire_icon_days() >= 1, true);
set role authenticated;
select public.t_eq('P3 expired with the stale total', (public.t_get('P3')).status || '/' || (public.t_get('P3')).resolution || '/' || (public.t_get('P3')).measured_value, 'broken/target_missed/7000');
select public.t_eq('P3 is measured again', position('P3' in public.t_measure_names()) > 0, true);
select public.t_eq('P3 late full total honours', public.t_report('P3', 10500)->>'honoured', '1');
select public.t_eq('P3 now honoured', (public.t_get('P3')).status, 'honoured');

-- Bad rows never fail the batch; counts add up across one report.
select public.t_eq('bad rows skipped', public.record_icon_measurements(jsonb_build_array(
    '{"contractId":"nope","day":"x","value":1,"measuredThrough":"y"}'::jsonb,
    public.t_row('A', -5),
    jsonb_set(public.t_row('A', 1), '{value}', '"Infinity"'),
    '{"day":"2026-10-01","value":1,"measuredThrough":"2026-10-01T00:00:00Z"}'::jsonb
  ))->>'skipped', '4');
create temp table batch as select public.record_icon_measurements(jsonb_build_array(
    public.t_row('A', 16000), public.t_row('G', 16000), public.t_row('E', 1), public.t_row('C', 100), public.t_row('H', 10000)
  )) as r;
select public.t_eq('batch counts', (select r from batch),
  '{"broken": 0, "pending": 0, "skipped": 1, "updated": 2, "honoured": 1, "unchanged": 1}'::jsonb);

-- Every key is present even when nothing happened.
select public.t_eq('empty report keys', public.record_icon_measurements('[]'::jsonb),
  '{"broken": 0, "pending": 0, "skipped": 0, "updated": 0, "honoured": 0, "unchanged": 0}'::jsonb);
reset role;

-- Not callable without a signed-in user.
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  perform public.record_icon_measurements('[]'::jsonb);
  raise exception 'FAIL anonymous call was accepted';
exception when sqlstate '42501' then
  raise notice 'ok  anonymous call refused';
end $$;

-- The stand-in's functions are production's: same pg_get_functiondef() md5.
\set ON_ERROR_STOP on
select public.t_eq('baseline ' || p.proname || ' matches production', md5(pg_get_functiondef(p.oid)), x.md5)
from (values
  ('update_updated_at_column', '3210625d1c794f6db7b3c3defc5984dd'),
  ('icon_cut', '270d4554ecb9959c7bd42fe5c4fc3497'),
  ('icon_target_split', '71288fb5b03fbdd93edd6e4f282396df'),
  ('icon_copy_affirmation', '715efe069db48d63e5fc20d67f8eb309'),
  ('icon_copy_deadline', '369624b5d376972024cdb8541af8de66'),
  ('icon_schedule', '9470cc5ecd55ca783f577a38af569b44'),
  ('icon_reserved_days', 'b75268fdc38710c0bfeffd29ce2f44c4'),
  ('icon_days_to_measure', 'b0df75c43f218c843a61fe4efb1ffe25'),
  ('expire_icon_days', 'a7af4714cfc80ef41f37bddd9fcfd576'),
  ('icon_push_facts', '3d396c2e252e2793768c9a73e02a7fdb'),
  ('icon_push_jobs', 'd0763dedd128fb9dbda8f759bb8f267d'),
  ('icon_push_plan', '55affed11a2c83a739a92c067f583783'),
  ('contracts_icon_guard', '05d2aad1b81f327fe38fe69dfcbe2ec6'),
  ('contracts_icon_reserve', '12c767142a1a6db3a58e7e1380872a94'),
  ('contracts_icon_days', 'ba8878e4a12694e58e557769d5dd72b0'),
  ('contracts_word_guard', '0d051e3b6e01453c49fa7d141bef375b'),
  ('self_report_icon_day', '95feb36678457d17636baf234bf7f096'),
  ('record_word_reading', '77ed09fa03b8ee58d8a9622de9982d27'),
  ('record_icon_measurements', '3e443e4f5a8ae4c80be38ce30c33e73a')
) as x(proname, md5)
join pg_proc p on p.proname = x.proname and p.pronamespace = 'public'::regnamespace
order by p.proname;
select public.t_eq('every baseline function is present', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('update_updated_at_column', 'icon_cut', 'icon_target_split', 'icon_copy_affirmation', 'icon_copy_deadline', 'icon_schedule', 'icon_reserved_days', 'icon_days_to_measure', 'expire_icon_days', 'icon_push_facts', 'icon_push_jobs', 'icon_push_plan', 'contracts_icon_guard', 'contracts_icon_reserve', 'contracts_icon_days', 'contracts_word_guard', 'self_report_icon_day', 'record_word_reading', 'record_icon_measurements')), 19::bigint);

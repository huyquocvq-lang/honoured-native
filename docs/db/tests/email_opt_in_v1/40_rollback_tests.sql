\set ON_ERROR_STOP on
select public.t_eq('consent columns are gone',
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name like 'marketing_opt_in%'), 0::bigint);
select public.t_eq('consent functions are gone',
  to_regprocedure('public.set_marketing_opt_in(boolean)') is null
  and to_regprocedure('public.record_signup_marketing_opt_in(boolean, text)') is null
  and to_regprocedure('public.profiles_marketing_guard()') is null, true);
select public.t_eq('guard trigger is gone',
  (select count(*) from pg_trigger where tgname = 'profiles_marketing_guard'), 0::bigint);

-- Sign-up works as before, metadata or not.
insert into auth.users (id, email, raw_user_meta_data) values
  ('66666666-6666-6666-6666-666666666666', 'u6@example.com', '{"display_name":"U6","marketing_opt_in":true}');
select public.t_eq('sign-up still creates the profile',
  (select display_name from public.profiles where id = '66666666-6666-6666-6666-666666666666'), 'U6');
select public.t_eq('sign-up still starts the trial',
  (select count(*) from public.trial_state where user_id = '66666666-6666-6666-6666-666666666666'), 1::bigint);
select public.t_eq('handle_new_user is the production body again',
  md5(pg_get_functiondef('public.handle_new_user()'::regprocedure)), :'baseline_md5');

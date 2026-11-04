\set ON_ERROR_STOP on
-- Applied again after a rollback: rows created in between start opted out.
select public.t_eq('an account from the rolled-back window starts opted out',
  public.t_consent('66666666-6666-6666-6666-666666666666'), 'false|no-time|no-source');
select public.t_eq('the guard is back',
  (select count(*) from pg_trigger where tgname = 'profiles_marketing_guard'), 1::bigint);
insert into auth.users (id, email, raw_user_meta_data) values
  ('77777777-7777-7777-7777-777777777777', 'u7@example.com', '{"marketing_opt_in":"true"}');
select public.t_eq('email sign-up records again after re-applying',
  public.t_consent('77777777-7777-7777-7777-777777777777'), 'true|time|signup_email');

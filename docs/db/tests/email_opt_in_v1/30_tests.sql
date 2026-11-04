\set ON_ERROR_STOP on
-- Accounts: U0 existed before the migration; U1/U2 sign up with email (box
-- ticked / not ticked); U3 signs up with Apple; U4 is a Google account
-- created two hours ago; U5 has no profile row of its own.

select public.t_eq('existing account is not opted in and has no choice recorded',
  public.t_consent('00000000-0000-0000-0000-000000000000'), 'false|no-time|no-source');

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'u1@example.com', '{"display_name":"U1","marketing_opt_in":true}'),
  ('22222222-2222-2222-2222-222222222222', 'u2@example.com', '{"display_name":"U2","marketing_opt_in":"false"}'),
  ('33333333-3333-3333-3333-333333333333', 'u3@privaterelay.example', '{"name":"U3"}');
insert into auth.users (id, email, raw_user_meta_data, created_at) values
  ('44444444-4444-4444-4444-444444444444', 'u4@example.com', '{"name":"U4"}', now() - interval '2 hours');

select public.t_eq('email sign-up with the box ticked is opted in',
  public.t_consent('11111111-1111-1111-1111-111111111111'), 'true|time|signup_email');
select public.t_eq('email sign-up keeps the name',
  (select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'U1');
select public.t_eq('email sign-up still starts the trial',
  (select count(*) from public.trial_state where user_id = '11111111-1111-1111-1111-111111111111'), 1::bigint);
select public.t_eq('email sign-up with the box clear records a no',
  public.t_consent('22222222-2222-2222-2222-222222222222'), 'false|time|signup_email');
select public.t_eq('Apple sign-up starts with no choice recorded',
  public.t_consent('33333333-3333-3333-3333-333333333333'), 'false|no-time|no-source');

-- U3 writes its own row directly: the name changes, consent does not.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
set role authenticated;
update public.profiles
   set display_name = 'Renamed', marketing_opt_in = true,
       marketing_opt_in_at = now(), marketing_opt_in_source = 'settings'
 where id = '33333333-3333-3333-3333-333333333333';
reset role;
select public.t_eq('a direct update keeps consent',
  public.t_consent('33333333-3333-3333-3333-333333333333'), 'false|no-time|no-source');
select public.t_eq('a direct update still changes the name',
  (select display_name from public.profiles where id = '33333333-3333-3333-3333-333333333333'), 'Renamed');

-- U3's Apple sign-up choice is recorded once; a later sign-in cannot change it.
set role authenticated;
select public.t_eq('Apple sign-up choice is recorded',
  public.record_signup_marketing_opt_in(true, 'signup_apple') ->> 'applied', 'true');
select public.t_eq('a later sign-in cannot overwrite it',
  public.record_signup_marketing_opt_in(false, 'signup_apple') ->> 'reason', 'already_recorded');
reset role;
select public.t_eq('Apple account is opted in from sign-up',
  public.t_consent('33333333-3333-3333-3333-333333333333'), 'true|time|signup_apple');

-- U1 chose at email sign-up; the social path cannot change that.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('email sign-up choice cannot be replaced by the sign-up call',
  public.record_signup_marketing_opt_in(false, 'signup_google') ->> 'reason', 'already_recorded');
reset role;
select public.t_eq('U1 still opted in from email sign-up',
  public.t_consent('11111111-1111-1111-1111-111111111111'), 'true|time|signup_email');

-- U4 is two hours old: signing in with Google now is not a sign-up.
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);
set role authenticated;
select public.t_eq('an older account is not treated as a sign-up',
  public.record_signup_marketing_opt_in(true, 'signup_google') ->> 'reason', 'not_a_new_account');
do $$
begin
  perform public.record_signup_marketing_opt_in(true, 'settings');
  raise exception 'FAIL settings is not a sign-up source';
exception when sqlstate '22023' then
  raise notice 'ok  a source other than sign-up is refused';
end $$;
do $$
begin
  perform public.record_signup_marketing_opt_in(null, 'signup_google');
  raise exception 'FAIL a missing choice was accepted';
exception when sqlstate '22023' then
  raise notice 'ok  a missing choice is refused';
end $$;
reset role;
select public.t_eq('U4 still has no choice recorded',
  public.t_consent('44444444-4444-4444-4444-444444444444'), 'false|no-time|no-source');

-- The Settings toggle, both ways, for U4 and for U1.
set role authenticated;
select public.t_eq('Settings toggle on',
  public.set_marketing_opt_in(true) ->> 'marketing_opt_in', 'true');
reset role;
select public.t_eq('Settings toggle on is recorded with its source',
  public.t_consent('44444444-4444-4444-4444-444444444444'), 'true|time|settings');
set role authenticated;
select public.t_eq('Settings toggle off',
  public.set_marketing_opt_in(false) ->> 'marketing_opt_in', 'false');
reset role;
select public.t_eq('Settings toggle off is recorded with its source',
  public.t_consent('44444444-4444-4444-4444-444444444444'), 'false|time|settings');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;
select public.t_eq('U1 turns it off in Settings',
  public.set_marketing_opt_in(false) ->> 'applied', 'true');
reset role;
select public.t_eq('U1 off from Settings',
  public.t_consent('11111111-1111-1111-1111-111111111111'), 'false|time|settings');
select public.t_eq('other accounts are untouched',
  public.t_consent('22222222-2222-2222-2222-222222222222'), 'false|time|signup_email');

-- U5 inserts its own profile row and tries to opt itself in.
insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555', 'u5@example.com');
delete from public.profiles where id = '55555555-5555-5555-5555-555555555555';
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
set role authenticated;
insert into public.profiles (id, display_name, marketing_opt_in, marketing_opt_in_at, marketing_opt_in_source)
values ('55555555-5555-5555-5555-555555555555', 'U5', true, now(), 'settings');
reset role;
select public.t_eq('a client-inserted row starts opted out',
  public.t_consent('55555555-5555-5555-5555-555555555555'), 'false|no-time|no-source');

-- Not signed in, and anonymous callers.
select set_config('request.jwt.claim.sub', '', false);
set role authenticated;
do $$
begin
  perform public.set_marketing_opt_in(true);
  raise exception 'FAIL a call without a user was accepted';
exception when insufficient_privilege then
  raise notice 'ok  a call without a user is refused';
end $$;
reset role;
set role anon;
do $$
begin
  perform public.set_marketing_opt_in(true);
  raise exception 'FAIL anon could set consent';
exception when insufficient_privilege then
  raise notice 'ok  anon cannot set consent';
end $$;
do $$
begin
  perform public.record_signup_marketing_opt_in(true, 'signup_apple');
  raise exception 'FAIL anon could record a sign-up choice';
exception when insufficient_privilege then
  raise notice 'ok  anon cannot record a sign-up choice';
end $$;
reset role;

-- A choice always carries its time and source.
do $$
begin
  update public.profiles set marketing_opt_in = true, marketing_opt_in_at = null, marketing_opt_in_source = null
   where id = '22222222-2222-2222-2222-222222222222';
  raise exception 'FAIL opted in without a recorded time';
exception when check_violation then
  raise notice 'ok  opted in needs a time and a source';
end $$;
do $$
begin
  update public.profiles set marketing_opt_in_source = 'newsletter'
   where id = '22222222-2222-2222-2222-222222222222';
  raise exception 'FAIL an unknown source was stored';
exception when check_violation then
  raise notice 'ok  unknown sources are refused';
end $$;

# Evidence queries for the M2 test plan. Run with the Lovable `query_database`
# tool (service role) against Lovable Cloud. Replace the <PLACEHOLDERS>. Every
# query is read-only or ends in ROLLBACK. Never select token values: tokens are
# shown as a length and a short hash.

QUERIES = [
    ("Q-00", "Test user id",
     "Find the user id of a test account (needed by Q-09 and Q-10).",
     """select id as user_id, email, created_at
from auth.users
where email = '<TEST_EMAIL>';""",
     "One row per account."),

    ("Q-01", "Icon contracts of the account",
     "Signed Icon terms and status (M2-01, M2-03, M2-04, M2-11, M2-12).",
     """select c.client_id, c.status, c.created_at, c.deadline, c.resolved_at,
       c.primary_activity, c.primary_target, c.because, c.secondary_activity, c.standing,
       c.icon_weekdays, c.icon_start_day, c.icon_period_count, c.icon_period_unit, c.icon_end_day,
       c.icon_deadline_time, c.icon_timezone, c.icon_morning_time, c.icon_evening_time,
       c.icon_metric, c.icon_target, c.icon_unit,
       (c.signature_path is not null) as has_signature
from public.contracts c
join auth.users u on u.id = c.user_id
where u.email = '<TEST_EMAIL>'
  and c.icon_weekdays is not null
order by c.created_at desc;""",
     "icon_weekdays are ISO weekdays (Mon = 1 … Sun = 7); icon_end_day is exclusive."),

    ("Q-02", "Icon days of one Icon",
     "One row per scheduled day with local times in the Icon's zone (M2-03, M2-04, M2-05, M2-09).",
     """select d.day, d.session_number, d.status, d.resolution, d.measured_value,
       to_char(d.deadline_at at time zone c.icon_timezone, 'YYYY-MM-DD HH24:MI') as cutoff_local,
       to_char(d.morning_at at time zone c.icon_timezone, 'HH24:MI') as morning_local,
       to_char(d.evening_at at time zone c.icon_timezone, 'HH24:MI') as evening_local,
       to_char(d.scored_at at time zone c.icon_timezone, 'YYYY-MM-DD HH24:MI') as scored_local
from public.icon_days d
join public.contracts c on c.id = d.contract_id
where c.client_id = '<CLIENT_ID>'
order by d.day;""",
     "CLIENT_ID comes from Q-01."),

    ("Q-03", "Push tokens of the account",
     "Registered tokens without their values (M2-06).",
     """select left(t.installation_id::text, 8) as install, t.kind, t.environment, t.topic,
       t.contract_client_id, t.icon_day, t.os_version, t.live_activities_enabled,
       length(t.token) as token_len, left(md5(t.token), 8) as token_hash,
       t.created_at, t.updated_at
from public.push_tokens t
join auth.users u on u.id = t.user_id
where u.email = '<TEST_EMAIL>'
order by t.kind, t.updated_at desc;""",
     "device ≈ 64 characters, push_to_start ≈ 160. A changed token_hash means a rotated token."),

    ("Q-03b", "Push tokens of one install",
     "Whether an install still has rows after sign-out (M2-06).",
     """select left(t.installation_id::text, 8) as install, t.kind, count(*) as rows
from public.push_tokens t
where t.installation_id::text like '<INSTALL8>%'
group by 1, 2
order by 2;""",
     "INSTALL8 = the install column from Q-03 before signing out. Expect no rows after sign-out."),

    ("Q-04", "Push log (one row per slot)",
     "What each Icon appearance did (M2-07, M2-09).",
     """select c.client_id, l.day, l.slot, l.channel, l.status, l.apns_status, l.apns_reason,
       to_char(l.recorded_at at time zone c.icon_timezone, 'YYYY-MM-DD HH24:MI:SS') as recorded_local
from public.icon_push_log l
join public.contracts c on c.id = l.contract_id
join auth.users u on u.id = c.user_id
where u.email = '<TEST_EMAIL>'
order by l.recorded_at desc
limit 50;""",
     "slot: morning, evening, result, end. status: sent, skipped or failed."),

    ("Q-05", "Push requests",
     "Each APNs request and its outcome (M2-07, M2-09).",
     """select s.request_id, c.client_id, s.day, s.slot, s.channel, s.auxiliary, s.outcome,
       s.apns_status, s.apns_reason, left(s.installation_id::text, 8) as install,
       to_char(s.created_at at time zone c.icon_timezone, 'YYYY-MM-DD HH24:MI:SS') as queued_local
from public.icon_push_sends s
join public.contracts c on c.id = s.contract_id
join auth.users u on u.id = c.user_id
where u.email = '<TEST_EMAIL>'
order by s.created_at desc
limit 50;""",
     "auxiliary = true is the evening close of the morning card. outcome: sent, retry, drop-token, new-provider-token, failed."),

    ("Q-06", "Scheduled jobs",
     "icon-push (every minute) and icon-days-expire (every 15 minutes) are running (M2-05, M2-07).",
     """select j.jobid, j.jobname, j.schedule, j.active,
       (select count(*) from cron.job_run_details r
         where r.jobid = j.jobid and r.start_time > now() - interval '1 hour') as runs_last_hour,
       (select count(*) from cron.job_run_details r
         where r.jobid = j.jobid and r.start_time > now() - interval '1 hour' and r.status <> 'succeeded') as failed_last_hour,
       (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid) as last_run
from cron.job j
where j.jobname in ('icon-push', 'icon-days-expire')
order by j.jobid;""",
     "Expect about 60 and 4 runs in the last hour, 0 failed."),

    ("Q-07", "Health totals of a day",
     "Synced Apple Health totals for comparison with the Icon reading (M2-05).",
     """select h.day, h.metric, h.total, h.unit, h.updated_at
from public.health_daily h
join auth.users u on u.id = h.user_id
where u.email = '<TEST_EMAIL>'
  and h.day = '<YYYY-MM-DD>'
order by h.metric;""",
     "health_daily days follow the daily reset hour; compare with an Icon day only when the reset hour is 00:00."),

    ("Q-08", "Recap reconciliation",
     "Counts behind a weekly or monthly recap (M2-10).",
     """with u as (select id from auth.users where email = '<TEST_EMAIL>')
select
  count(*) filter (where d.status = 'honoured') as honoured,
  count(*) filter (where d.status = 'broken') as broken,
  count(*) filter (where d.status = 'pending') as pending,
  (select count(*) from public.contracts c2, u
    where c2.user_id = u.id and c2.icon_weekdays is not null and c2.status = 'amended'
      and (c2.resolved_at at time zone c2.icon_timezone)::date between '<FIRST_DAY>' and '<LAST_DAY>') as amended_icons
from public.icon_days d, u
where d.user_id = u.id
  and d.day between '<FIRST_DAY>' and '<LAST_DAY>';""",
     "Week = Monday to Sunday; month = 1st to last day. The app counts Amended by the iPhone's local date of the early exit."),

    ("Q-09", "Account isolation (RLS)",
     "What one account can see of another's Icon data (M2-03). Rolled back.",
     """begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', '<VIEWER_USER_ID>', 'role', 'authenticated')::text, true);
select
  (select count(*) from public.icon_days where user_id = '<OWNER_USER_ID>') as icon_days_visible,
  (select count(*) from public.contracts where user_id = '<OWNER_USER_ID>') as contracts_visible,
  (select count(*) from public.push_tokens where user_id = '<OWNER_USER_ID>') as push_tokens_visible;
rollback;""",
     "VIEWER = ACC-B, OWNER = ACC-A: all 0. VIEWER = OWNER: the owner's own counts."),

    ("Q-10", "Lock-in guard",
     "Tries to change signed terms as the owner, reads them back, rolls back (M2-04).",
     """begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', '<OWNER_USER_ID>', 'role', 'authenticated')::text, true);
with attempted as (
  update public.contracts
     set icon_weekdays = '{1,2,3,4,5,6,7}', icon_period_count = 9, icon_target = 1,
         primary_target = '1 steps', icon_deadline_time = '01:00'
   where client_id = '<CLIENT_ID>'
  returning icon_weekdays, icon_period_count, icon_period_unit, icon_target, primary_target, icon_deadline_time
)
select * from attempted;
rollback;""",
     "One row, holding the original values: the guard put them back. No row means the client id or user id is wrong."),

    ("Q-11", "Recent contracts of the account",
     "Shows that a refused contract was never stored (M2-15).",
     """select c.client_id, c.status, (c.icon_weekdays is not null) as is_icon,
       c.primary_activity, c.created_at, c.deadline
from public.contracts c
join auth.users u on u.id = c.user_id
where u.email = '<TEST_EMAIL>'
  and c.created_at > now() - interval '2 days'
order by c.created_at desc;""",
     "The refused contract must not be listed."),

    ("Q-12", "Signature stored for an Icon",
     "The signature the card shows exists in storage (M2-08).",
     """select c.client_id, (c.signature_path is not null) as has_signature,
       (select count(*) from storage.objects o
         where o.bucket_id = 'signatures' and o.name = c.signature_path) as stored_objects
from public.contracts c
where c.client_id = '<CLIENT_ID>';""",
     "has_signature true and stored_objects 1."),

    ("Q-13", "Wall-clock times across a clock change",
     "Cut-off and reminders keep their local times when the UTC offset changes (M2-14).",
     """select d.day,
       to_char(d.deadline_at at time zone c.icon_timezone, 'HH24:MI') as cutoff_local,
       to_char(d.morning_at at time zone c.icon_timezone, 'HH24:MI') as morning_local,
       to_char(d.evening_at at time zone c.icon_timezone, 'HH24:MI') as evening_local,
       (d.deadline_at at time zone c.icon_timezone) - (d.deadline_at at time zone 'UTC') as utc_offset
from public.icon_days d
join public.contracts c on c.id = d.contract_id
where c.client_id = '<CLIENT_ID>'
  and d.day between '<FROM_DAY>' and '<TO_DAY>'
order by d.day;""",
     "Local columns constant; utc_offset changes by 1 hour at the clock change."),

    ("Q-14", "Client privileges",
     "What signed-in and anonymous clients may do (M2-03, M2-06).",
     """select
  has_table_privilege('authenticated', 'public.icon_days', 'insert') as auth_insert_icon_days,
  has_table_privilege('authenticated', 'public.icon_days', 'update') as auth_update_icon_days,
  has_table_privilege('authenticated', 'public.apns_provider_tokens', 'select') as auth_read_provider_tokens,
  has_table_privilege('anon', 'public.apns_provider_tokens', 'select') as anon_read_provider_tokens,
  has_table_privilege('authenticated', 'public.icon_push_log', 'select') as auth_read_push_log,
  has_table_privilege('authenticated', 'public.icon_push_sends', 'select') as auth_read_push_sends,
  has_function_privilege('authenticated', 'public.icon_push_tick(timestamptz)', 'execute') as auth_run_tick,
  has_function_privilege('anon', 'public.unregister_push_tokens(uuid)', 'execute') as anon_unregister;""",
     "All false except anon_unregister (true: sign-out must work without a session)."),
]

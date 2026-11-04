#!/bin/bash
# Runs the Icon revision checks (Phase 4 M2.1-M2.4) in throwaway Postgres 17
# databases (see ../pgtest.sh for the Docker and local modes), on a stand-in
# whose functions are production's own bodies. Nothing here touches Lovable
# Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name=honoured-sqltest-revisions
source "$here/../pgtest.sh"

base() {
  start
  step /work/00_schema.sql
  step /work/01_prod_functions.sql
  step /work/02_triggers.sql
}

# psql -c prints every statement's result; callers keep the last line.
as_a() {
  echo "select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false); set role authenticated; $1"
}

expect() {
  if [[ "$2" != "$3" ]]; then
    echo "FAIL $1: got $2, want $3"
    exit 1
  fi
  echo "ok  $1"
}

echo "# Pass 0: the stand-in is production"
base
step /work/03_baseline_check.sql

echo "# Pass 1: migration, revisions, readers, rollback"
base
step /work/10_seed.sql
step /db/icon_revisions_v1_rollback.sql      # before the migration: nothing to undo
step /db/icon_revisions_v1.sql
step /db/icon_revisions_v1.sql               # re-running is harmless
step /work/20_helpers.sql
step /work/30_tests.sql
step /db/icon_revisions_v1.sql               # and harmless after revisions
step /work/32_rerun_tests.sql
step /work/36_cascade_tests.sql
step_refused /db/icon_revisions_v1_rollback.sql "holds 5 revisions"
step /db/icon_revisions_v1_rollback.sql -c "set honoured.discard_icon_revisions = 'yes'"
step /work/40_rollback_tests.sql
step /db/icon_revisions_v1_rollback.sql      # re-running the rollback is harmless
step /db/icon_revisions_v1.sql               # applies again after a rollback
step /work/50_reapply_tests.sql

echo "# Pass 2: two revisions of one Icon at the same time"
base
step /work/10_seed.sql
step /db/icon_revisions_v1.sql
step /work/20_helpers.sql
sig=11111111-1111-1111-1111-111111111111/client-1/revisions
# The same request twice: the second waits for the first, then gets it back.
psql_c "begin; $(as_a "select public.t_rev('1', '7', 11000, '$sig/c1.png'); select pg_sleep(2); commit;")" >/dev/null &
first=$!
sleep 0.5
second=$(psql_c "$(as_a "select public.t_rev('1', '7', 11000, '$sig/c1.png')->>'duplicate';")" | tail -n 1)
wait "$first"
expect "a concurrent retry gets the same revision back" "$second" "true"
expect "one revision recorded" "$(psql_c "select count(*) from public.icon_revisions")" "1"
# Two different requests: the second queues and builds on the first.
psql_c "begin; $(as_a "select public.t_rev('1', '8', 9500, '$sig/c2.png'); select pg_sleep(2); commit;")" >/dev/null &
first=$!
sleep 0.5
second=$(psql_c "$(as_a "select concat_ws('/', r->>'revision', r->>'targetText') from (select public.t_rev('1', '9', 9000, '$sig/c3.png') r) x;")" | tail -n 1)
wait "$first"
expect "a concurrent second revision queues behind the first" "$second" "3/9000 steps"
expect "it records the first as its previous target" \
  "$(psql_c "select previous_target_text from public.icon_revisions where revision = 3")" "9500 steps"
expect "tomorrow holds the latest" \
  "$(psql_c "select public.t_state('1', public.t_today('Europe/London') + 1)")" "pending/9000 steps/9000/3"
# For comparing a deployment with what was tested here.
psql_c "select 'md5 after icon_revisions_v1: ' || proname || ' ' || md5(pg_get_functiondef(oid)) from pg_proc
        where pronamespace = 'public'::regnamespace and proname in ('contracts_icon_days', 'icon_days_to_measure',
          'icon_push_jobs', 'record_icon_measurements', 'revise_icon_target', 'icon_revisions_immutable') order by proname"

echo "# Pass 3: icon_revisions_v1_1 on top of v1, with Supabase's default grants"
base
step /work/05_supabase_defaults.sql
step /work/10_seed.sql
step /work/60_v1_1_seed.sql
step /db/icon_revisions_v1.sql
step /db/icon_revisions_v1_1_rollback.sql    # before v1.1: v1 stays as it is
step /db/icon_revisions_v1_1.sql
step /db/icon_revisions_v1_1.sql             # re-running is harmless
step /work/20_helpers.sql
step /work/30_tests.sql                      # every v1 check holds on v1.1
step /work/36_cascade_tests.sql
step /work/60_v1_1_tests.sql
psql_c "select 'md5 after icon_revisions_v1_1: ' || proname || ' ' || md5(pg_get_functiondef(oid)) from pg_proc
        where pronamespace = 'public'::regnamespace and proname in ('revise_icon_target', 'icon_revisions_immutable') order by proname"
step /db/icon_revisions_v1_1_rollback.sql
step /work/70_v1_1_rollback_tests.sql
step /db/icon_revisions_v1_1_rollback.sql    # re-running the rollback is harmless
step /db/icon_revisions_v1_1.sql             # applies again after its rollback
step_refused /db/icon_revisions_v1_rollback.sql "holds"
step /db/icon_revisions_v1_rollback.sql -c "set honoured.discard_icon_revisions = 'yes'"
step /work/40_rollback_tests.sql             # the v1 rollback undoes v1.1 too
step_refused /db/icon_revisions_v1_1_rollback.sql "nothing for icon_revisions_v1_1_rollback.sql to undo"
step_refused /db/icon_revisions_v1_1.sql "needs icon_revisions_v1.sql applied first"

echo "# Pass 4: rolling back v1 while a revision commits"
base
step /work/10_seed.sql
step /db/icon_revisions_v1.sql
step /work/20_helpers.sql
# The rollback waits for the revision instead of counting past it.
psql_c "begin; $(as_a "select public.t_rev('1', '7', 11000, '$sig/c1.png'); select pg_sleep(2); commit;")" >/dev/null &
first=$!
sleep 0.5
step_refused /db/icon_revisions_v1_rollback.sql "holds 1 revisions"
wait "$first"
expect "the revision committed meanwhile is kept" "$(psql_c "select count(*) from public.icon_revisions")" "1"
echo "ALL STEPS PASSED"

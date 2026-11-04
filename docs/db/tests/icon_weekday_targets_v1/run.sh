#!/bin/bash
# Runs the Icon weekday target checks (icon_weekday_targets_v1.sql) in
# throwaway Postgres 17 databases (see ../pgtest.sh for the Docker and local
# modes), on the revision suite's stand-in, whose functions are production's
# own bodies. Nothing here touches Lovable Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name=honoured-sqltest-weekday-targets
source "$here/../pgtest.sh"
rev=/db/tests/icon_revisions_v1

base() {
  start
  step $rev/00_schema.sql
  step $rev/01_prod_functions.sql
  step $rev/02_triggers.sql
  step $rev/05_supabase_defaults.sql
}

echo "# Pass 1: every revision check still holds with weekday targets in place"
base
step $rev/10_seed.sql
step $rev/60_v1_1_seed.sql
step /db/icon_revisions_v1.sql
step /db/icon_revisions_v1_1.sql
step /db/icon_weekday_targets_v1.sql
step /db/icon_weekday_targets_v1.sql         # re-running is harmless
step $rev/20_helpers.sql
step $rev/30_tests.sql
step $rev/36_cascade_tests.sql
step $rev/60_v1_1_tests.sql

echo "# Pass 2: weekday targets, weekday revisions, push facts, rollback"
base
step $rev/10_seed.sql
step /db/icon_revisions_v1.sql
step /db/icon_revisions_v1_1.sql
step /db/icon_weekday_targets_v1_rollback.sql # before the migration: nothing to undo
step /db/icon_weekday_targets_v1.sql
step $rev/20_helpers.sql
step /work/20_helpers.sql
step /work/30_tests.sql
step /db/icon_weekday_targets_v1.sql         # and harmless after signings and revisions
psql_c "select 'md5 after icon_weekday_targets_v1: ' || proname || ' ' || md5(pg_get_functiondef(oid)) from pg_proc
        where pronamespace = 'public'::regnamespace and proname in ('contracts_icon_guard', 'contracts_icon_days',
          'icon_push_facts', 'revise_icon_targets') order by proname"
step_refused /db/icon_revisions_v1_rollback.sql "icon_weekday_targets_v1.sql is in place"
step_refused /db/icon_weekday_targets_v1_rollback.sql "Icons hold weekday targets"
step /db/icon_weekday_targets_v1_rollback.sql -c "set honoured.discard_icon_weekday_targets = 'yes'"
step /work/40_rollback_tests.sql
step /db/icon_weekday_targets_v1_rollback.sql # re-running the rollback is harmless
step /db/icon_weekday_targets_v1.sql         # applies again after a rollback
step /work/50_reapply_tests.sql

echo "# Pass 3: refused on top of icon_revisions_v1.sql alone"
base
step $rev/10_seed.sql
step /db/icon_revisions_v1.sql
step_refused /db/icon_weekday_targets_v1.sql "needs icon_revisions_v1_1.sql applied first"
echo "ALL STEPS PASSED"

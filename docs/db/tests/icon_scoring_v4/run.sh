#!/bin/bash
# Runs the Icon scoring v4 checks in throwaway Postgres 17 databases (see
# ../pgtest.sh for the Docker and local modes), on the v2 stand-in schema and
# seed. Nothing here touches Lovable Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name=honoured-sqltest-v4
source "$here/../pgtest.sh"

base() {
  start
  step /v2/00_schema.sql
  step /db/icon_scoring_v2_rollback.sql    # the v1 functions as deployed
  step /v2/10_seed.sql
  step /db/icon_scoring_v2.sql
}

echo "# Pass 1: v4 needs v3, and keeps v2's behaviour for one source"
base
step_refused /db/icon_scoring_v4.sql "needs icon_scoring_v3.sql applied first"
step /work/05_still_v2.sql               # the refused run left nothing behind
step /db/icon_scoring_v3.sql
step /db/icon_scoring_v4.sql
step /db/icon_scoring_v4.sql             # re-running is harmless
step /v2/30_v2_tests.sql

echo "# Pass 2: v3's source rules hold under v4"
base
step /db/icon_scoring_v3.sql
step /db/icon_scoring_v4.sql
step /v3/30_v3_tests.sql

echo "# Pass 3: Automatic <-> iPhone, then the rollback"
base
step /db/icon_scoring_v3.sql
v3_md5=$(psql_c "select md5(pg_get_functiondef('public.record_icon_measurements(jsonb)'::regprocedure))")
echo "record_icon_measurements under v3: $v3_md5"
step /db/icon_scoring_v4.sql
step /work/30_v4_tests.sql
step /db/icon_scoring_v4_rollback.sql
step /work/40_rollback_tests.sql -v v3_md5="$v3_md5"
step /db/icon_scoring_v4.sql             # applies again after a rollback
echo "ALL STEPS PASSED"

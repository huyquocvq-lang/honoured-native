#!/bin/bash
# Runs the email opt-in v1 checks in a throwaway Postgres 17 (see
# ../pgtest.sh for the Docker and local modes). Nothing here touches
# Lovable Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name=honoured-sqltest-email-opt-in
source "$here/../pgtest.sh"

start
step /work/00_schema.sql
baseline_md5=$(psql_c "select md5(pg_get_functiondef('public.handle_new_user()'::regprocedure))")
echo "handle_new_user before the migration: $baseline_md5"
step /work/10_seed.sql
step /db/email_opt_in_v1.sql
step /db/email_opt_in_v1.sql              # re-running is harmless
step /work/30_tests.sql
step /db/email_opt_in_v1_rollback.sql
step /work/40_rollback_tests.sql -v baseline_md5="$baseline_md5"
step /db/email_opt_in_v1.sql              # applies again after a rollback
step /work/50_reapply_tests.sql
echo "ALL STEPS PASSED"

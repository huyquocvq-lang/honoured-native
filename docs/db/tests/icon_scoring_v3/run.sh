#!/bin/bash
# Runs the Icon scoring v3 checks in throwaway Postgres 17 containers
# (production is 17.6), on the v2 stand-in schema and seed. Nothing here
# touches Lovable Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
v2="$(cd "$here/../icon_scoring_v2" && pwd)"
db="$(cd "$here/../.." && pwd)"
name=honoured-sqltest-v3

stop() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap stop EXIT

start() {
  stop
  docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test \
    -v "$here":/work:ro -v "$v2":/v2:ro -v "$db":/db:ro postgres:17-alpine >/dev/null
  for _ in $(seq 1 60); do
    if docker exec "$name" pg_isready -U postgres -q 2>/dev/null \
       && docker exec "$name" psql -U postgres -tAc 'select 1' >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  echo "Postgres did not start"
  exit 1
}

run() { docker exec "$name" psql -U postgres -X -q -v ON_ERROR_STOP=1 -f "$1" 2>&1; }

step() {
  echo "== $1"
  if ! out=$(run "$1"); then
    echo "$out" | sed -E 's/^psql:[^:]+:[0-9]+: //'
    echo "STEP FAILED: $1"
    exit 1
  fi
  echo "$out" | grep -E 'ok  |FAIL' | sed -E 's/^psql:[^:]+:[0-9]+: NOTICE:  //' || true
}

# A file that must refuse to run, with `expected` in its error.
step_refused() {
  echo "== $1 (must be refused)"
  if out=$(run "$1"); then
    echo "STEP SHOULD HAVE FAILED: $1"
    exit 1
  fi
  if ! echo "$out" | grep -q "$2"; then
    echo "$out"
    echo "STEP FAILED FOR ANOTHER REASON: $1"
    exit 1
  fi
  echo "ok  refused: $2"
}

echo "# Pass 1: v3 needs v2, then behaves as v2 for readings of one source"
start
step /v2/00_schema.sql
step /db/icon_scoring_v2_rollback.sql      # the v1 functions as deployed
step /v2/10_seed.sql
step_refused /db/icon_scoring_v3.sql "needs icon_scoring_v2.sql applied first"
step /work/05_column_absent.sql            # the refused run left nothing behind
step /db/icon_scoring_v2.sql
step /db/icon_scoring_v3.sql
step /db/icon_scoring_v3.sql               # re-running is harmless
step /v2/30_v2_tests.sql

echo "# Pass 2: readings from another source"
start
step /v2/00_schema.sql
step /db/icon_scoring_v2_rollback.sql
step /v2/10_seed.sql
step /db/icon_scoring_v2.sql
step /db/icon_scoring_v3.sql
step /work/30_v3_tests.sql
step /db/icon_scoring_v3_rollback.sql
step /work/40_rollback_tests.sql
echo "ALL STEPS PASSED"

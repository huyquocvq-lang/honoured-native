#!/bin/bash
# Runs the goal diagnostics v1 checks in a throwaway Postgres 17 container
# (production is 17.6), on the stand-in schema of the Icon scoring tests.
# Nothing here touches Lovable Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
v2="$(cd "$here/../icon_scoring_v2" && pwd)"
db="$(cd "$here/../.." && pwd)"
name=honoured-sqltest-diagnostics

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test \
  -v "$here":/work:ro -v "$v2":/v2:ro -v "$db":/db:ro postgres:17-alpine >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  if docker exec "$name" pg_isready -U postgres -q 2>/dev/null \
     && docker exec "$name" psql -U postgres -tAc 'select 1' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

step() {
  echo "== $1"
  if ! out=$(docker exec "$name" psql -U postgres -X -q -v ON_ERROR_STOP=1 -f "$1" 2>&1); then
    echo "$out" | sed -E 's/^psql:[^:]+:[0-9]+: //'
    echo "STEP FAILED: $1"
    exit 1
  fi
  echo "$out" | grep -E 'ok  |FAIL' | sed -E 's/^psql:[^:]+:[0-9]+: NOTICE:  //' || true
}

step /v2/00_schema.sql
step /work/10_seed.sql
step /db/goal_diagnostics_v1.sql
step /db/goal_diagnostics_v1.sql           # re-running is harmless
step /work/30_tests.sql
step /db/goal_diagnostics_v1_rollback.sql
step /work/40_rollback_tests.sql
echo "ALL STEPS PASSED"

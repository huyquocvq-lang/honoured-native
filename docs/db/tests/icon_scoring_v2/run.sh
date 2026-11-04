#!/bin/bash
# Runs the Icon scoring v2 checks in a throwaway Postgres 17 container
# (production is 17.6). Nothing here touches Lovable Cloud.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="/Users/drakenvu/Documents/MacMiniDocuments/upwork/honoured/honoured-native/docs/db"
name=honoured-sqltest

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test \
  -v "$here":/work:ro -v "$db":/db:ro postgres:17-alpine >/dev/null
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

step /work/00_schema.sql
step /db/icon_scoring_v2_rollback.sql      # the v1 functions as deployed
step /work/10_seed.sql
step /work/20_v1_baseline.sql
step /db/icon_scoring_v2.sql
step /db/icon_scoring_v2.sql               # re-running is harmless
step /work/30_v2_tests.sql
step /db/icon_scoring_v2_rollback.sql
step /work/40_rollback_tests.sql
echo "ALL STEPS PASSED"

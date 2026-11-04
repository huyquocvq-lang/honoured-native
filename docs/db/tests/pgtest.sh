# Shared runner for the SQL checks: source it from a suite's run.sh after
# setting `here` (the suite folder) and `name` (a container name). It starts
# a throwaway Postgres 17 (production is 17.6) and nothing touches Lovable
# Cloud.
#
# With PG_BIN set to a folder holding initdb, pg_ctl and postgres 17, each
# pass runs in a temporary local cluster; psql comes from PATH or PSQL.
# Otherwise each pass runs in a postgres:17-alpine Docker container.
#
# Suites name files by their place in the container: /work (the suite),
# /db (docs/db), /v2 and /v3 (the Icon scoring v2 and v3 suites); the local
# mode maps them to the real folders.

db="$(cd "$here/../.." && pwd)"
v2="$(cd "$here/../icon_scoring_v2" && pwd)"
v3="$(cd "$here/../icon_scoring_v3" && pwd)"
PSQL="${PSQL:-psql}"

if [[ -n "${PG_BIN:-}" ]]; then
  pg_tmp="$(mktemp -d)"
  pg_port="${PG_PORT:-55432}"

  stop() {
    if [[ -d "$pg_tmp/data" ]]; then
      "$PG_BIN/pg_ctl" -D "$pg_tmp/data" -m immediate stop >/dev/null 2>&1 || true
      rm -rf "$pg_tmp/data"
    fi
  }
  start() {
    stop
    "$PG_BIN/initdb" -D "$pg_tmp/data" -U postgres -A trust >/dev/null
    "$PG_BIN/pg_ctl" -D "$pg_tmp/data" -l "$pg_tmp/server.log" \
      -o "-k $pg_tmp -p $pg_port -c listen_addresses=" -w start >/dev/null
  }
  local_path() {
    case "$1" in
      /work/*) echo "$here/${1#/work/}" ;;
      /db/*) echo "$db/${1#/db/}" ;;
      /v2/*) echo "$v2/${1#/v2/}" ;;
      /v3/*) echo "$v3/${1#/v3/}" ;;
      *) echo "$1" ;;
    esac
  }
  psql_run() {
    local file; file="$(local_path "$1")"; shift
    "$PSQL" -h "$pg_tmp" -p "$pg_port" -U postgres -X -q -v ON_ERROR_STOP=1 "$@" -f "$file"
  }
  psql_c() { "$PSQL" -h "$pg_tmp" -p "$pg_port" -U postgres -X -q -tA -c "$1"; }
  trap 'stop; rm -rf "$pg_tmp"' EXIT
else
  stop() { docker rm -f "$name" >/dev/null 2>&1 || true; }
  start() {
    stop
    docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test \
      -v "$here":/work:ro -v "$v2":/v2:ro -v "$v3":/v3:ro -v "$db":/db:ro postgres:17-alpine >/dev/null
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
  psql_run() {
    local file="$1"; shift
    docker exec "$name" psql -U postgres -X -q -v ON_ERROR_STOP=1 "$@" -f "$file"
  }
  psql_c() { docker exec "$name" psql -U postgres -X -q -tA -c "$1"; }
  trap stop EXIT
fi

step() {
  local file="$1"; shift
  echo "== $file"
  if ! out=$(psql_run "$file" "$@" 2>&1); then
    echo "$out" | sed -E 's/^psql:[^:]+:[0-9]+: //'
    echo "STEP FAILED: $file"
    exit 1
  fi
  echo "$out" | grep -E 'ok  |FAIL' | sed -E 's/^psql:[^:]+:[0-9]+: NOTICE:  //' || true
}

# A file that must refuse to run, with `expected` in its error.
step_refused() {
  echo "== $1 (must be refused)"
  if out=$(psql_run "$1" 2>&1); then
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

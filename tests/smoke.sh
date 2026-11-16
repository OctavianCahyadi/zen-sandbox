#!/usr/bin/env bash
# End-to-end smoke test for sbx. Starts real containers and purges them at the end,
# so it refuses to run where a sandbox already exists. Meant for CI or an isolated
# Docker daemon (see CONTRIBUTING.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SBX="$ROOT/bin/sbx"
SBX_HOME="$(mktemp -d)"
export SBX_HOME

if [ -n "$(docker ps -aq --filter name=sbx-)" ] || [ -n "$(docker volume ls -q --filter name=sbx-)" ]; then
  echo "smoke: this machine already has sbx-* containers or volumes; refusing to run." >&2
  exit 2
fi

pass() { echo "ok   $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
has()  { grep -q -- "$2" <<<"$1" || fail "$3 (got: $1)"; }

s3() {
  docker exec sbx-rustfs curl -s --aws-sigv4 aws:amz:us-east-1:s3 --user sandbox:sandbox123 "$@"
}

cleanup() {
  docker stop sbxsmoke-old >/dev/null 2>&1 || true
  docker container prune -f --filter label=sbx.smoke=1 >/dev/null 2>&1 || true
  "$SBX" remove postgres redis rustfs --purge >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$SBX" up postgres redis rustfs >/dev/null
out="$("$SBX" list)"
has "$out" "postgres *yes *yes" "postgres should be enabled and running"
pass "up postgres redis rustfs"

"$SBX" project init demo-app >/dev/null
out="$("$SBX" resources)"
has "$out" "postgres:db *demo_app" "database demo_app should be recorded"
has "$out" "rustfs:bucket *demo-app" "bucket demo-app should be recorded"
[ "$(docker exec sbx-postgres psql -U demo_app -d demo_app -Atc 'select 1')" = "1" ] || fail "cannot query demo_app"
[ "$(s3 -o /dev/null -w '%{http_code}' -I http://127.0.0.1:9000/demo-app)" = "200" ] || fail "bucket demo-app missing"
pass "project init (database + bucket)"

out="$("$SBX" env demo-app)"
has "$out" "S3_BUCKET=demo-app" "env should print the bucket"
has "$out" "demo_app" "env should print the database"
pass "env"

"$SBX" port redis 16379 >/dev/null 2>&1
out="$("$SBX" context)"
has "$out" "redis (localhost:16379)" "context should show the changed redis port"
out="$("$SBX" port postgres 16379 2>&1 || true)"
has "$out" "already used by another sandbox service" "duplicate port should be refused"
pass "port change is applied and shown in context"

# Something else holds a port: sbx must name it and `auto` must move away from it.
docker run -d --name sbxsmoke-old -l sbx.smoke=1 -l com.docker.compose.project=oldproj \
  -p 127.0.0.1:13306:5432 -e POSTGRES_USER=old -e POSTGRES_PASSWORD=oldpw -e POSTGRES_DB=olddb \
  postgres:16-alpine >/dev/null
"$SBX" port mysql 13306 >/dev/null 2>&1
out="$("$SBX" port)"
has "$out" "13306 *IN USE by container sbxsmoke-old" "busy port should name its owner"
"$SBX" port mysql auto >/dev/null 2>&1
out="$("$SBX" port)"
has "$out" "MYSQL_PORT *13307" "auto should pick the next free port"
pass "busy port owner + auto"

for _ in $(seq 1 30); do
  docker exec sbxsmoke-old pg_isready -U old -d olddb >/dev/null 2>&1 && break
  sleep 1
done
sleep 2
docker exec sbxsmoke-old psql -q -U old -d olddb \
  -c "CREATE EXTENSION pgcrypto" \
  -c "CREATE TABLE t(id serial primary key, v text)" \
  -c "INSERT INTO t(v) SELECT md5(g::text) FROM generate_series(1, 100) g"
out="$("$SBX" scan)"
has "$out" "oldproj *postgres *sbxsmoke-old" "scan should list the old postgres"
out="$("$SBX" import postgres sbxsmoke-old imported 2>&1)"
has "$out" "tables: source 1, sandbox 1; restore errors: 0" "import should copy the table cleanly"
[ "$(docker exec sbx-postgres psql -U imported -d imported -Atc 'select count(*) from t')" = "100" ] || fail "imported rows missing"
out="$("$SBX" import postgres sbxsmoke-old imported 2>&1 || true)"
has "$out" "already has 1 tables" "second import should be refused"
pass "scan + import postgres"

"$SBX" bucket drop demo-app >/dev/null 2>&1
[ "$(s3 -o /dev/null -w '%{http_code}' -I http://127.0.0.1:9000/demo-app)" = "404" ] || fail "bucket should be gone"
"$SBX" remove redis >/dev/null 2>&1
out="$("$SBX" list)"
has "$out" "redis *- *-" "redis should be disabled and stopped"
pass "bucket drop + remove"

echo "smoke: all checks passed"

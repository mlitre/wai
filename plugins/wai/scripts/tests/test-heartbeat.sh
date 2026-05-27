#!/usr/bin/env bash
# Integration test for Phase 2: UI heartbeat + /api/heartbeat endpoint
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
START_SERVER="$REPO_ROOT/scripts/start-server.sh"

PREFIX="[test-heartbeat]"

SCRATCH_DIRS=()
SERVER_PIDS=()

cleanup() {
  for pid in "${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for d in "${SCRATCH_DIRS[@]+"${SCRATCH_DIRS[@]}"}"; do
    if [[ -n "$d" && -d "$d" ]]; then
      rm -rf "$d"
    fi
  done
}
trap cleanup EXIT

log() {
  echo "$PREFIX $*"
}

fail() {
  echo "$PREFIX FAIL: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd curl
require_cmd jq
require_cmd node
require_cmd bash
require_cmd python3

# Launch a server. Args: <scratch_dir> [env KEY=VAL ...]
# Sets global SERVER_URL and SERVER_PID.
launch_server() {
  local project_dir="$1"
  shift
  local env_args=("$@")

  mkdir -p "$project_dir"
  SCRATCH_DIRS+=("$project_dir")

  local info
  info="$(env "${env_args[@]}" "$START_SERVER" --project-dir "$project_dir")"

  SERVER_URL="$(echo "$info" | jq -r '.url')"
  local pid_file="$project_dir/.ds/server.pid"
  if [[ ! -f "$pid_file" ]]; then
    fail "server.pid not written at $pid_file; info was: $info"
  fi
  SERVER_PID="$(cat "$pid_file")"
  SERVER_PIDS+=("$SERVER_PID")

  if [[ -z "$SERVER_URL" || "$SERVER_URL" == "null" ]]; then
    fail "could not extract URL from: $info"
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "server $SERVER_PID not alive after launch"
  fi
}

kill_server() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    # wait up to 3s
    for _ in 1 2 3 4 5 6; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
  fi
}

################################################################################
# Test 1: /api/heartbeat exists, returns 204; CORS wildcard must NOT be present
# (the UI is same-origin with the server; permissive CORS would expose diffs
# and file contents to any page the user happens to visit)
################################################################################
log "Test 1: /api/heartbeat returns 204 with no permissive CORS header"
D1="$(mktemp -d)"
launch_server "$D1"
URL1="$SERVER_URL"
PID1="$SERVER_PID"

# `curl -sSI` sends HEAD by default; server accepts both GET and HEAD.
HEAD_OUT="$(curl -sSI "$URL1/api/heartbeat")"
if ! printf '%s' "$HEAD_OUT" | grep -qE '^HTTP/(1\.1|2) 204'; then
  echo "$HEAD_OUT"
  fail "expected HTTP 204 from /api/heartbeat"
fi
if printf '%s' "$HEAD_OUT" | grep -qi '^Access-Control-Allow-Origin: \*'; then
  echo "$HEAD_OUT"
  fail "Access-Control-Allow-Origin: * should have been removed"
fi
log "Test 1: PASS"
kill_server "$PID1"

################################################################################
# Test 2: heartbeat resets idle timer (server stays alive past idle budget)
################################################################################
log "Test 2: heartbeat resets idle timer"
D2="$(mktemp -d)"
launch_server "$D2" DS_IDLE_TIMEOUT_MS=4000
URL2="$SERVER_URL"
PID2="$SERVER_PID"

# Loop every 1s for 12s hitting /api/heartbeat
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  curl -s "$URL2/api/heartbeat" >/dev/null || true
  sleep 1
done

# Verify server still alive
if ! curl -sf "$URL2/api/status" >/dev/null; then
  fail "server at $URL2 died despite heartbeat polling (idle=4s, polled 12s)"
fi
if ! kill -0 "$PID2" 2>/dev/null; then
  fail "server PID $PID2 no longer alive"
fi
log "Test 2: PASS"
kill_server "$PID2"

################################################################################
# Test 3: no heartbeat => server dies within 75s
################################################################################
log "Test 3: no heartbeat -> server exits (idle budget 4s, check runs at 60s)"
D3="$(mktemp -d)"
launch_server "$D3" DS_IDLE_TIMEOUT_MS=4000
PID3="$SERVER_PID"

# Do NOT make any requests. Poll kill -0 for up to 75s.
DIED="false"
for i in $(seq 1 75); do
  if ! kill -0 "$PID3" 2>/dev/null; then
    DIED="true"
    log "  server $PID3 exited after ~${i}s of silence"
    break
  fi
  sleep 1
done

if [[ "$DIED" != "true" ]]; then
  fail "server $PID3 still alive after 75s with no traffic (idle=4s)"
fi
log "Test 3: PASS"

################################################################################
# Test 4: UI wiring grep checks
################################################################################
log "Test 4: UI wiring grep checks"
cd "$REPO_ROOT"

grep -q "HEARTBEAT_INTERVAL_MS = 60 \* 1000" ui/app.js \
  || fail "ui/app.js missing HEARTBEAT_INTERVAL_MS constant"
grep -q "function startHeartbeat" ui/app.js \
  || fail "ui/app.js missing startHeartbeat function"
grep -q "function stopHeartbeat" ui/app.js \
  || fail "ui/app.js missing stopHeartbeat function"
grep -q "fetch('/api/heartbeat')" ui/app.js \
  || fail "ui/app.js missing fetch('/api/heartbeat') call"
grep -q "stopHeartbeat()" ui/app.js \
  || fail "ui/app.js missing stopHeartbeat() call"
grep -q "startHeartbeat()" ui/app.js \
  || fail "ui/app.js missing startHeartbeat() call"

log "Test 4: PASS"

################################################################################
# Test 5: Node-based UI driver simulates browser heartbeat + submit
################################################################################
log "Test 5: Node UI driver, heartbeat keeps server alive, submit resets idle"
D5="$(mktemp -d)"
launch_server "$D5" DS_IDLE_TIMEOUT_MS=4000
URL5="$SERVER_URL"
PID5="$SERVER_PID"

NODE_DRIVER="$(cat <<'NODEJS'
const url = process.env.TEST_URL;

async function main() {
  // 1. Initial /api/diff fetch (like UI init())
  const diffRes = await fetch(url + '/api/diff');
  if (!diffRes.ok) {
    console.error('DRIVER: /api/diff failed:', diffRes.status);
    process.exit(2);
  }
  await diffRes.json();

  // 2. Start heartbeat every 1s
  const hb = setInterval(() => {
    fetch(url + '/api/heartbeat').catch(() => {});
  }, 1000);

  // 3. Wait 6s (server idle budget is 4s, heartbeat must keep it alive)
  await new Promise(r => setTimeout(r, 6000));

  // 4. Stop heartbeat
  clearInterval(hb);

  // 5. Post synthetic review
  const reviewRes = await fetch(url + '/api/review', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      decision: 'approve',
      summary: 'test review from heartbeat driver',
      comments: [],
    }),
  });
  if (!reviewRes.ok) {
    console.error('DRIVER: /api/review failed:', reviewRes.status);
    process.exit(3);
  }
  console.log('DRIVER: ok');
}

main().catch(err => {
  console.error('DRIVER: error', err && err.message);
  process.exit(1);
});
NODEJS
)"

if ! TEST_URL="$URL5" node -e "$NODE_DRIVER"; then
  fail "Node driver script failed (heartbeat did not keep server alive, or submit failed)"
fi

# Immediately after submit the server should still be alive
# (the POST itself resets idle).
if ! kill -0 "$PID5" 2>/dev/null; then
  fail "server $PID5 not alive right after synthetic review submit"
fi
if ! curl -sf "$URL5/api/status" >/dev/null; then
  fail "server $URL5 /api/status not reachable right after submit"
fi

log "Test 5: PASS"
kill_server "$PID5"

################################################################################
echo "$PREFIX PASS: all heartbeat tests passed"
exit 0

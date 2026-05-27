#!/usr/bin/env bash
# Integration test for Phase 3: parallel-project lifecycles are independent.
# Two projects launch their own servers with a tight idle budget. We heartbeat
# project 1 while ignoring project 2. Project 1 must stay alive; project 2
# must idle out.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
START_SERVER="$REPO_ROOT/scripts/start-server.sh"

PREFIX="[test-parallel]"

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
require_cmd bash

# Launch a server. Args: <scratch_dir> [env KEY=VAL ...]
# Sets global SERVER_URL, SERVER_PID, SERVER_PORT.
launch_server() {
  local project_dir="$1"
  shift
  local env_args=("$@")

  mkdir -p "$project_dir"
  SCRATCH_DIRS+=("$project_dir")

  local info
  info="$(env "${env_args[@]}" "$START_SERVER" --project-dir "$project_dir")"

  SERVER_URL="$(echo "$info" | jq -r '.url')"
  SERVER_PORT="$(echo "$info" | jq -r '.port')"
  local pid_file="$project_dir/.ds/server.pid"
  if [[ ! -f "$pid_file" ]]; then
    fail "server.pid not written at $pid_file; info was: $info"
  fi
  SERVER_PID="$(cat "$pid_file")"
  SERVER_PIDS+=("$SERVER_PID")

  if [[ -z "$SERVER_URL" || "$SERVER_URL" == "null" ]]; then
    fail "could not extract URL from: $info"
  fi
  if [[ -z "$SERVER_PORT" || "$SERVER_PORT" == "null" ]]; then
    fail "could not extract port from: $info"
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "server $SERVER_PID not alive after launch"
  fi
}

################################################################################
# Step 1: launch two independent servers with tight idle budget
################################################################################
log "Step 1: launching two servers with DS_IDLE_TIMEOUT_MS=4000"

D1="$(mktemp -d -t ds-par1-XXXXXX)"
launch_server "$D1" DS_IDLE_TIMEOUT_MS=4000
URL1="$SERVER_URL"
PID1="$SERVER_PID"
PORT1="$SERVER_PORT"
log "  project 1: dir=$D1 pid=$PID1 port=$PORT1 url=$URL1"

D2="$(mktemp -d -t ds-par2-XXXXXX)"
launch_server "$D2" DS_IDLE_TIMEOUT_MS=4000
URL2="$SERVER_URL"
PID2="$SERVER_PID"
PORT2="$SERVER_PORT"
log "  project 2: dir=$D2 pid=$PID2 port=$PORT2 url=$URL2"

# Sanity: both up, distinct ports, own server-info files
[[ "$PID1" != "$PID2" ]] || fail "both servers share PID $PID1"
[[ "$PORT1" != "$PORT2" ]] || fail "both servers share port $PORT1"
[[ -f "$D1/.ds/server-info" ]] || fail "project 1 missing .ds/server-info"
[[ -f "$D2/.ds/server-info" ]] || fail "project 2 missing .ds/server-info"

# Each server-info references its own project's state_dir
SD1="$(jq -r '.state_dir' < "$D1/.ds/server-info")"
SD2="$(jq -r '.state_dir' < "$D2/.ds/server-info")"
[[ "$SD1" == "$D1/"* ]] || fail "project 1 state_dir $SD1 not under $D1"
[[ "$SD2" == "$D2/"* ]] || fail "project 2 state_dir $SD2 not under $D2"

curl -sf "$URL1/api/status" >/dev/null || fail "project 1 /api/status unreachable"
curl -sf "$URL2/api/status" >/dev/null || fail "project 2 /api/status unreachable"

################################################################################
# Step 2: heartbeat project 1 for 10s while ignoring project 2
################################################################################
log "Step 2: heartbeating project 1 every 1s for 10s; project 2 idle"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -s "$URL1/api/heartbeat" >/dev/null || true
  sleep 1
done

################################################################################
# Step 3: project 1 must still be alive
################################################################################
log "Step 3: project 1 should still be alive"
if ! kill -0 "$PID1" 2>/dev/null; then
  fail "project 1 PID $PID1 died despite heartbeat"
fi
if ! curl -sf "$URL1/api/status" >/dev/null; then
  fail "project 1 $URL1/api/status unreachable despite heartbeat"
fi
log "  project 1 still alive"

################################################################################
# Step 4: project 2 must idle out (poll up to 75s; idle check fires ~60s)
################################################################################
log "Step 4: waiting for project 2 to idle out (up to 75s total)"
DIED="false"
for i in $(seq 1 75); do
  if ! kill -0 "$PID2" 2>/dev/null; then
    DIED="true"
    log "  project 2 PID $PID2 exited after ~${i}s of silence"
    break
  fi
  sleep 1
done

if [[ "$DIED" != "true" ]]; then
  fail "project 2 PID $PID2 still alive after 75s with no traffic (idle=4s)"
fi

# And project 1 should still be alive at this point, but we haven't
# heartbeat'd it during the 75s wait, so it may or may not be alive. We only
# asserted lifecycle independence up to step 3. Step 3 established P1 stays
# alive while P2 will die; that's the parallel-independence claim.

################################################################################
echo "$PREFIX PASS: parallel projects have independent idle lifecycles"
exit 0

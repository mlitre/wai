#!/usr/bin/env bash
# Integration test for Phase 1: centralized server-info publishing.
# Verifies that scripts/start-server.sh publishes .ds/server-info and
# .ds/server.pid regardless of caller, that cold-starts refresh those files,
# that orphan servers are killed on re-launch, and that check-review.js
# follows the refreshed state_dir.

set -euo pipefail

PREFIX="[test-server-info]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
START_SH="${PLUGIN_ROOT}/scripts/start-server.sh"
CHECK_JS="${PLUGIN_ROOT}/hooks/check-review.js"
SESSION_HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

log() { printf '%s %s\n' "$PREFIX" "$*"; }
fail() { printf '%s FAIL: %s\n' "$PREFIX" "$*" >&2; exit 1; }

for bin in curl jq node bash; do
  command -v "$bin" >/dev/null 2>&1 || fail "missing required tool: $bin"
done

[[ -x "$START_SH" ]] || fail "start-server.sh not executable: $START_SH"
[[ -f "$CHECK_JS" ]] || fail "check-review.js not found: $CHECK_JS"
[[ -f "$SESSION_HOOK" ]] || fail "session-start.sh not found: $SESSION_HOOK"

# Scratch project
SCRATCH="$(mktemp -d -t ds-test-XXXXXX)"
PID1=""
PID2=""
PID3=""

cleanup() {
  local rc=$?
  for p in "$PID1" "$PID2" "$PID3"; do
    if [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; then
      kill "$p" 2>/dev/null || true
    fi
  done
  if [[ -n "$SCRATCH" && -d "$SCRATCH" ]]; then
    rm -rf "$SCRATCH"
  fi
  if [[ $rc -eq 0 ]]; then
    printf '%s PASS\n' "$PREFIX"
  else
    printf '%s FAIL (exit=%d)\n' "$PREFIX" "$rc" >&2
  fi
  exit $rc
}
trap cleanup EXIT

log "scratch dir: $SCRATCH"
(
  cd "$SCRATCH" \
    && git init -q \
    && git config user.email test@example.com \
    && git config user.name test \
    && git config commit.gpgsign false \
    && git config tag.gpgsign false \
    && git commit -q --allow-empty -m init
)

wait_for_exit() {
  # Wait up to 5s for $1 (pid) to exit.
  local pid="$1"
  for _ in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

read_info_field() {
  # $1 field, $2 info file
  jq -r ".${1}" < "$2"
}

#-------------------------------------------------------------------------
log "step 1: fresh launch publishes top-level files"
out1="$("$START_SH" --project-dir "$SCRATCH")"
echo "$out1" | jq . >/dev/null || fail "start-server stdout is not JSON: $out1"

INFO="${SCRATCH}/.ds/server-info"
PIDF="${SCRATCH}/.ds/server.pid"

[[ -f "$INFO" ]] || fail ".ds/server-info was not created"
[[ -f "$PIDF" ]] || fail ".ds/server.pid was not created"

jq -e 'has("url") and has("state_dir") and has("port")' "$INFO" >/dev/null \
  || fail ".ds/server-info missing url/state_dir/port: $(cat "$INFO")"

PID1="$(cat "$PIDF")"
[[ -n "$PID1" ]] || fail ".ds/server.pid is empty"
kill -0 "$PID1" 2>/dev/null || fail "PID $PID1 from server.pid is not live"
log "  fresh PID=$PID1 port=$(read_info_field port "$INFO")"

#-------------------------------------------------------------------------
log "step 2: published URL is reachable; /api/status returns submitted:false"
URL1="$(read_info_field url "$INFO")"
[[ -n "$URL1" && "$URL1" != "null" ]] || fail "no url in server-info"
# Allow a brief grace period for the HTTP listener.
status_body=""
for _ in $(seq 1 20); do
  if status_body="$(curl -sf "${URL1}/api/status" 2>/dev/null)"; then
    break
  fi
  sleep 0.1
done
[[ -n "$status_body" ]] || fail "GET ${URL1}/api/status did not return 200"
echo "$status_body" | jq -e '.submitted == false' >/dev/null \
  || fail "/api/status body missing submitted:false, got: $status_body"
log "  /api/status OK: $status_body"

PORT1="$(read_info_field port "$INFO")"
STATE_DIR1="$(read_info_field state_dir "$INFO")"

#-------------------------------------------------------------------------
log "step 3: cold-start after kill refreshes files"
kill "$PID1" 2>/dev/null || true
wait_for_exit "$PID1" || fail "first server PID $PID1 did not exit"

out2="$("$START_SH" --project-dir "$SCRATCH")"
echo "$out2" | jq . >/dev/null || fail "second launch stdout is not JSON: $out2"

[[ -f "$INFO" ]] || fail ".ds/server-info missing after cold-start"
[[ -f "$PIDF" ]] || fail ".ds/server.pid missing after cold-start"

PORT2="$(read_info_field port "$INFO")"
STATE_DIR2="$(read_info_field state_dir "$INFO")"
PID2="$(cat "$PIDF")"

[[ "$PORT2" != "$PORT1" ]] || fail "port did not change across cold-start ($PORT1 == $PORT2)"
[[ "$STATE_DIR2" != "$STATE_DIR1" ]] || fail "state_dir did not change across cold-start"
kill -0 "$PID2" 2>/dev/null || fail "second server PID $PID2 is not live"
log "  refreshed PID=$PID2 port=$PORT2 state_dir=$STATE_DIR2"

#-------------------------------------------------------------------------
log "step 4: no cascade-kill / exactly one live server for project after re-launch"
out3="$("$START_SH" --project-dir "$SCRATCH")"
echo "$out3" | jq . >/dev/null || fail "third launch stdout is not JSON"

PID3="$(cat "$PIDF")"
[[ "$PID3" != "$PID2" ]] || fail "third launch returned same PID as previous ($PID2)"

# PID2 must have been swept by orphan-kill inside start-server.sh.
if kill -0 "$PID2" 2>/dev/null; then
  # Give it a brief moment to die.
  wait_for_exit "$PID2" || fail "prior server PID $PID2 was not killed by orphan sweep"
fi
kill -0 "$PID3" 2>/dev/null || fail "third server PID $PID3 is not live"

# Exactly one node server/index.js process must reference the scratch project.
# `env DS_DIR=... node ...` is exec-replaced by node, so DS_DIR is not in the
# cmdline, we have to read /proc/<pid>/environ. DS_DIR is set to the session
# subdirectory $SCRATCH/.ds/sessions/<id>, so we match by prefix.
matches=0
scoped=""
for pid in $(pgrep -f 'server/index.js' 2>/dev/null || true); do
  env_file="/proc/${pid}/environ"
  [[ -r "$env_file" ]] || continue
  ds_dir_val="$(awk -v RS='\0' -F= '$1=="DS_DIR"{print $2; exit}' "$env_file" 2>/dev/null)"
  if [[ "$ds_dir_val" == "${SCRATCH}/"* || "$ds_dir_val" == "${SCRATCH}" ]]; then
    matches=$((matches + 1))
    scoped="${scoped} ${pid}"
  fi
done
[[ "$matches" == "1" ]] || fail "expected exactly 1 live server for $SCRATCH, got $matches (pids:${scoped:-none})"
[[ "${scoped// /}" == "$PID3" ]] || fail "the surviving server PID (${scoped// /}) is not PID3=$PID3"
log "  PID3=$PID3 is the sole live server for the project"

# Ensure cleanup trap targets the current live PID.
PID2=""

#-------------------------------------------------------------------------
log "step 5: hooks/session-start.sh no longer duplicates publish"
dup_count="$(grep -c 'echo .* > .*/\.ds/server-info' "$SESSION_HOOK" || true)"
[[ "$dup_count" == "0" ]] || fail "session-start.sh still publishes server-info (count=$dup_count)"
log "  session-start.sh publish count = 0"

#-------------------------------------------------------------------------
log "step 6: check-review.js reads refreshed state_dir"
STATE_DIR3="$(read_info_field state_dir "$INFO")"
[[ -d "$STATE_DIR3" ]] || fail "state_dir $STATE_DIR3 does not exist"

REVIEW_JSON="${STATE_DIR3}/review.json"
cat > "$REVIEW_JSON" <<'JSON'
{"decision":"approve","summary":"auto-test","comments":[]}
JSON

hook_out="$(cd "$SCRATCH" && node "$CHECK_JS")"
[[ -n "$hook_out" ]] || fail "check-review.js produced no output"
sys_msg="$(echo "$hook_out" | jq -r '.systemMessage // empty')"
[[ -n "$sys_msg" ]] || fail "check-review.js output missing systemMessage: $hook_out"
echo "$sys_msg" | grep -q 'APPROVE'   || fail "systemMessage missing APPROVE: $sys_msg"
echo "$sys_msg" | grep -q 'auto-test' || fail "systemMessage missing auto-test: $sys_msg"
[[ ! -f "$REVIEW_JSON" ]] || fail "review.json was not deleted after hook ran"
log "  systemMessage = $sys_msg"

log "all assertions passed"
exit 0

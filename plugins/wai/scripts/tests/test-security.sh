#!/usr/bin/env bash
# Integration test for security/correctness fixes:
# - /api/file-context rejects path traversal via `../` (startsWith bug)
# - /vendor/ rejects path traversal via `../`
# - cwd is locked to DS_PROJECT_DIR; meta-file cwd is ignored
# - /api/wait-for-review long-poll delivers a submitted review atomically
# - A second waiter / hook after the first consumer sees no review
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
START_SERVER="$REPO_ROOT/scripts/start-server.sh"
CHECK_JS="$REPO_ROOT/hooks/check-review.js"

PREFIX="[test-security]"
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

log() { echo "$PREFIX $*"; }
fail() { echo "$PREFIX FAIL: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing: $1"; }

require_cmd curl
require_cmd jq
require_cmd node

launch_server() {
  local project_dir="$1"
  mkdir -p "$project_dir"
  SCRATCH_DIRS+=("$project_dir")
  local info
  info="$("$START_SERVER" --project-dir "$project_dir")"
  SERVER_URL="$(echo "$info" | jq -r '.url')"
  local pid_file="$project_dir/.ds/server.pid"
  [[ -f "$pid_file" ]] || fail "server.pid missing: $info"
  SERVER_PID="$(cat "$pid_file")"
  SERVER_PIDS+=("$SERVER_PID")
  STATE_DIR="$(echo "$info" | jq -r '.state_dir')"
  kill -0 "$SERVER_PID" 2>/dev/null || fail "server $SERVER_PID not alive"
}

################################################################################
# Setup: project P and a neighboring dir P-evil (would pass a startsWith check)
################################################################################
TMP="$(mktemp -d -t ds-sec-XXXXXX)"
SCRATCH_DIRS+=("$TMP")
PROJECT="$TMP/proj"
EVIL="$TMP/proj-evil"
mkdir -p "$PROJECT" "$EVIL"
echo 'SECRET_CONTENT' > "$EVIL/secret.txt"
echo 'public' > "$PROJECT/hello.txt"

(cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && git commit -q --allow-empty -m init)

launch_server "$PROJECT"
URL="$SERVER_URL"

################################################################################
# Test 1: legitimate read inside project succeeds
################################################################################
log "Test 1: /api/file-context reads files inside the project"
resp="$(curl -sf "$URL/api/file-context?file=hello.txt&start=1&end=5")"
echo "$resp" | jq -e '.lines | length >= 1' >/dev/null \
  || fail "expected lines in hello.txt, got: $resp"
log "Test 1: PASS"

################################################################################
# Test 2: path traversal to sibling dir is rejected
#
# cwd = $PROJECT; request file='../proj-evil/secret.txt'. A buggy startsWith
# guard would resolve to $TMP/proj-evil/secret.txt, then check
# startsWith($TMP/proj), which passes because '/proj-evil' starts with '/proj'.
# The isWithin() helper with path.sep must reject this.
################################################################################
log "Test 2: /api/file-context rejects ../proj-evil/secret.txt"
code="$(curl -s -o /tmp/ds-sec-out -w '%{http_code}' "$URL/api/file-context?file=../proj-evil/secret.txt&start=1&end=5")"
body="$(cat /tmp/ds-sec-out)"
rm -f /tmp/ds-sec-out
if [[ "$code" == "200" ]]; then
  if echo "$body" | grep -q SECRET_CONTENT; then
    fail "traversal succeeded, got SECRET_CONTENT: $body"
  fi
fi
[[ "$code" == "403" || "$code" == "404" ]] \
  || fail "expected 403 (Access denied) or 404, got $code: $body"
log "Test 2: PASS (code=$code)"

################################################################################
# Test 3: meta-file cwd is ignored (cwd is locked at startup)
#
# Write a review-meta.json that claims cwd=$EVIL. Since the server has
# DS_PROJECT_DIR=$PROJECT locked at startup, /api/file-context must still
# refuse to read secret.txt even by its bare name.
################################################################################
log "Test 3: review-meta.json cwd cannot redirect file-context reads"
cat > "$STATE_DIR/review-meta.json" <<JSON
{"baseline":"HEAD","cwd":"$EVIL","timestamp":0}
JSON
code="$(curl -s -o /tmp/ds-sec-out -w '%{http_code}' "$URL/api/file-context?file=secret.txt&start=1&end=5")"
body="$(cat /tmp/ds-sec-out)"
rm -f /tmp/ds-sec-out
if echo "$body" | grep -q SECRET_CONTENT; then
  fail "server honored meta cwd, leaked secret.txt: $body"
fi
log "Test 3: PASS (code=$code, body did not leak secret)"

################################################################################
# Test 4: /vendor/ traversal is rejected
################################################################################
log "Test 4: /vendor/ rejects ../ traversal"
code="$(curl -s -o /dev/null -w '%{http_code}' "$URL/vendor/../server/index.js")"
[[ "$code" == "403" || "$code" == "404" ]] \
  || fail "/vendor/../server/index.js returned $code (expected 403/404)"
log "Test 4: PASS (code=$code)"

################################################################################
# Test 5: /api/wait-for-review delivers a submitted review atomically; a
# second consumer (or the hook) sees no review afterwards
################################################################################
log "Test 5: /api/wait-for-review long-poll + atomic claim"

# Start the long-poll in the background. Write a review after 1s.
RESP_FILE="$(mktemp)"
( curl -s --max-time 15 "$URL/api/wait-for-review" > "$RESP_FILE" ) &
WAIT_PID=$!

sleep 1
curl -sf -X POST "$URL/api/review" \
  -H 'Content-Type: application/json' \
  -d '{"decision":"approve","summary":"sec-test","comments":[]}' >/dev/null \
  || fail "POST /api/review failed"

wait "$WAIT_PID"
resp="$(cat "$RESP_FILE")"
rm -f "$RESP_FILE"
echo "$resp" | jq -e '.delivered == true' >/dev/null \
  || fail "long-poll did not deliver; got: $resp"
echo "$resp" | jq -e '.review.decision == "approve"' >/dev/null \
  || fail "long-poll review.decision mismatch: $resp"

# After atomic claim, review.json must NOT exist (hook would double-deliver)
[[ ! -f "$STATE_DIR/review.json" ]] \
  || fail "review.json still present after long-poll claim, would cause double-delivery"

# Hook run immediately after should produce no systemMessage
hook_out="$(cd "$PROJECT" && node "$CHECK_JS")"
if echo "$hook_out" | jq -e '.systemMessage' >/dev/null 2>&1; then
  fail "hook delivered a duplicate review after long-poll consumed it: $hook_out"
fi
log "Test 5: PASS"

echo "$PREFIX PASS: all security tests passed"
exit 0

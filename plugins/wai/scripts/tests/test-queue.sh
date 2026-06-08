#!/usr/bin/env bash
# Integration test for the wai-queue CLI (T1 subcommands):
# - init creates the five state dirs and is idempotent
# - add writes a well-formed pending/<prio>-<id>/ (meta.json + prompt.md), prints bare id
# - status counts a freshly-added task as 1 pending
# - result on a non-existent id exits nonzero
# - cancel removes a pending task and status drops to 0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="$PLUGIN_ROOT/skills/queue/wai-queue.sh"

PREFIX="[test-queue]"
SCRATCH_DIRS=()

cleanup() {
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

require_cmd jq
require_cmd bash

[[ -x "$CLI" ]] || fail "CLI not executable: $CLI"

# fresh_queue: make an isolated scratch queue dir and export WAI_QUEUE_DIR.
fresh_queue() {
  local d
  d="$(mktemp -d -t wai-queue-XXXXXX)"
  SCRATCH_DIRS+=("$d")
  export WAI_QUEUE_DIR="$d/queue"
}

################################################################################
# Test 1: init creates the five state dirs and is idempotent
################################################################################
log "Test 1: init creates pending/claimed/done/failed/bin and is idempotent"
fresh_queue
out="$(bash "$CLI" init)"
[[ "$out" == "$WAI_QUEUE_DIR" ]] || fail "init did not print resolved dir, got: $out"
for sub in pending claimed done failed bin; do
  [[ -d "$WAI_QUEUE_DIR/$sub" ]] || fail "init did not create $sub/"
done
# Idempotent: second run exits 0 and is a no-op
bash "$CLI" init >/dev/null || fail "second init exited nonzero (not idempotent)"
for sub in pending claimed done failed bin; do
  [[ -d "$WAI_QUEUE_DIR/$sub" ]] || fail "second init lost $sub/"
done
log "Test 1: PASS"

################################################################################
# Test 2: add writes a well-formed pending/<prio>-<id>/ and prints bare id
################################################################################
log "Test 2: add writes a well-formed pending task and prints bare id"
fresh_queue
bash "$CLI" init >/dev/null
work="$(mktemp -d -t wai-queue-cwd-XXXXXX)"
SCRATCH_DIRS+=("$work")
id="$(bash "$CLI" add --cwd "$work" --priority 5 --agent reviewer --needs a,b "do the thing")"
[[ -n "$id" ]] || fail "add printed empty id"
# Priority 5 -> zero-padded 05; dir name is <prio>-<id>
taskdir="$WAI_QUEUE_DIR/pending/05-$id"
[[ -d "$taskdir" ]] || fail "expected pending dir $taskdir, missing"
# printed id matches the dir suffix (strip the NN- prefix)
dirname="$(basename "$taskdir")"
[[ "${dirname#*-}" == "$id" ]] || fail "printed id $id != dir suffix ${dirname#*-}"
# prompt.md content
[[ -f "$taskdir/prompt.md" ]] || fail "prompt.md missing in $taskdir"
grep -q "do the thing" "$taskdir/prompt.md" || fail "prompt.md content mismatch"
# meta.json well-formed: assert jq -e on every field
meta="$taskdir/meta.json"
[[ -f "$meta" ]] || fail "meta.json missing in $taskdir"
jq -e --arg id "$id" '.id == $id' "$meta" >/dev/null || fail "meta .id mismatch"
jq -e --arg cwd "$work" '.cwd == $cwd' "$meta" >/dev/null || fail "meta .cwd mismatch"
jq -e '.priority == 5' "$meta" >/dev/null || fail "meta .priority != 5"
jq -e '.agent == "reviewer"' "$meta" >/dev/null || fail "meta .agent != reviewer"
jq -e '.needs == ["a","b"]' "$meta" >/dev/null || fail "meta .needs != [a,b]"
jq -e '.attempt == 0' "$meta" >/dev/null || fail "meta .attempt != 0"
jq -e '.created | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$meta" >/dev/null \
  || fail "meta .created not iso8601-Z"
log "Test 2: PASS"

################################################################################
# Test 2b: add defaults + stdin prompt via '-'
################################################################################
log "Test 2b: add defaults (cwd/priority/agent/needs) and stdin prompt"
fresh_queue
bash "$CLI" init >/dev/null
id="$(cd "$work" && printf 'from stdin\n' | bash "$CLI" add -)"
taskdir="$WAI_QUEUE_DIR/pending/50-$id"
[[ -d "$taskdir" ]] || fail "expected default-priority dir $taskdir, missing"
grep -q "from stdin" "$taskdir/prompt.md" || fail "stdin prompt not captured"
meta="$taskdir/meta.json"
jq -e --arg cwd "$work" '.cwd == $cwd' "$meta" >/dev/null || fail "default cwd != PWD"
jq -e '.priority == 50' "$meta" >/dev/null || fail "default priority != 50"
jq -e '.agent == "general-purpose"' "$meta" >/dev/null || fail "default agent wrong"
jq -e '.needs == []' "$meta" >/dev/null || fail "default needs != []"
log "Test 2b: PASS"

################################################################################
# Test 3: status counts a freshly-added task as 1 pending
################################################################################
log "Test 3: status counts a freshly-added task as 1 pending"
fresh_queue
bash "$CLI" init >/dev/null
# empty queue: zero counts, exit 0
empty_status="$(bash "$CLI" status)" || fail "status on empty queue exited nonzero"
echo "$empty_status" | grep -Eq 'pending[^0-9]*0' || fail "empty status pending != 0: $empty_status"
id="$(bash "$CLI" add "task one")"
st="$(bash "$CLI" status)"
echo "$st" | grep -Eq 'pending[^0-9]*1' || fail "status pending != 1: $st"
# per-task line present with id, state, prio, attempt, needs
echo "$st" | grep -q "$id" || fail "status missing task line for $id"
echo "$st" | grep -q "pending" || fail "status task line missing state"
echo "$st" | grep -q "prio=" || fail "status task line missing prio="
echo "$st" | grep -q "attempt=" || fail "status task line missing attempt="
echo "$st" | grep -q "needs=" || fail "status task line missing needs="
log "Test 3: PASS"

################################################################################
# Test 4: result on a non-existent id exits nonzero
################################################################################
log "Test 4: result on a non-existent id exits nonzero"
fresh_queue
bash "$CLI" init >/dev/null
if bash "$CLI" result nonexistent-id-12345 >/dev/null 2>&1; then
  fail "result on missing id exited 0 (expected nonzero)"
fi
log "Test 4: PASS"

################################################################################
# Test 4b: cancel refuses a claimed task (claimed takes precedence, nonzero)
################################################################################
log "Test 4b: cancel refuses a claimed task"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "claimed task")"
# Simulate a claim (T1 has no claim subcommand): move into claimed/<id>.
mv "$WAI_QUEUE_DIR/pending/50-$id" "$WAI_QUEUE_DIR/claimed/$id"
if bash "$CLI" cancel "$id" >/dev/null 2>&1; then
  fail "cancel of a claimed task exited 0 (expected nonzero refusal)"
fi
[[ -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "cancel removed a claimed task dir"
log "Test 4b: PASS"

################################################################################
# Test 5: cancel removes a pending task and status drops to 0
################################################################################
log "Test 5: cancel removes a pending task and status drops to 0"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "cancel me")"
[[ -d "$WAI_QUEUE_DIR/pending/50-$id" ]] || fail "task not created before cancel"
bash "$CLI" cancel "$id" || fail "cancel exited nonzero"
[[ ! -d "$WAI_QUEUE_DIR/pending/50-$id" ]] || fail "cancel did not remove task dir"
st="$(bash "$CLI" status)"
echo "$st" | grep -Eq 'pending[^0-9]*0' || fail "status pending != 0 after cancel: $st"
log "Test 5: PASS"

echo "$PREFIX PASS: all queue tests passed"
exit 0

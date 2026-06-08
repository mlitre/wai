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

################################################################################
# Test 6: claim is atomic under a 2-worker race (exactly one winner)
################################################################################
log "Test 6: two concurrent claims partition one task (exactly one winner)"
fresh_queue
bash "$CLI" init >/dev/null
bash "$CLI" add "race task" >/dev/null
out_a="$(mktemp)"; out_b="$(mktemp)"
SCRATCH_DIRS+=("$out_a" "$out_b")
ec_a=0; ec_b=0
bash "$CLI" claim >"$out_a" 2>/dev/null &
pid_a=$!
bash "$CLI" claim >"$out_b" 2>/dev/null &
pid_b=$!
wait "$pid_a" || ec_a=$?
wait "$pid_b" || ec_b=$?
winners=0
[[ $ec_a -eq 0 && -s "$out_a" ]] && winners=$((winners + 1))
[[ $ec_b -eq 0 && -s "$out_b" ]] && winners=$((winners + 1))
[[ $winners -eq 1 ]] || fail "expected exactly 1 claim winner, got $winners (ec_a=$ec_a ec_b=$ec_b)"
claimed_count=0
for d in "$WAI_QUEUE_DIR"/claimed/*; do [[ -d "$d" ]] && claimed_count=$((claimed_count + 1)); done
[[ $claimed_count -eq 1 ]] || fail "expected 1 dir in claimed/, got $claimed_count"
# The winner printed claimed/<id>
winner_out="$out_a"; [[ $ec_b -eq 0 && -s "$out_b" ]] && winner_out="$out_b"
grep -q "claimed/" "$winner_out" || fail "winner did not print a claimed/ path: $(cat "$winner_out")"
log "Test 6: PASS"

################################################################################
# Test 6b: 3 workers / 3 tasks partition cleanly (each task claimed once)
################################################################################
log "Test 6b: 3 concurrent claims over 3 tasks -> clean partition"
fresh_queue
bash "$CLI" init >/dev/null
for i in 1 2 3; do bash "$CLI" add "task $i" >/dev/null; done
declare -a couts=()
declare -a cpids=()
for i in 1 2 3; do
  o="$(mktemp)"; SCRATCH_DIRS+=("$o"); couts+=("$o")
  bash "$CLI" claim >"$o" 2>/dev/null &
  cpids+=("$!")
done
wins=0
for idx in 0 1 2; do
  ec=0; wait "${cpids[$idx]}" || ec=$?
  [[ $ec -eq 0 && -s "${couts[$idx]}" ]] && wins=$((wins + 1))
done
[[ $wins -eq 3 ]] || fail "expected 3 claim winners over 3 tasks, got $wins"
ccount=0
for d in "$WAI_QUEUE_DIR"/claimed/*; do [[ -d "$d" ]] && ccount=$((ccount + 1)); done
[[ $ccount -eq 3 ]] || fail "expected 3 dirs in claimed/, got $ccount"
pcount=0
for d in "$WAI_QUEUE_DIR"/pending/*; do [[ -d "$d" ]] && pcount=$((pcount + 1)); done
[[ $pcount -eq 0 ]] || fail "expected pending/ empty after 3 claims, got $pcount"
log "Test 6b: PASS"

################################################################################
# Test 7: claim returns priority-then-FIFO order
################################################################################
log "Test 7: claim ordering is priority-then-FIFO"
fresh_queue
bash "$CLI" init >/dev/null
# Two priority-50 tasks at distinct timestamps, then a priority-10 task.
id_old="$(bash "$CLI" add --priority 50 "old p50")"
sleep 1
id_new="$(bash "$CLI" add --priority 50 "new p50")"
id_hi="$(bash "$CLI" add --priority 10 "p10 hi")"
c1="$(bash "$CLI" claim)"
grep -q "/$id_hi\$" <<<"$c1" || fail "first claim should be priority-10 $id_hi, got $c1"
c2="$(bash "$CLI" claim)"
grep -q "/$id_old\$" <<<"$c2" || fail "second claim should be older p50 $id_old, got $c2"
c3="$(bash "$CLI" claim)"
grep -q "/$id_new\$" <<<"$c3" || fail "third claim should be newer p50 $id_new, got $c3"
log "Test 7: PASS"

################################################################################
# Test 8: complete moves claimed -> done and result <id> prints the result
################################################################################
log "Test 8: complete moves to done/ and result prints stored output"
fresh_queue
export WAI_QUEUE_WORKER="test-worker-1"
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "to complete")"
claimed_path="$(bash "$CLI" claim)"
[[ "$claimed_path" == *"/claimed/$id" ]] || fail "claim did not return claimed/$id, got $claimed_path"
[[ -f "$WAI_QUEUE_DIR/claimed/$id/claim.json" ]] || fail "claim.json not written"
jq -e --arg w "$WAI_QUEUE_WORKER" '.worker == $w' "$WAI_QUEUE_DIR/claimed/$id/claim.json" >/dev/null \
  || fail "claim.json worker mismatch"
jq -e '.ts | type == "number"' "$WAI_QUEUE_DIR/claimed/$id/claim.json" >/dev/null \
  || fail "claim.json ts not a number"
rf="$(mktemp)"; SCRATCH_DIRS+=("$rf")
printf 'the result body\n' >"$rf"
bash "$CLI" complete "$id" --result-file "$rf" || fail "complete exited nonzero"
[[ -d "$WAI_QUEUE_DIR/done/$id" ]] || fail "complete did not move task to done/"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "complete left task in claimed/"
res="$(bash "$CLI" result "$id")"
grep -q "the result body" <<<"$res" || fail "result did not print stored body: $res"
# complete on a non-claimed id is nonzero
if bash "$CLI" complete "$id" --result-file "$rf" >/dev/null 2>&1; then
  fail "complete on a non-claimed (done) id exited 0"
fi
log "Test 8: PASS"

################################################################################
# Test 8b: complete reads result from stdin when --result-file is omitted
################################################################################
log "Test 8b: complete reads stdin result when --result-file omitted"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "stdin complete")"
bash "$CLI" claim >/dev/null
printf 'stdin result\n' | bash "$CLI" complete "$id" || fail "complete via stdin exited nonzero"
res="$(bash "$CLI" result "$id")"
grep -q "stdin result" <<<"$res" || fail "complete did not store stdin result: $res"
log "Test 8b: PASS"

################################################################################
# Test 9: fail retries (requeue) then dead-letters at the retry limit
################################################################################
log "Test 9: fail requeues with attempt bump, then dead-letters at limit"
export WAI_QUEUE_RETRIES=2
fresh_queue
export WAI_QUEUE_RETRIES=2
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "flaky task")"
bash "$CLI" claim >/dev/null
# First failure: attempt -> 1, requeued to pending/
out="$(bash "$CLI" fail "$id" --reason "boom one")"
grep -q "pending" <<<"$out" || fail "first fail did not report pending requeue: $out"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "first fail left task in claimed/"
req="$WAI_QUEUE_DIR/pending/50-$id"
[[ -d "$req" ]] || fail "first fail did not requeue to pending/50-$id"
[[ ! -f "$req/claim.json" ]] || fail "requeued task still has claim.json"
jq -e '.attempt == 1' "$req/meta.json" >/dev/null || fail "attempt not bumped to 1 after first fail"
# Re-claim and fail again: attempt -> 2 >= retries -> failed/
bash "$CLI" claim >/dev/null
out="$(bash "$CLI" fail "$id" --reason "boom two")"
grep -q "failed" <<<"$out" || fail "second fail did not report dead-letter: $out"
[[ -d "$WAI_QUEUE_DIR/failed/$id" ]] || fail "second fail did not dead-letter to failed/"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "second fail left task in claimed/"
jq -e '.attempt == 2' "$WAI_QUEUE_DIR/failed/$id/meta.json" >/dev/null || fail "attempt not 2 at dead-letter"
res="$(bash "$CLI" result "$id")"
grep -q "boom two" <<<"$res" || fail "dead-letter result.md missing reason: $res"
grep -q "error:" <<<"$res" || fail "dead-letter result.md missing 'error:' prefix: $res"
# fail on a non-claimed id is nonzero
if bash "$CLI" fail "$id" --reason x >/dev/null 2>&1; then
  fail "fail on a non-claimed (failed) id exited 0"
fi
log "Test 9: PASS"

echo "$PREFIX PASS: all queue tests passed"
exit 0

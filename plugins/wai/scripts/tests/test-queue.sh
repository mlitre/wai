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

################################################################################
# Test 10: claim is collision-safe — never buries a task inside an existing
# claimed/<id> dir (finding #1). Force claimed/<id> to pre-exist, then claim.
################################################################################
log "Test 10: claim skips a candidate when claimed/<id> already exists (no nesting)"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "collide me")"
mkdir -p "$WAI_QUEUE_DIR/claimed/$id"
# claim may exit 0 or 1 here; what matters is it must NOT bury the pending task
# inside claimed/$id (the POSIX `mv into existing dir` corruption).
bash "$CLI" claim >/dev/null 2>&1 || true
nested=()
for d in "$WAI_QUEUE_DIR/claimed/$id"/*-"$id"; do
  [[ -e "$d" ]] && nested+=("$d")
done
[[ ${#nested[@]} -eq 0 ]] || fail "claim buried the task: found nested $(printf '%s ' "${nested[@]}")"
log "Test 10: PASS"

################################################################################
# Test 11: add publishes atomically — no .staging leftover (finding #3).
################################################################################
log "Test 11: add leaves no .staging leftover and a well-formed pending dir"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "atomic publish")"
taskdir="$WAI_QUEUE_DIR/pending/50-$id"
[[ -d "$taskdir" ]] || fail "add did not publish pending dir $taskdir"
[[ -f "$taskdir/meta.json" && -f "$taskdir/prompt.md" ]] || fail "published task not well-formed"
if [[ -d "$WAI_QUEUE_DIR/.staging" ]]; then
  for d in "$WAI_QUEUE_DIR/.staging"/*; do
    [[ -e "$d" ]] && fail "add left a .staging leftover: $d"
  done
fi
log "Test 11: PASS"

################################################################################
# Test 12: complete --result-file <bad-path> dies cleanly, leaves task claimed
# (finding #4).
################################################################################
log "Test 12: complete with a missing --result-file dies cleanly, no move"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "bad result file")"
bash "$CLI" claim >/dev/null
err="$(mktemp)"; SCRATCH_DIRS+=("$err")
if bash "$CLI" complete "$id" --result-file /no/such/file 2>"$err"; then
  fail "complete with missing result file exited 0 (expected nonzero die)"
fi
grep -q "complete:" "$err" || fail "complete bad-file error not prefixed 'complete:': $(cat "$err")"
[[ -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "complete bad-file moved task out of claimed/"
[[ ! -d "$WAI_QUEUE_DIR/done/$id" ]] || fail "complete bad-file leaked task into done/"
log "Test 12: PASS"

################################################################################
# Test 13: worker-id resolution tolerates a failing hostname (finding #5).
################################################################################
log "Test 13: init/status succeed when hostname is missing/failing"
fresh_queue
shimbin="$(mktemp -d -t wai-queue-bin-XXXXXX)"
SCRATCH_DIRS+=("$shimbin")
printf '#!/usr/bin/env bash\nexit 1\n' > "$shimbin/hostname"
chmod +x "$shimbin/hostname"
(
  export PATH="$shimbin:$PATH"
  unset WAI_QUEUE_WORKER
  bash "$CLI" init >/dev/null || exit 11
  bash "$CLI" status >/dev/null || exit 12
) || fail "init/status failed with a failing hostname (worker-id fallback missing)"
log "Test 13: PASS"

################################################################################
# Test 14: priority is bounded 0-99 and claim ordering is numeric (finding #6).
################################################################################
log "Test 14: --priority >= 100 dies; priorities 5/50/99 claim in ascending order"
fresh_queue
bash "$CLI" init >/dev/null
if bash "$CLI" add --priority 100 "too big" >/dev/null 2>&1; then
  fail "add --priority 100 exited 0 (expected die: must be 0-99)"
fi
id5="$(bash "$CLI" add --priority 5 "p5")"
id50="$(bash "$CLI" add --priority 50 "p50")"
id99="$(bash "$CLI" add --priority 99 "p99")"
c1="$(bash "$CLI" claim)"; grep -q "/$id5\$" <<<"$c1" || fail "first claim should be p5 $id5, got $c1"
c2="$(bash "$CLI" claim)"; grep -q "/$id50\$" <<<"$c2" || fail "second claim should be p50 $id50, got $c2"
c3="$(bash "$CLI" claim)"; grep -q "/$id99\$" <<<"$c3" || fail "third claim should be p99 $id99, got $c3"
# Leading-zero priorities must parse as decimal, not octal (finding #6 follow-up).
fresh_queue
bash "$CLI" init >/dev/null
id08="$(bash "$CLI" add --priority 08 "p08")" || fail "add --priority 08 must be accepted (decimal 8)"
[[ -d "$WAI_QUEUE_DIR/pending/08-$id08" ]] || fail "p08 should use prefix 08-, dir missing"
jq -e '.priority == 8' "$WAI_QUEUE_DIR/pending/08-$id08/meta.json" >/dev/null || fail "p08 meta .priority must be decimal 8"
id010="$(bash "$CLI" add --priority 010 "p010")" || fail "add --priority 010 must be accepted (decimal 10)"
[[ -d "$WAI_QUEUE_DIR/pending/10-$id010" ]] || fail "p010 should use prefix 10- (decimal), dir missing"
jq -e '.priority == 10' "$WAI_QUEUE_DIR/pending/10-$id010/meta.json" >/dev/null || fail "p010 meta .priority must be decimal 10"
log "Test 14: PASS"

################################################################################
# Test 15: claim gates on deps — B (--needs A) is never claimable while A is
# pending or claimed; once A completes, B becomes claimable.
################################################################################
log "Test 15: claim never returns a task whose dep is still pending/claimed"
fresh_queue
bash "$CLI" init >/dev/null
id_a="$(bash "$CLI" add "task A")"
id_b="$(bash "$CLI" add --needs "$id_a" "task B")"
# A is pending: the only claimable task is A (B is blocked).
c1="$(bash "$CLI" claim)" || fail "claim found nothing while A is ready"
grep -q "/$id_a\$" <<<"$c1" || fail "first claim should be A $id_a, got $c1"
# A is now claimed (not done): B must still NOT be claimable -> claim exits 1.
if c="$(bash "$CLI" claim 2>/dev/null)"; then
  fail "claim returned a task while A claimed-not-done (got $c); B must be gated"
fi
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id_b" ]] || fail "B was claimed while its dep A is unmet"
# Complete A: B's dep is now satisfied -> claim returns B.
printf 'A done\n' | bash "$CLI" complete "$id_a" || fail "complete A failed"
c2="$(bash "$CLI" claim)" || fail "claim found nothing after A completed; B should be ready"
grep -q "/$id_b\$" <<<"$c2" || fail "claim after A done should be B $id_b, got $c2"
log "Test 15: PASS"

################################################################################
# Test 16: eligible ordering — a blocked task is skipped even if it has higher
# priority than a ready one. dep < priority for eligibility.
################################################################################
log "Test 16: claim skips a blocked higher-priority task for a ready one"
fresh_queue
bash "$CLI" init >/dev/null
# Dep D (low priority so it sorts late) and a high-priority blocked task that
# needs D, plus a ready mid-priority task. Claim must return a *ready* task,
# never the blocked one, regardless of the blocked one's higher priority.
id_d="$(bash "$CLI" add --priority 90 "dep D")"
id_blocked="$(bash "$CLI" add --priority 1 --needs "$id_d" "blocked hi-prio")"
id_ready="$(bash "$CLI" add --priority 50 "ready mid-prio")"
c="$(bash "$CLI" claim)" || fail "claim found nothing while ready tasks exist"
if grep -q "/$id_blocked\$" <<<"$c"; then
  fail "claim returned the blocked hi-prio task $id_blocked (dep unmet): $c"
fi
# It must have claimed a *ready* task: either D (p90) or the ready one (p50).
# By priority among ready tasks, the p50 ready task wins over p90 D.
grep -q "/$id_ready\$" <<<"$c" || fail "claim should pick ready p50 $id_ready over blocked p1, got $c"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id_blocked" ]] || fail "blocked task was claimed despite unmet dep"
log "Test 16: PASS"

################################################################################
# Test 17: cascade fail — A<-B<-C. When A dead-letters (past retry limit), its
# dependents B and C transitively move to failed/ with "blocked by" reasons,
# and pending/ ends up empty.
################################################################################
log "Test 17: dead-letter of A cascade-fails dependents B and C transitively"
fresh_queue
export WAI_QUEUE_RETRIES=1
bash "$CLI" init >/dev/null
id_a="$(bash "$CLI" add "task A")"
# Force the dependent (C) to sort BEFORE its parent (B) in cascade's pending
# scan (priority 01 vs 50): pass 1 sees C's dep B still pending (skip) and fails
# B; only pass 2 catches C. A single-pass (non-fixpoint) cascade leaves C in
# pending and fails the "pending empty" assertion below — so this pins the loop.
id_b="$(bash "$CLI" add --needs "$id_a" --priority 50 "task B")"
id_c="$(bash "$CLI" add --needs "$id_b" --priority 1 "task C")"
# Claim and fail A once: WAI_QUEUE_RETRIES=1 means attempt 1 >= 1 -> dead-letter.
bash "$CLI" claim >/dev/null   # claims A (only ready task; B,C blocked)
out="$(bash "$CLI" fail "$id_a" --reason "A boom")"
grep -q "failed" <<<"$out" || fail "fail A did not dead-letter: $out"
[[ -d "$WAI_QUEUE_DIR/failed/$id_a" ]] || fail "A not in failed/"
# Cascade: B and C must both be in failed/ now, with blocked-by reasons.
[[ -d "$WAI_QUEUE_DIR/failed/$id_b" ]] || fail "B did not cascade to failed/"
[[ -d "$WAI_QUEUE_DIR/failed/$id_c" ]] || fail "C did not cascade to failed/ (transitive)"
res_b="$(bash "$CLI" result "$id_b")"
grep -q "blocked by $id_a" <<<"$res_b" || fail "B result.md missing 'blocked by $id_a': $res_b"
res_c="$(bash "$CLI" result "$id_c")"
grep -q "blocked by $id_b" <<<"$res_c" || fail "C result.md missing 'blocked by $id_b': $res_c"
# pending/ must be empty afterward.
pcount=0
for d in "$WAI_QUEUE_DIR"/pending/*; do [[ -d "$d" ]] && pcount=$((pcount + 1)); done
[[ $pcount -eq 0 ]] || fail "pending/ not empty after cascade, got $pcount"
unset WAI_QUEUE_RETRIES
log "Test 17: PASS"

################################################################################
# Test 18: dead-dep on claim — A is already in failed/ and B (--needs A) is the
# only pending task. claim must dead-letter B (blocked by A) and exit 1 (nothing
# claimable), never claim B.
################################################################################
log "Test 18: claim dead-letters a candidate whose dep is already failed, exits 1"
fresh_queue
bash "$CLI" init >/dev/null
id_a="$(bash "$CLI" add "task A")"
id_b="$(bash "$CLI" add --needs "$id_a" "task B")"
# Force A into failed/ directly (no dependents present yet, so no cascade fires).
mv "$WAI_QUEUE_DIR/pending/50-$id_a" "$WAI_QUEUE_DIR/failed/$id_a"
printf 'error: forced\n' > "$WAI_QUEUE_DIR/failed/$id_a/result.md"
# B is the only pending candidate but its dep A is dead -> claim dead-letters B
# and finds nothing claimable (exit 1).
if bash "$CLI" claim >/dev/null 2>&1; then
  fail "claim returned 0 while the only candidate B has a dead dep (must exit 1)"
fi
[[ -d "$WAI_QUEUE_DIR/failed/$id_b" ]] || fail "claim did not dead-letter B with the dead dep"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id_b" ]] || fail "claim wrongly claimed B with a dead dep"
res_b="$(bash "$CLI" result "$id_b")"
grep -q "blocked by $id_a" <<<"$res_b" || fail "B result.md missing 'blocked by $id_a': $res_b"
# pending/ is now empty.
pcount=0
for d in "$WAI_QUEUE_DIR"/pending/*; do [[ -d "$d" ]] && pcount=$((pcount + 1)); done
[[ $pcount -eq 0 ]] || fail "pending/ not empty after claim dead-lettered B, got $pcount"
log "Test 18: PASS"

################################################################################
# Test 19: reap requeues a stale claim (claim.json.ts older than WAI_QUEUE_STALE)
# back to pending/ with attempt bumped and no claim.json left behind.
################################################################################
log "Test 19: reap requeues a stale claim and bumps attempt"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "stale task")"
bash "$CLI" claim >/dev/null || fail "claim failed"
[[ -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "task not claimed"
# Age the claim.json ts deterministically (no sleep) well past the staleness window.
cj="$WAI_QUEUE_DIR/claimed/$id/claim.json"
old_ts=$(( $(date +%s) - 100 ))
jq --argjson ts "$old_ts" '.ts = $ts' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"
reaped="$(WAI_QUEUE_STALE=1 bash "$CLI" reap)"
grep -q "$id" <<<"$reaped" || fail "reap did not report requeued id $id: $reaped"
[[ -d "$WAI_QUEUE_DIR/pending/50-$id" ]] || fail "reap did not requeue to pending/50-$id"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "reap left task in claimed/"
[[ ! -f "$WAI_QUEUE_DIR/pending/50-$id/claim.json" ]] || fail "reap left claim.json on requeued task"
jq -e '.attempt == 1' "$WAI_QUEUE_DIR/pending/50-$id/meta.json" >/dev/null || fail "reap did not bump attempt to 1"
log "Test 19: PASS"

################################################################################
# Test 20: reap leaves a fresh claim untouched (ts within WAI_QUEUE_STALE).
################################################################################
log "Test 20: reap leaves a fresh claim untouched"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "fresh task")"
bash "$CLI" claim >/dev/null || fail "claim failed"
WAI_QUEUE_STALE=1800 bash "$CLI" reap >/dev/null
[[ -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "reap requeued a fresh claim"
[[ -f "$WAI_QUEUE_DIR/claimed/$id/claim.json" ]] || fail "reap removed claim.json from a fresh claim"
[[ ! -d "$WAI_QUEUE_DIR/pending/50-$id" ]] || fail "fresh claim wrongly moved to pending/"
log "Test 20: PASS"

################################################################################
# Test 21: reap treats a claimed dir with no claim.json as an orphaned claim
# (a worker died between mv and stamp, or after losing its stamp) and requeues it.
################################################################################
log "Test 21: reap requeues an orphaned claim (missing claim.json)"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "orphan task")"
bash "$CLI" claim >/dev/null || fail "claim failed"
rm -f "$WAI_QUEUE_DIR/claimed/$id/claim.json"
WAI_QUEUE_STALE=1800 bash "$CLI" reap >/dev/null
[[ -d "$WAI_QUEUE_DIR/pending/50-$id" ]] || fail "reap did not requeue an orphaned claim"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "reap left orphaned claim in claimed/"
jq -e '.attempt == 1' "$WAI_QUEUE_DIR/pending/50-$id/meta.json" >/dev/null || fail "reap did not bump attempt on orphan"
log "Test 21: PASS"

################################################################################
# Test 22: reap dead-letters a task that stays stale past the retry limit,
# instead of requeueing it forever (livelock guard). Reaps count toward attempt.
################################################################################
log "Test 22: reap dead-letters a stale task at the retry cap"
fresh_queue
bash "$CLI" init >/dev/null
id="$(bash "$CLI" add "perpetually stale")"
bash "$CLI" claim >/dev/null || fail "claim failed"
cj="$WAI_QUEUE_DIR/claimed/$id/claim.json"
old_ts=$(( $(date +%s) - 100 ))
jq --argjson ts "$old_ts" '.ts = $ts' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"
# WAI_QUEUE_RETRIES=1: attempt 0 -> 1, 1 >= 1 -> dead-letter, not requeue.
out="$(WAI_QUEUE_STALE=1 WAI_QUEUE_RETRIES=1 bash "$CLI" reap)"
grep -q "$id" <<<"$out" || fail "reap did not report the dead-lettered id: $out"
[[ -d "$WAI_QUEUE_DIR/failed/$id" ]] || fail "reap did not dead-letter a task past the retry limit"
[[ ! -d "$WAI_QUEUE_DIR/claimed/$id" ]] || fail "reap left the dead-lettered task in claimed/"
[[ ! -d "$WAI_QUEUE_DIR/pending/50-$id" ]] || fail "reap requeued instead of dead-lettering at the cap"
bash "$CLI" result "$id" | grep -q "reaped past retry limit" || fail "dead-lettered task missing reaped reason"
log "Test 22: PASS"

echo "$PREFIX PASS: all queue tests passed"
exit 0

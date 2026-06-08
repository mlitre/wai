#!/usr/bin/env bash
#
# Usage: wai-queue <command> [args]
#
#   init                       Create the queue state dirs (idempotent). Prints $WAI_QUEUE_DIR.
#   add [opts] <prompt|->      Enqueue a task. <prompt> of '-' reads stdin. Prints the bare id.
#     --cwd <dir>              Working dir the task runs in (default: $PWD).
#     --priority <n>           Priority 0-99, lower = higher (default: 50, zero-padded to 2 digits).
#     --agent <type>           Subagent type (default: general-purpose).
#     --needs <id,...>         Comma-separated task ids this task depends on (default: none).
#   status                     Print per-state counts and one line per task.
#   result <id>                Print the result.md of a done/failed task (nonzero if absent).
#   cancel <id>                Remove a non-claimed task; refuses to cancel a claimed task.
#   claim                      Atomically claim the next eligible task. Prints claimed/<id>; nonzero if none.
#   complete <id> [--result-file <f>]   Finish a claimed task, store result, move to done/.
#   fail <id> [--reason <s>]   Fail a claimed task; retry, else dead-letter + cascade to dependents.
#   reap                       Requeue stale claims (older than WAI_QUEUE_STALE) back to pending/.
#
# Environment (with defaults):
#   WAI_QUEUE_DIR      Queue root.            ${XDG_DATA_HOME:-$HOME/.local/share}/wai/queue
#   WAI_QUEUE_RETRIES  Max attempts.          2
#   WAI_QUEUE_STALE    Stale-claim seconds.   1800
#   WAI_QUEUE_WORKER   Worker identity.       $(hostname || $HOSTNAME || unknown)-$$
#
set -euo pipefail

WAI_QUEUE_DIR="${WAI_QUEUE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wai/queue}"
WAI_QUEUE_RETRIES="${WAI_QUEUE_RETRIES:-2}"
WAI_QUEUE_STALE="${WAI_QUEUE_STALE:-1800}"
WAI_QUEUE_WORKER="${WAI_QUEUE_WORKER:-$(hostname 2>/dev/null || echo "${HOSTNAME:-unknown}")-$$}"

die() { echo "wai-queue: $*" >&2; exit 1; }

# find_task <id>: locate a task dir across states. On success, prints
# "<state> <path>" on stdout and exits 0. On miss, exits 1 (no output).
# A valid task lives in exactly one state; claimed is checked before pending
# so a transiently-duplicated task is never treated as cancelable pending.
find_task() {
  local id="$1" d state
  for state in claimed done failed; do
    if [[ -d "$WAI_QUEUE_DIR/$state/$id" ]]; then
      echo "$state $WAI_QUEUE_DIR/$state/$id"
      return 0
    fi
  done
  for d in "$WAI_QUEUE_DIR"/pending/*-"$id"; do
    if [[ -d "$d" ]]; then
      echo "pending $d"
      return 0
    fi
  done
  return 1
}

cmd_init() {
  mkdir -p "$WAI_QUEUE_DIR"/{pending,claimed,done,failed,bin}
  echo "$WAI_QUEUE_DIR"
}

cmd_add() {
  local cwd="$PWD" priority=50 agent="general-purpose" needs="" prompt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd)      cwd="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      --agent)    agent="$2"; shift 2 ;;
      --needs)    needs="$2"; shift 2 ;;
      --)         shift; break ;;
      -*)         [[ "$1" == "-" ]] && break; die "add: unknown option: $1" ;;
      *)          break ;;
    esac
  done
  [[ $# -ge 1 ]] || die "add: missing <prompt>"
  if [[ "$1" == "-" ]]; then
    prompt="$(cat)"
  else
    prompt="$1"
  fi

  [[ "$priority" =~ ^[0-9]+$ ]] || die "add: --priority must be a non-negative integer"
  priority=$((10#$priority))  # force base-10 so leading zeros (08, 010) aren't read as octal
  (( priority >= 0 && priority <= 99 )) || die "add: --priority must be an integer 0-99"
  local prio2
  prio2="$(printf '%02d' "$priority")"

  local id created needs_json
  id="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}"
  created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Build the needs JSON array (empty -> []).
  if [[ -z "$needs" ]]; then
    needs_json='[]'
  else
    needs_json="$(printf '%s' "$needs" | jq -R 'split(",")')"
  fi

  # Build the task in a dot-prefixed staging dir on the same filesystem, then
  # atomically rename it into pending/ so a concurrent claimer never observes a
  # half-built task dir (prompt.md/meta.json appearing piecemeal).
  local taskdir="$WAI_QUEUE_DIR/pending/${prio2}-${id}"
  local stagedir="$WAI_QUEUE_DIR/.staging/${id}"
  mkdir -p "$stagedir"
  printf '%s\n' "$prompt" > "$stagedir/prompt.md"
  jq -n \
    --arg id "$id" \
    --arg cwd "$cwd" \
    --argjson priority "$priority" \
    --arg agent "$agent" \
    --argjson needs "$needs_json" \
    --arg created "$created" \
    '{id:$id, cwd:$cwd, priority:$priority, agent:$agent, needs:$needs, created:$created, attempt:0}' \
    > "$stagedir/meta.json"

  [[ -e "$taskdir" ]] && { rm -rf "$stagedir"; die "add: task id collision: $id"; }
  mv "$stagedir" "$taskdir"

  echo "$id"
}

cmd_status() {
  local state count
  for state in pending claimed done failed; do
    count=0
    if [[ -d "$WAI_QUEUE_DIR/$state" ]]; then
      for d in "$WAI_QUEUE_DIR/$state"/*; do
        [[ -d "$d" ]] && count=$((count + 1))
      done
    fi
    echo "$state $count"
  done

  # One line per task across all states.
  for state in pending claimed done failed; do
    [[ -d "$WAI_QUEUE_DIR/$state" ]] || continue
    for d in "$WAI_QUEUE_DIR/$state"/*; do
      [[ -d "$d" ]] || continue
      local meta="$d/meta.json"
      [[ -f "$meta" ]] || continue
      local id prio attempt needs
      id="$(jq -r '.id' "$meta")"
      prio="$(jq -r '.priority' "$meta")"
      attempt="$(jq -r '.attempt' "$meta")"
      needs="$(jq -rc '.needs' "$meta")"
      echo "$id  $state  prio=$prio  attempt=$attempt  needs=$needs"
    done
  done
}

cmd_result() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "result: missing <id>"
  local state
  for state in done failed; do
    local rf="$WAI_QUEUE_DIR/$state/$id/result.md"
    if [[ -f "$rf" ]]; then
      cat "$rf"
      return 0
    fi
  done
  die "result: no result for id: $id"
}

cmd_cancel() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "cancel: missing <id>"
  local hit state path
  if ! hit="$(find_task "$id")"; then
    die "cancel: no such task: $id"
  fi
  state="${hit%% *}"
  path="${hit#* }"
  if [[ "$state" == "claimed" ]]; then
    die "cancel: refusing to cancel a claimed task: $id"
  fi
  rm -rf "$path"
}

# claim: atomically claim the highest-priority pending task. Scans pending/
# in sort order (priority prefix then time-sortable id = priority-then-FIFO)
# and races to `mv` each candidate into claimed/<id>. The first winning mv
# stamps claim.json and prints "claimed/<id>"; a losing mv (another worker won)
# falls through to the next candidate. Exits 1 with no output if nothing is
# claimable.
cmd_claim() {
  local d id cdir pdir blocker
  for d in $(claim_candidates); do
    id="${d#*-}"
    cdir="$WAI_QUEUE_DIR/claimed/$id"
    pdir="$WAI_QUEUE_DIR/pending/$d"
    # DAG gating: a candidate is only eligible when every need is in done/.
    # If any need is already in failed/, the candidate is dead — dead-letter it
    # (blocked by <need>) and keep scanning. If any need is neither done nor
    # failed (still pending/claimed), it's not yet eligible — skip and continue.
    blocker="$(dep_blocker "$pdir")"
    if [[ "$blocker" == failed:* ]]; then
      local need="${blocker#failed:}"
      # Collision-safe: never bury into an existing failed/<id> dir.
      [[ -e "$WAI_QUEUE_DIR/failed/$id" ]] && continue
      printf 'blocked by %s\n' "$need" > "$pdir/result.md"
      mv "$pdir" "$WAI_QUEUE_DIR/failed/$id"
      continue
    fi
    [[ "$blocker" == pending:* ]] && continue
    # Guard against POSIX `mv into an existing dir`: if claimed/$id already
    # exists, mv would bury the source *inside* it (claimed/$id/<prio>-$id/) and
    # return 0, clobbering an existing claim.json. Skip such a candidate.
    [[ -e "$cdir" ]] && continue
    if mv "$pdir" "$cdir" 2>/dev/null; then
      # Stamp claim.json crash-atomically (tmp -> rename), so the dir is never
      # parked in claimed/ without a claim.json the reaper keys on.
      jq -n \
        --arg worker "$WAI_QUEUE_WORKER" \
        --argjson ts "$(date +%s)" \
        '{worker:$worker, ts:$ts}' \
        > "$cdir/claim.json.tmp.$$" \
        && mv "$cdir/claim.json.tmp.$$" "$cdir/claim.json"
      echo "$cdir"
      return 0
    fi
  done
  return 1
}

# claim_candidates: print pending dir basenames in claim order (sorted by name,
# which is "<prio>-<id>": priority ascending, then time-sortable id = FIFO).
# Prints nothing when pending/ is empty.
claim_candidates() {
  local d
  for d in "$WAI_QUEUE_DIR"/pending/*; do
    [[ -d "$d" ]] || continue
    basename "$d"
  done | sort
}

# dep_blocker <taskdir>: inspect the task's meta.needs (a JSON array) and report
# its eligibility. Prints "failed:<need>" if a need is already dead-lettered
# (this task is dead), "pending:<need>" if a need is not yet in done/ (not yet
# eligible), or nothing (every need is in done/, so the task is claimable). An
# empty needs array always prints nothing (no deps -> eligible).
dep_blocker() {
  local taskdir="$1" need pending=""
  local meta="$taskdir/meta.json"
  [[ -f "$meta" ]] || return 0
  while IFS= read -r need; do
    [[ -n "$need" ]] || continue
    # A failed need makes the task dead regardless of other deps: report it
    # immediately (failed/ wins over a still-pending dep).
    if [[ -d "$WAI_QUEUE_DIR/failed/$need" ]]; then
      printf 'failed:%s\n' "$need"
      return 0
    fi
    # Remember the first unmet (not-yet-done) need, but keep scanning in case a
    # later need is in failed/ (which takes precedence).
    if [[ -z "$pending" && ! -d "$WAI_QUEUE_DIR/done/$need" ]]; then
      pending="$need"
    fi
  done < <(jq -r '.needs[]? // empty' "$meta")
  [[ -n "$pending" ]] && printf 'pending:%s\n' "$pending"
  return 0
}

# complete <id> [--result-file <f>]: finalize a claimed task as done. Writes
# result.md (from --result-file, else stdin) then moves claimed/<id> -> done/<id>.
cmd_complete() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "complete: missing <id>"
  shift
  local result_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --result-file) result_file="$2"; shift 2 ;;
      *) die "complete: unknown option: $1" ;;
    esac
  done
  local hit
  hit="$(find_task "$id")" || die "complete: no such task: $id"
  [[ "${hit%% *}" == "claimed" ]] || die "complete: task not claimed: $id"
  if [[ -n "$result_file" ]]; then
    [[ -f "$result_file" ]] || die "complete: no such result file: $result_file"
    cat "$result_file" > "$WAI_QUEUE_DIR/claimed/$id/result.md"
  else
    cat > "$WAI_QUEUE_DIR/claimed/$id/result.md"
  fi
  rm -f "$WAI_QUEUE_DIR/claimed/$id/claim.json"
  mv "$WAI_QUEUE_DIR/claimed/$id" "$WAI_QUEUE_DIR/done/$id"
}

# fail <id> [--reason <s>]: a claimed task failed. Bump meta.attempt; if it
# reaches WAI_QUEUE_RETRIES, dead-letter to failed/<id> with result.md =
# "error: <reason>". Otherwise drop claim.json and requeue to
# pending/<prio>-<id>. Prints the resulting state ("failed" or "pending").
cmd_fail() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "fail: missing <id>"
  shift
  local reason=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) die "fail: unknown option: $1" ;;
    esac
  done
  local hit
  hit="$(find_task "$id")" || die "fail: no such task: $id"
  [[ "${hit%% *}" == "claimed" ]] || die "fail: task not claimed: $id"
  local cdir="$WAI_QUEUE_DIR/claimed/$id"

  local meta="$cdir/meta.json" attempt priority
  attempt="$(jq -r '.attempt // 0' "$meta")"
  attempt=$((attempt + 1))
  local tmp="$meta.tmp.$$"
  jq --argjson attempt "$attempt" '.attempt = $attempt' "$meta" > "$tmp"
  mv "$tmp" "$meta"

  if [[ "$attempt" -ge "$WAI_QUEUE_RETRIES" ]]; then
    printf 'error: %s\n' "$reason" > "$cdir/result.md"
    rm -f "$cdir/claim.json"
    mv "$cdir" "$WAI_QUEUE_DIR/failed/$id"
    # Now that this task is terminal-failed, transitively dead-letter every
    # dependent (and their dependents) that can no longer ever run.
    cascade_failures
    echo "failed $id"
  else
    priority="$(jq -r '.priority' "$meta")"
    local prio2
    prio2="$(printf '%02d' "$priority")"
    rm -f "$cdir/claim.json"
    mv "$cdir" "$WAI_QUEUE_DIR/pending/${prio2}-${id}"
    echo "pending $id"
  fi
}

# cascade_failures: fixpoint sweep that dead-letters every task with a need now
# in failed/. Repeatedly scans pending/ and claimed/; each task whose dep_blocker
# reports "failed:<need>" is moved to failed/<id> with result.md = "blocked by
# <need>". Loops the whole sweep until a pass makes no moves, so transitive
# chains (A->B->C) all collapse. The claimed/ scan is a safe no-op in practice
# (a claimed task's deps were all in done/ at claim time, and done/ is terminal)
# but is kept per spec.
cascade_failures() {
  local moved=1 state d id blocker need
  while (( moved )); do
    moved=0
    for state in pending claimed; do
      for d in "$WAI_QUEUE_DIR/$state"/*; do
        [[ -d "$d" ]] || continue
        blocker="$(dep_blocker "$d")"
        [[ "$blocker" == failed:* ]] || continue
        need="${blocker#failed:}"
        # pending dirs are "<prio>-<id>"; claimed dirs are bare "<id>".
        if [[ "$state" == pending ]]; then
          id="$(basename "$d")"; id="${id#*-}"
        else
          id="$(basename "$d")"
        fi
        # Collision-safe: never bury into an existing failed/<id> dir.
        [[ -e "$WAI_QUEUE_DIR/failed/$id" ]] && continue
        printf 'blocked by %s\n' "$need" > "$d/result.md"
        rm -f "$d/claim.json"
        mv "$d" "$WAI_QUEUE_DIR/failed/$id"
        moved=1
      done
    done
  done
}

# reap: requeue stale claims. For each claimed/<id>, if its claim.json.ts is
# older than WAI_QUEUE_STALE seconds — or claim.json is missing entirely (a
# worker that died between the claim mv and the stamp, or lost its stamp) — bump
# meta.attempt, drop claim.json, and move the task back to pending/<prio>-<id>
# so another worker can pick it up. Fresh claims are left untouched. Prints each
# requeued id. Always exits 0.
cmd_reap() {
  local now d id meta cjson ts priority prio2 attempt tmp
  now="$(date +%s)"
  for d in "$WAI_QUEUE_DIR"/claimed/*; do
    [[ -d "$d" ]] || continue
    id="$(basename "$d")"
    meta="$d/meta.json"
    [[ -f "$meta" ]] || continue   # not a real task dir; leave it alone
    cjson="$d/claim.json"
    if [[ -f "$cjson" ]]; then
      ts="$(jq -r '.ts // 0' "$cjson")"
      (( now - ts > WAI_QUEUE_STALE )) || continue   # fresh claim, skip
    fi
    priority="$(jq -r '.priority' "$meta")"
    prio2="$(printf '%02d' "$priority")"
    # Collision-safe (check before any mutation): never bury into an existing
    # pending/<prio>-<id>, and don't half-requeue if the target is taken.
    [[ -e "$WAI_QUEUE_DIR/pending/${prio2}-${id}" ]] && continue
    attempt="$(jq -r '.attempt // 0' "$meta")"
    attempt=$((attempt + 1))
    tmp="$meta.tmp.$$"
    jq --argjson attempt "$attempt" '.attempt = $attempt' "$meta" > "$tmp"
    mv "$tmp" "$meta"
    rm -f "$cjson"
    mv "$d" "$WAI_QUEUE_DIR/pending/${prio2}-${id}"
    echo "$id"
  done
}

main() {
  [[ $# -ge 1 ]] || die "usage: wai-queue <init|add|status|result|cancel|claim|complete|fail|reap> [args]"
  local sub="$1"; shift
  case "$sub" in
    init)     cmd_init "$@" ;;
    add)      cmd_add "$@" ;;
    status)   cmd_status "$@" ;;
    result)   cmd_result "$@" ;;
    cancel)   cmd_cancel "$@" ;;
    claim)    cmd_claim "$@" ;;
    complete) cmd_complete "$@" ;;
    fail)     cmd_fail "$@" ;;
    reap)     cmd_reap "$@" ;;
    *)        die "unknown subcommand: $sub" ;;
  esac
}

main "$@"

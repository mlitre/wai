#!/usr/bin/env bash
#
# Usage: wai-queue <command> [args]
#
#   init                       Create the queue state dirs (idempotent). Prints $WAI_QUEUE_DIR.
#   add [opts] <prompt|->      Enqueue a task. <prompt> of '-' reads stdin. Prints the bare id.
#     --cwd <dir>              Working dir the task runs in (default: $PWD).
#     --priority <n>           Priority, lower = higher (default: 50, zero-padded to 2 digits).
#     --agent <type>           Subagent type (default: general-purpose).
#     --needs <id,...>         Comma-separated task ids this task depends on (default: none).
#   status                     Print per-state counts and one line per task.
#   result <id>                Print the result.md of a done/failed task (nonzero if absent).
#   cancel <id>                Remove a non-claimed task; refuses to cancel a claimed task.
#
# Environment (with defaults):
#   WAI_QUEUE_DIR      Queue root.            ${XDG_DATA_HOME:-$HOME/.local/share}/wai/queue
#   WAI_QUEUE_RETRIES  Max attempts.          2
#   WAI_QUEUE_STALE    Stale-claim seconds.   1800
#   WAI_QUEUE_WORKER   Worker identity.       $(hostname)-$$
#
set -euo pipefail

WAI_QUEUE_DIR="${WAI_QUEUE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wai/queue}"
WAI_QUEUE_RETRIES="${WAI_QUEUE_RETRIES:-2}"
WAI_QUEUE_STALE="${WAI_QUEUE_STALE:-1800}"
WAI_QUEUE_WORKER="${WAI_QUEUE_WORKER:-$(hostname)-$$}"

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

  local taskdir="$WAI_QUEUE_DIR/pending/${prio2}-${id}"
  mkdir -p "$taskdir"
  printf '%s\n' "$prompt" > "$taskdir/prompt.md"
  jq -n \
    --arg id "$id" \
    --arg cwd "$cwd" \
    --argjson priority "$priority" \
    --arg agent "$agent" \
    --argjson needs "$needs_json" \
    --arg created "$created" \
    '{id:$id, cwd:$cwd, priority:$priority, agent:$agent, needs:$needs, created:$created, attempt:0}' \
    > "$taskdir/meta.json"

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

main() {
  [[ $# -ge 1 ]] || die "usage: wai-queue <init|add|status|result|cancel> [args]"
  local sub="$1"; shift
  case "$sub" in
    init)   cmd_init "$@" ;;
    add)    cmd_add "$@" ;;
    status) cmd_status "$@" ;;
    result) cmd_result "$@" ;;
    cancel) cmd_cancel "$@" ;;
    *)      die "unknown subcommand: $sub" ;;
  esac
}

main "$@"

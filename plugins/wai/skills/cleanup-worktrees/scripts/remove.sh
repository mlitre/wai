#!/usr/bin/env bash
# remove.sh, Remove a single worktree, optionally with --force.
#
# Usage: remove.sh <worktree-path> [--force]
#
# Wraps `git worktree remove` so the caller doesn't have to inline the retry.
# Refuses to remove the cwd or the main worktree.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: remove.sh <worktree-path> [--force]" >&2
  exit 2
fi

wt_path="$1"
force_flag=""
if [[ "${2:-}" == "--force" ]]; then
  force_flag="--force"
fi

abs_wt="$(cd "${wt_path}" 2>/dev/null && pwd || true)"
if [[ -z "${abs_wt}" ]]; then
  echo "remove.sh: worktree path not found: ${wt_path}" >&2
  exit 1
fi

# Refuse if cwd is inside the worktree being removed.
cwd_abs="$(pwd)"
case "${cwd_abs}/" in
  "${abs_wt}/"*)
    echo "remove.sh: cwd is inside the worktree being removed; cd elsewhere first" >&2
    exit 1
    ;;
esac

# Refuse if this is the main worktree.
main_wt="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
if [[ "${abs_wt}" == "${main_wt}" ]]; then
  echo "remove.sh: refusing to remove the main worktree" >&2
  exit 1
fi

git worktree remove ${force_flag} "${abs_wt}"

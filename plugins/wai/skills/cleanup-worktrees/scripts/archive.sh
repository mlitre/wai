#!/usr/bin/env bash
# archive.sh, Mirror untracked .md files from a worktree into the main worktree.
#
# Usage: archive.sh <worktree-path> <main-worktree-path>
#
# Copies each untracked *.md file from <worktree-path> into the same relative
# path under <main-worktree-path>, never overwriting (cp -n). Anything that is
# not a .md file is ignored on purpose, session-state files like .ds/server.pid
# are disposable, planning/spec/review notes are not.
#
# Output: one line per file copied + a final summary line:
#   COPIED  <relpath>
#   SKIPPED <relpath>  (already exists in main)
#   SUMMARY <copied>/<total> .md files archived
#
# Read-only relative to the source worktree; writes only into the main worktree.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: archive.sh <worktree-path> <main-worktree-path>" >&2
  exit 2
fi

src_wt="$1"
main_wt="$2"

if [[ ! -d "${src_wt}" ]]; then
  echo "archive.sh: source worktree not found: ${src_wt}" >&2
  exit 1
fi
if [[ ! -d "${main_wt}" ]]; then
  echo "archive.sh: main worktree not found: ${main_wt}" >&2
  exit 1
fi

if [[ "$(cd "${src_wt}" && pwd)" == "$(cd "${main_wt}" && pwd)" ]]; then
  echo "archive.sh: refusing to archive a worktree into itself" >&2
  exit 1
fi

copied=0
skipped=0
total=0

# Collect untracked .md files relative to src worktree.
while IFS= read -r rel; do
  [[ -z "${rel}" ]] && continue
  total=$((total + 1))
  src="${src_wt%/}/${rel}"
  dst="${main_wt%/}/${rel}"
  if [[ -e "${dst}" ]]; then
    printf "SKIPPED %s\n" "${rel}"
    skipped=$((skipped + 1))
    continue
  fi
  /usr/bin/mkdir -p "$(dirname "${dst}")"
  if /usr/bin/cp -n "${src}" "${dst}"; then
    printf "COPIED  %s\n" "${rel}"
    copied=$((copied + 1))
  else
    printf "SKIPPED %s\n" "${rel}"
    skipped=$((skipped + 1))
  fi
done < <(git -C "${src_wt}" ls-files --others --exclude-standard 2>/dev/null | grep '\.md$' || true)

printf "SUMMARY %d/%d .md files archived (%d skipped because they already exist in main)\n" \
  "${copied}" "${total}" "${skipped}"

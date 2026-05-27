#!/usr/bin/env bash
# scan.sh, Enumerate non-main worktrees and classify each by merge state.
#
# Output: TSV, one row per non-main worktree.
# Columns: path	branch	pr_number	pr_merged_at	uncommitted	unpushed_count	untracked_md_count	state
#
# Read-only. Never modifies repo state.

set -euo pipefail

# Resolve the main worktree (first entry of `git worktree list --porcelain`).
main_wt="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
if [[ -z "${main_wt}" ]]; then
  echo "scan.sh: could not determine main worktree root" >&2
  exit 1
fi

cd "${main_wt}"

# Use gh if available and authenticated, else fall back to git --merged.
use_gh=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  use_gh=1
fi

# Default upstream branch (origin/HEAD -> origin/<default>).
default_remote_ref="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_remote_ref#refs/remotes/origin/}"
default_branch="${default_branch:-main}"

# Pre-compute list of branches strictly merged into origin/<default> for fallback mode.
merged_branches=""
if [[ ${use_gh} -eq 0 ]]; then
  merged_branches="$(git branch --merged "origin/${default_branch}" 2>/dev/null | sed 's/^[* ] //' | sort -u || true)"
fi

# Emit header? No, keep output minimal so callers can parse with awk/cut.

# Iterate worktrees.
git worktree list --porcelain | awk '
  /^worktree /{wt=$2}
  /^HEAD /{head=$2}
  /^branch /{br=$2}
  /^detached/{br="(detached)"}
  /^$/{
    if (wt != "" && wt != "'"${main_wt}"'") {
      printf "%s\t%s\t%s\n", wt, br, head
    }
    wt=""; br=""; head=""
  }
  END{
    if (wt != "" && wt != "'"${main_wt}"'") {
      printf "%s\t%s\t%s\n", wt, br, head
    }
  }
' | while IFS=$'\t' read -r wt_path branch_ref head_sha; do
  branch="${branch_ref#refs/heads/}"
  if [[ "${branch}" == "(detached)" || -z "${branch}" ]]; then
    branch="(detached)"
  fi

  # uncommitted
  uncommitted=0
  if [[ -n "$(git -C "${wt_path}" status --porcelain 2>/dev/null | head -n1)" ]]; then
    uncommitted=1
  fi

  # unpushed
  unpushed=0
  if upstream="$(git -C "${wt_path}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    unpushed="$(git -C "${wt_path}" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
  fi

  # untracked .md count
  untracked_md=0
  if [[ -d "${wt_path}" ]]; then
    untracked_md="$(git -C "${wt_path}" ls-files --others --exclude-standard 2>/dev/null | grep -c '\.md$' || true)"
  fi

  # Merge state lookup.
  pr_number=""
  pr_merged_at=""
  state="open"
  if [[ "${branch}" == "(detached)" ]]; then
    state="unknown"
  elif [[ ${use_gh} -eq 1 ]]; then
    pr_json="$(gh pr list --state merged --head "${branch}" --json number,mergedAt --limit 1 2>/dev/null || echo '[]')"
    pr_number="$(printf '%s' "${pr_json}" | sed -n 's/.*"number":\([0-9]*\).*/\1/p')"
    pr_merged_at="$(printf '%s' "${pr_json}" | sed -n 's/.*"mergedAt":"\([^"]*\)".*/\1/p')"
    if [[ -n "${pr_number}" ]]; then
      state="merged"
    fi
  else
    # Fallback: name match against `git branch --merged`.
    if printf '%s\n' "${merged_branches}" | grep -qx "${branch}"; then
      state="merged"
    fi
  fi

  # Refine merged → merged-clean / merged-archive / merged-dirty.
  if [[ "${state}" == "merged" ]]; then
    if [[ "${uncommitted}" -ne 0 || "${unpushed}" -ne 0 ]]; then
      state="merged-dirty"
    elif [[ "${untracked_md}" -gt 0 ]]; then
      state="merged-archive"
    else
      # Check whether any non-md untracked junk remains. If so, still merged-clean
      # but the removal will need --force; mark for caller.
      junk_count="$(git -C "${wt_path}" ls-files --others --exclude-standard 2>/dev/null | grep -cv '\.md$' || true)"
      if [[ "${junk_count}" -gt 0 ]]; then
        state="merged-dirty"
      else
        state="merged-clean"
      fi
    fi
  fi

  printf "%s\t%s\t%s\t%s\t%d\t%d\t%d\t%s\n" \
    "${wt_path}" "${branch}" "${pr_number}" "${pr_merged_at}" \
    "${uncommitted}" "${unpushed}" "${untracked_md}" "${state}"
done

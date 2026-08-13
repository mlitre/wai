---
name: cleanup-worktrees
description: Remove git worktrees whose branches already merged via a closed GitHub PR, surfacing uncommitted changes, unpushed commits, and untracked notes before deleting anything. Use when the user asks to clean up or prune worktrees, or which are safe to remove after PRs land. Prefer it over hand-rolled `git worktree list` plus `gh pr list`.
---

# cleanup-worktrees

## What this skill does

EVerest-style multi-worktree workflows accumulate `.worktrees/<name>` directories after PRs merge. The branches still exist, but the on-disk checkouts are dead weight, they confuse `git worktree list`, eat disk, and hide stale plan/spec files. This skill walks every worktree, classifies it (still-open / merged / unknown), shows the user what would be lost if it's removed, and only acts after explicit confirmation.

The skill is intentionally conservative. Worktree removal can drop unpushed commits and untracked files; the goal is to make the user comfortable that nothing important is being thrown away before any `git worktree remove` runs.

## When to invoke

Trigger phrases include "clean up worktrees", "remove merged worktrees", "prune worktrees", "which worktrees can I delete", "delete worktrees for landed PRs", "tidy worktrees", "garbage collect worktrees". Also auto-trigger when the user says something like "are any of my worktrees ready to remove" or asks for a status table of worktrees.

**Recommended cadence:** weekly, or after a merge.

Do not trigger for:
- Creating new worktrees (use the worktree-creation skills).
- Pruning stale-but-not-merged branches.
- Bare-repo cleanup or reflog garbage collection.

## High-level flow

The skill is one read-only scan followed by an interactive removal loop:

1. **Scan**: enumerate worktrees, classify each as merged/open/unknown, collect safety signals.
2. **Present**: show one table the user can act on. Caveman-mode friendly: every row tells the user what would happen.
3. **Confirm**: ask the user which worktrees to remove. Default to "all merged + clean"; let them deselect.
4. **Archive**: for each removable worktree, mirror untracked `.md` files into the main worktree under the same relative path.
5. **Remove**: `git worktree remove [--force]` for each confirmed entry.
6. **Optional branch delete**: for each removed worktree, ask whether to also `git branch -D <branch>`.
7. **Final**: `git worktree prune` to clear stale admin records.

Never combine steps. Always show the user the table from step 2 and wait for their response before destroying anything.

## Step 1, Scan

Run from the **main worktree root** (use `git rev-parse --show-toplevel` if uncertain). Use the helper:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/cleanup-worktrees/scripts/scan.sh
```

The script prints a TSV with these columns, one row per non-main worktree:

```
path<TAB>branch<TAB>pr_number<TAB>pr_merged_at<TAB>uncommitted<TAB>unpushed_count<TAB>untracked_md_count<TAB>state
```

`state` values:

| value | meaning |
|---|---|
| `merged-clean` | PR merged, no uncommitted, no unpushed, untracked are only `.md` notes or empty |
| `merged-dirty` | PR merged, but has uncommitted or unpushed work, needs `--force` and risks data loss |
| `merged-archive` | PR merged, untracked `.md` plans/specs present that would be lost without archiving |
| `open` | No merged PR for this branch's head, leave alone |
| `unknown` | `gh` returned nothing for the branch (no upstream / detached / never pushed); leave alone unless user explicitly opts in |

If `gh` is not installed or `gh auth status` fails, fall back to `git branch --merged <default-branch>` against the upstream of the main branch (`git rev-parse --abbrev-ref --symbolic-full-name @{upstream}` from the main worktree). Tell the user the fallback is less accurate because squash-merged PRs won't show as merged via plain `--merged`.

The scan is **read-only**. It must not run `git worktree remove`, `git branch -D`, or `git push`.

## Step 2, Present

Render the scan output as a Markdown table in the chat. One row per worktree, columns: `Worktree`, `Branch`, `PR`, `Merged`, `Uncommitted`, `Unpushed`, `Untracked .md`, `State`. Use the PR number as a link (`#1234`) if available. Sort by state: `merged-clean` first, then `merged-archive`, `merged-dirty`, `open`, `unknown`.

Above the table, say one sentence about what the skill will do next. Below the table, ask the user to confirm. Example:

> Found 3 worktrees backed by merged PRs. Default plan: remove all `merged-clean` and `merged-archive` (archiving first); skip `merged-dirty` unless you say otherwise. OK?

Stop and wait for the user's response. If they say "go ahead" / "yes" / "ok", proceed with the default plan. If they want a different selection, accept paths or worktree names.

## Step 3, Confirm

The user response determines `TO_REMOVE` (list of worktree paths) and `INCLUDE_DIRTY` (bool). Echo the final plan back as a short list, one line per worktree, before any destructive action. Example:

> Removing:
> - `.worktrees/feat-foo` (branch `feat/foo`, PR #1234), archive 2 .md files first
> - `.worktrees/feat-bar` (branch `feat/bar`, PR #1240), clean, no archive needed
>
> Skipping `merged-dirty` worktree `.worktrees/feat-baz` (3 unpushed commits).

Do not proceed until the user confirms this echo. The user has already approved removal in step 2; this echo exists so they catch fat-finger mistakes (e.g., a typo of `feat-baz` accidentally included).

## Step 4, Archive untracked notes

For each worktree being removed, mirror any untracked `.md` files into the **main worktree** at the same relative path. Skip everything else. This intentionally drops session-state files like `.ds/server.pid`, but preserves planning/spec/review notes under `docs/`, `thoughts/`, `tasks/`, etc.

Algorithm:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/cleanup-worktrees/scripts/archive.sh <worktree-path> <main-worktree-path>
```

The helper:
- Lists untracked files in the worktree (`git -C <wt> ls-files --others --exclude-standard`).
- Keeps only `*.md` matches.
- For each match, creates the destination directory under main if needed.
- Copies with `cp -n` (no-clobber) so existing main-side files are never overwritten.
- Reports the count and any skipped collisions back to the caller.

Show the user the per-worktree archive summary before the actual `git worktree remove` call (e.g., "archived 3 of 3 .md files into main").

## Step 5, Remove

For each worktree in the confirmed list:

```bash
git worktree remove "<path>"
```

If that fails because of untracked or modified files (after step 4 archiving, meaning the leftover is genuinely non-Markdown junk like build outputs or session state), and the user confirmed in step 3 that `merged-dirty` entries should be force-removed, retry with:

```bash
git worktree remove --force "<path>"
```

Never `--force` without explicit user OK. If the user did not approve force for this row, abort the row, mark it skipped, and continue to the next.

After the loop, run:

```bash
git worktree prune
```

to clear admin records for any worktrees the user removed manually before invoking the skill.

## Step 6, Optional branch delete

For each successfully removed worktree, ask the user whether to delete the local branch ref. Default answer is **no** (keep it). Phrase the prompt with the merge target so they can sanity-check, e.g.:

> Branch `feat/foo` (merged via PR #1234 on 2026-05-19) is no longer checked out anywhere. Delete the local ref?

If yes:

```bash
git branch -D <branch>
```

Use `-D` (not `-d`) because squash-merged branches won't pass `-d`'s ancestry check. Do not delete remote refs, that's the PR-cleanup workflow, not this one.

If multiple worktrees were removed, offer a batch confirmation ("delete all of them?") to avoid yes/no spam.

## Step 7, Report

End with a short summary the user can read at a glance:

- N worktrees removed (list).
- M worktrees skipped and why.
- K branches deleted.
- L `.md` files archived into main.

Caveman mode is on for most invocations, keep the summary tight. Fragments OK.

## Safety rules

1. **Never run `git worktree remove` from inside the worktree being removed.** Always `cd` to the main worktree root first or pass an absolute path while at a different cwd.
2. **Never delete a branch whose worktree is still on disk.** Do branch deletes *after* the worktree removal succeeded for that row.
3. **Never `git push` anything.** This skill is local-only.
4. **Never run on `main` write commands.** Removing worktrees is allowed on any branch (it's a repo-admin op), but if the user's main worktree HEAD happens to *be* one of the branches you're being asked to delete, refuse and tell them to check out a different branch first.
5. **Never overwrite files in the main worktree during archive.** `cp -n` only.
6. **Never trust state from a stale scan.** If the user takes long enough between step 2 and step 4 that the state might have changed (e.g., they switched branches), re-run the scan before destructive actions.

## Edge cases worth knowing

- **Squash merges**: the branch HEAD will not match any commit on the default branch. That's why we use `gh pr list --head <branch>` instead of `git branch --merged`. Plain `--merged` will miss almost every squash-merged PR.
- **Detached HEAD worktrees**: `git worktree list` will show `(detached HEAD)` instead of a branch name. The scan classifies them as `unknown`.
- **Forked branches**: a worktree branch might track a fork rather than the upstream `origin`. `gh pr list --head <branch>` queries the current repo's `origin`. If `gh` returns no result but the user knows the PR was merged elsewhere, treat it as `unknown` and ask.
- **No `gh` auth**: fall back to `git branch --merged`, warn the user, and exclude any worktree whose branch isn't a strict ancestor of the upstream default branch.
- **Worktree path contains spaces**: quote everything; the helpers already do.
- **Main worktree path lookup**: get it once with `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'`. The first entry is always the main one.

## Helper scripts

The skill ships three scripts under `scripts/`:

- `scan.sh`, read-only classification (step 1).
- `archive.sh`, mirror untracked `.md` files into main (step 4).
- `remove.sh`, wrapper around `git worktree remove` that retries with `--force` only when explicitly told to (step 5). Optional; you can inline the `git worktree remove` calls instead if it's clearer in context.

Read each script before running it the first time so you understand what it touches. They are kept short on purpose.

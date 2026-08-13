---
name: resolving-merge-conflicts
description: Resolve an in-progress git merge or rebase conflict hunk by hunk. Use when a merge or rebase stops with conflicts, when `git status` shows unmerged paths, or when the user says they are stuck in a rebase, mid-merge, or have conflict markers in a file.
allowed-tools: Bash, Read, Edit, Grep, Glob
inspired-by:
  - mattpocock/skills/engineering/resolving-merge-conflicts
---

# Resolving merge conflicts

A conflict is not a text problem. It is two intents disagreeing, and both sides look locally correct, which is exactly why resolving from the hunk alone produces code that compiles and means the wrong thing.

Resolve by **intent traced to its primary source**, then finish the operation.

## Invariant, always resolve

Never run `git merge --abort`, `git rebase --abort`, or `git reset --hard` to escape a conflict. Abort is the move that looks safe and silently discards every resolution already made, including the ones that were right. If you genuinely cannot resolve a hunk, stop and hand the specific hunk back to the user with both intents stated. Leave the operation in progress.

The `git-guardrails-claude-code` hook blocks these commands. If you find yourself reaching for one, that is the signal to hand back, not to work around the block.

## Process

1. **See the state.** `git status` for unmerged paths, `git log --oneline --left-right HEAD...MERGE_HEAD` (or `REBASE_HEAD`) for what each side carries, and read the conflicting files. Know which side is "ours" and which is "theirs" before touching anything, since rebase inverts the intuition: during a rebase, `ours` is the upstream branch you are replaying onto.

2. **Find the primary source for each side.** The hunk is the symptom; the intent lives upstream of it. In order: the commit message that introduced the change (`git log -1 --format=%B <sha>`), then `git log -S'<distinctive line>'` to find when and why the line arrived, then the PR or issue if the commit references one, then a spec under `specs/` or a plan under `plans/` matching the feature. Do not resolve a hunk whose intent you cannot state in one sentence per side.

3. **Resolve each hunk.** Preserve both intents where they compose. Where they genuinely conflict, keep the one matching the stated goal of the merge and note the trade-off in the final report. Never invent new behavior: a resolution that is neither side is a change smuggled in under a merge, and it will not be reviewed as one.

4. **Run the project's checks.** Discover them from the environment rather than assuming: `package.json` scripts, `Makefile`, `CMakeLists.txt`, `pyproject.toml`, CI config. Typecheck or build first, then tests, then format. A merge that resolves cleanly and fails the build is not resolved.

5. **Finish the operation.** Stage the resolved files and continue (`git rebase --continue`, or commit the merge). For a rebase, keep going until every commit has replayed, resolving each stop the same way. The user's git policy applies throughout: never push, and never run git writes on `main`.

## Report

State per conflicting file: the two intents, which one won or how they composed, and any trade-off taken. Name the checks you ran and their result. If you handed a hunk back, say which one and why.

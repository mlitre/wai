---
name: finishing-a-development-branch
description: Use when implementation is complete, tests pass, and you need to decide how to integrate the work, presents structured options for merge, PR, keep, or discard, then executes the choice and cleans up.
inspired-by: github.com/obra/superpowers/skills/finishing-a-development-branch
---

# Finishing a Development Branch

Verify tests → detect environment → present options → execute choice → clean up.

## Process

### 1. Verify tests

Run the project's test suite first (`npm test` / `cargo test` / `pytest` / `go test ./...` / whatever the repo uses).

If failures:

```
Tests failing (<N> failures). Must fix before finishing:

[failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Do not proceed.

### 2. Detect environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
```

| State | Menu | Cleanup |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON` (normal repo) | 4 options | No worktree to clean |
| `GIT_DIR != GIT_COMMON`, named branch (worktree) | 4 options | Provenance-based (see step 6) |
| Detached HEAD | 3 options (no merge) | No cleanup (externally managed) |

### 3. Determine base branch

```bash
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

Or ask: "This branch split from main, correct?"

### 4. Present options

Normal repo or named-branch worktree, present exactly these 4:

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Print a "Ready for review" checklist (manual push + PR)
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

Detached HEAD, present exactly these 3:

```
Implementation complete. You're on a detached HEAD (externally managed workspace).

1. Print a "Ready for review" checklist (manual push + PR from a new branch)
2. Keep as-is (I'll handle it later)
3. Discard this work

Which option?
```

Don't add explanation. Keep options concise.

### 5. Execute choice

**Option 1, merge locally:**

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

git checkout <base-branch>
git pull
git merge <feature-branch>

# Verify tests on merged result
<test command>
```

Only after merge succeeds: cleanup worktree (step 6), then `git branch -d <feature-branch>`.

**Option 2, Ready-for-review checklist (print only):**

Do not push. Do not create the PR. Do not run any state-changing `gh` command. Print this checklist and stop:

```
Ready for review. Run these yourself when you're satisfied:

1. /review-pr                           # multi-agent audit
2. /ds <base-branch>                    # diffscape browser review vs base
3. /describe-pr                         # writes .claude/pr-descriptions/<branch-slug>.md
4. git push -u origin <feature-branch>  # publish
5. gh pr create --body-file .claude/pr-descriptions/<branch-slug>.md
```

Substitute `<base-branch>` and `<feature-branch>` from the detected env. Do not clean up the worktree, user needs it alive for PR iteration.

The shift from auto-push (old V1) to print-only (V2) is intentional. The branch is the user's call; this skill stops at the recommendation.

**Option 3, keep as-is:**

Report: "Keeping branch `<name>`. Worktree preserved at `<path>`." No cleanup.

**Option 4, discard:**

Confirm first:

```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact "discard". If confirmed:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

Cleanup worktree (step 6), then `git branch -D <feature-branch>`.

### 6. Cleanup workspace

Runs for options 1 and 4 only. Options 2 and 3 preserve the worktree.

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

- If `GIT_DIR == GIT_COMMON`: normal repo, no worktree to remove. Done.
- If `WORKTREE_PATH` is under `.claude/worktrees/`, `.worktrees/`, or `worktrees/` at the repo root: this tooling created it, we own cleanup.

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git worktree remove "$WORKTREE_PATH"
git worktree prune
```

Otherwise the host environment (harness) owns this workspace, leave it alone. If your platform provides a workspace-exit tool, use it.

## Quick reference

| Option | Merge | Push | Keep worktree | Delete branch |
|--------|-------|------|---------------|---------------|
| 1. Merge locally | yes |, |, | yes |
| 2. Print checklist (manual push + PR) |, | manual | yes |, |
| 3. Keep as-is |, |, | yes |, |
| 4. Discard |, |, |, | yes (force) |

## Common mistakes

- **Skipping test verification**, merge broken code or open a failing PR. Verify before offering options.
- **Open-ended questions**, "what next?" is ambiguous. Present exactly 4 options (or 3).
- **Cleaning up worktree for option 2**, kills the workspace the user needs for PR iteration. Cleanup only for options 1 and 4.
- **Deleting branch before removing worktree**, `git branch -d` fails because the worktree still references the branch. Merge → remove worktree → delete branch.
- **Running `git worktree remove` from inside the worktree**, fails silently. Always `cd` to the main repo root first.
- **Cleaning up harness-owned worktrees**, leaves phantom state. Only clean up worktrees under conventional paths (`.claude/worktrees/`, `.worktrees/`, `worktrees/`).
- **No confirmation for discard**, accidental loss. Require a typed "discard".

## Red flags

Never:

- Proceed with failing tests.
- Merge without verifying tests on the result.
- Delete work without typed confirmation.
- Force-push without explicit request.
- Remove a worktree before confirming merge success.
- Clean up a worktree you didn't create.
- Run `git worktree remove` from inside the worktree.

Always:

- Verify tests before offering options.
- Detect environment before presenting the menu.
- `cd` to main repo root before worktree removal.
- Run `git worktree prune` after removal.

---
name: local-review
disable-model-invocation: true
description: Set up a worktree for reviewing a colleague's branch, adds their fork as a remote, fetches, creates the worktree.
inspired-by: humanlayer/.claude/commands/local_review.md
---

# Local Review

You're setting up a hands-on review of someone else's branch. The goal is to have the branch checked out in an isolated worktree where you can read, run, and poke at the code without disturbing your current work.

## Invocation

`/local-review <github-username>:<branch-name>`, e.g. `/local-review alice:fix/auth-token-expiry`.

If the user runs `/local-review` with no argument, ask for it in that exact format and wait.

## Process

### 1. Parse

Split on `:`. Left = GitHub username (the fork owner). Right = branch name on their fork.

If the branch name encodes a ticket (e.g. `eng-1696`, `JIRA-42`, `PROJ-123`), extract it for a short worktree name. Otherwise sanitize the branch name (replace `/` with `-`, drop weird chars).

### 2. Discover the upstream repo

The current working directory is a git repo. Figure out its owner/name from `origin`:

```bash
git remote get-url origin
```

This gives you `git@github.com:OWNER/REPO.git` or `https://github.com/OWNER/REPO.git`. Extract `REPO`. You'll use it to construct the colleague's fork URL.

### 3. Add the fork as a remote (idempotent)

```bash
git remote -v | grep -q '^<USERNAME>\s' || \
  git remote add <USERNAME> git@github.com:<USERNAME>/<REPO>.git
git fetch <USERNAME>
```

If the fetch fails, surface the error, the username or fork probably doesn't exist.

### 4. Create the worktree

Place it under `.claude/worktrees/review-<short-name>` (consistent with the harness's worktree layout):

```bash
git worktree add -b review/<USERNAME>/<BRANCH> .claude/worktrees/review-<SHORT_NAME> <USERNAME>/<BRANCH>
```

The `-b` creates a local tracking branch named `review/<USERNAME>/<BRANCH>` so it's obvious in `git branch` what the worktree is for.

### 5. Settings + dependencies

- If `.claude/settings.local.json` exists in the main worktree, copy it to the new worktree's `.claude/` directory.
- If the repo has a setup convention (Makefile target, package.json script, Justfile recipe, etc.), invoke it. Ask the user if you can't infer it. Common patterns: `make setup`, `npm install`, `pnpm install`, `bun install`, `uv sync`, `cargo build`.

### 6. Confirm + next steps

Echo back what you did, then suggest the V2 chain:

> Set up worktree for `<USERNAME>/<BRANCH>` at `.claude/worktrees/review-<SHORT_NAME>`. Local branch `review/<USERNAME>/<BRANCH>` tracks it. Dependencies installed via `<command>`.
>
> Next:
>   1. Dispatch `code-reviewer` on the diff, it self-dispatches the tests/comments/errors/types specialists.
>   2. `/ds <base-commit>`, diffscape browser review of the diff vs base.
>   3. Manual verdict via `gh pr review <pr-number> --approve | --comment | --request-changes`.
>
> The worktree is yours until the upstream PR merges, then `cleanup-worktrees` will prune it.

## Cleanup

The review worktree is auto-detected by the `cleanup-worktrees` skill once the upstream PR merges (the `review/<USERNAME>/<BRANCH>` naming convention makes it obvious which worktree belongs to which review). No manual cleanup needed.

## Error handling

- **Worktree already exists**: tell the user the path and let them remove it manually first. Don't destroy work.
- **Fetch fails**: surface the error verbatim. Usually the fork/branch doesn't exist or auth is missing.
- **Setup command fails**: report the error but leave the worktree in place, they can still read the code.

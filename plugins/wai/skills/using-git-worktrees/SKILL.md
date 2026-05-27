---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from the current workspace, or before executing an implementation plan, ensures an isolated workspace exists, preferring native worktree tools and falling back to plain `git worktree`.
inspired-by: github.com/obra/superpowers/skills/using-git-worktrees
---

# Using Git Worktrees

Ensure work happens in an isolated workspace. Prefer the platform's native worktree tools. Fall back to manual `git worktree` only when no native tool exists.

**Core principle:** detect existing isolation first. Then use native tools. Then fall back to git. Never fight the harness.

## Step 0, detect existing isolation

Before creating anything, check whether you're already in an isolated workspace:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard:** `GIT_DIR != GIT_COMMON` is also true inside git submodules. Before concluding "already in a worktree", verify you are not in a submodule:

```bash
# If this returns a path, you're in a submodule, not a worktree, treat as a normal repo
git rev-parse --show-superproject-working-tree 2>/dev/null
```

If `GIT_DIR != GIT_COMMON` and not a submodule: you are already in a linked worktree. Skip to step 3 (project setup). Do not create another worktree.

Report:

- On a branch, "Already in isolated workspace at `<path>` on branch `<name>`."
- Detached HEAD, "Already in isolated workspace at `<path>` (detached HEAD, externally managed). Branch creation needed at finish time."

If `GIT_DIR == GIT_COMMON` (or in a submodule), you're in a normal repo checkout.

Has the user already declared a worktree preference in your instructions? If not, ask consent:

> "Want me to set up an isolated worktree? It protects your current branch from changes."

Honor any existing declared preference without asking. If the user declines, work in place and skip to step 3.

## Step 1, create the isolated workspace

Two mechanisms. Try in this order.

### 1a. Native worktree tool (preferred)

The user has consented. Do you have a native worktree tool, `EnterWorktree`, `WorktreeCreate`, `/worktree` command, `--worktree` flag, etc.? If so, use it and skip to step 3.

Native tools handle directory placement, branch creation, and cleanup automatically. Using `git worktree add` when a native tool exists creates phantom state your harness can't see or manage.

Only proceed to 1b if no native tool is available.

### 1b. Git worktree fallback

Create a worktree manually with git.

**Directory selection priority**, explicit user preference always beats observed filesystem state:

1. Check your instructions for a declared worktree directory preference. If present, use it.
2. Check for an existing project-local worktree directory:
   ```bash
   ls -d .claude/worktrees 2>/dev/null    # Preferred for Claude Code projects
   ls -d .worktrees 2>/dev/null           # Common hidden alternative
   ls -d worktrees 2>/dev/null            # Plain alternative
   ```
   If multiple exist, prefer `.claude/worktrees` → `.worktrees` → `worktrees`.
3. No existing directory → default to `.claude/worktrees/` at the project root.

**Safety: verify directory is ignored** before creating the worktree (project-local only):

```bash
git check-ignore -q .claude/worktrees 2>/dev/null \
  || git check-ignore -q .worktrees 2>/dev/null \
  || git check-ignore -q worktrees 2>/dev/null
```

If not ignored: add the directory to `.gitignore`, commit the change, then proceed. This prevents worktree contents from being committed to the repo.

**Create the worktree:**

```bash
path="$LOCATION/$BRANCH_NAME"
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

**Sandbox fallback:** if `git worktree add` fails with a permission error (sandbox denial), tell the user the sandbox blocked creation and you're working in place. Then run setup and baseline tests in place.

## Step 3, project setup

Auto-detect and run appropriate setup:

```bash
[ -f package.json ]      && npm install
[ -f Cargo.toml ]        && cargo build
[ -f requirements.txt ]  && pip install -r requirements.txt
[ -f pyproject.toml ]    && poetry install
[ -f go.mod ]            && go mod download
```

## Step 4, verify clean baseline

Run the project's tests to ensure the workspace starts clean:

```bash
# Whatever the project uses
npm test / cargo test / pytest / go test ./...
```

If tests fail: report failures, ask whether to proceed or investigate. If tests pass: report ready.

Report format:

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick reference

| Situation | Action |
|-----------|--------|
| Already in a linked worktree | Skip creation (step 0) |
| In a submodule | Treat as normal repo (step 0 guard) |
| Native worktree tool available | Use it (step 1a) |
| No native tool | Git fallback (step 1b) |
| `.claude/worktrees/` exists | Use it (verify ignored) |
| `.worktrees/` exists | Use it (verify ignored) |
| `worktrees/` exists | Use it (verify ignored) |
| Multiple exist | Prefer `.claude/worktrees` |
| Directory not ignored | Add to `.gitignore` + commit |
| Permission error on create | Sandbox fallback, work in place |
| Tests fail during baseline | Report failures + ask |
| No `package.json` / `Cargo.toml` / etc. | Skip dependency install |

## Common mistakes

- **Fighting the harness**, using `git worktree add` when the platform provides isolation already. Step 0 detects this; step 1a defers to native tools.
- **Skipping detection**, creating a nested worktree inside an existing one. Run step 0 first, always.
- **Skipping ignore verification**, worktree contents get tracked and pollute `git status`. Use `git check-ignore` before creating project-local worktrees.
- **Assuming directory location**, inconsistency, violates project conventions. Follow the priority: instruction file → existing directory → default `.claude/worktrees/`.
- **Proceeding with failing tests**, can't distinguish new bugs from pre-existing issues. Report and ask.

## Red flags

Never:

- Create a worktree when step 0 detected existing isolation.
- Use `git worktree add` when a native tool exists. This is the #1 mistake, if you have it, use it.
- Skip step 1a, jumping straight to git commands.
- Create a project-local worktree without verifying it's ignored.
- Skip baseline test verification.
- Proceed with failing tests without asking.

Always:

- Run step 0 detection first.
- Prefer native tools over git fallback.
- Follow directory priority: instruction → existing → default.
- Verify ignored for project-local.
- Auto-detect and run project setup.
- Verify clean test baseline.

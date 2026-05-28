---
name: gh-stack
description: Manage stacked branches and pull requests with the `gh-stack` GitHub CLI extension. Use when the user wants to create, push, rebase, sync, navigate, or view stacks of dependent PRs, mentions stacked diffs, branch chains, layered review, or asks to split a large PR into smaller dependent layers. Workflow-agnostic, the user decides when to reach for stacking, the skill does not auto-couple to `/create-plan` or `/implement-plan`. Push, submit, sync, link, unstack, and sync --prune are gated, the agent must obtain explicit one-off authorization before invoking them (same posture as `git push`).
inspired-by: github/gh-stack v0.0.5 (SKILL.md upstream at github.com/github/gh-stack/blob/main/skills/gh-stack/SKILL.md)
---

# gh-stack

`gh stack` is a GitHub CLI extension for managing **stacked branches and pull requests**, an ordered list of branches where each builds on the one below it. Each branch maps to one PR whose base is the branch below it, so reviewers see only that layer's diff.

```
main (trunk)
 └── feat/auth-layer     → PR #1 (base: main)               - bottom (closest to trunk)
  └── feat/api-endpoints → PR #2 (base: feat/auth-layer)
   └── feat/frontend     → PR #3 (base: feat/api-endpoints) - top
```

`up` / `down` / `top` / `bottom` follow this geometry, `up` moves away from trunk, `down` moves toward it.

For per-command details (flags, exit codes, output format), see [COMMANDS.md](./COMMANDS.md). This file holds the rules, the wai gates, and the workflows.

## Prerequisites

1. **GitHub CLI `gh` v2.0+**, authenticated.
2. **Extension installed**: `gh extension install github/gh-stack`.
3. **GitHub-side Stacked PRs preview access**, the feature is in private preview. Without enrollment, `gh stack submit` and `gh stack link` exit code 9 (`Stacked PRs unavailable`). Local commands (`init`, `add`, `rebase`, `push`, `navigate`) still work, but PRs do not render as a Stack on GitHub. Sign up: <https://github.com/orgs/community/discussions> (search "Stacked PRs waitlist") or check repo settings.
4. **Global git config already set** (one-time, project-wide):
   - `git config --global rerere.enabled true`, conflict-resolution memory.
   - `git config --global remote.pushDefault origin`, picks origin automatically when multiple remotes exist.
   - **Global `prepare-commit-msg` hook**, appends `Signed-off-by` to every commit using the git-config identity. Installed at `~/.config/git/hooks/prepare-commit-msg`, registered via `git config --global core.hooksPath ~/.config/git/hooks`. (Note, `format.signoff` only applies to `git format-patch`, not `git commit`; the hook is the only way to auto-DCO on every commit.)

   Verify configs with `git config --global --get <key>`. Verify the hook fired on a recent commit with `git log -1 --format=%B`, the trailer should be present. Never set per-repo, the global values cover every repo on this machine.

## Push gating, hard rule

These commands write to the remote or destroy local/remote state. **Treat each one as a `git push`, ask the user for explicit one-off authorization before invoking.** The `git-guardrails-claude-code` hook blocks them as well, defense in depth:

| Command | Why gated |
|---|---|
| `gh stack push` | Force-pushes (`--force-with-lease --atomic`) every stack branch |
| `gh stack submit` | Pushes + creates GitHub PRs (shared state, visible to others) |
| `gh stack sync` | Pushes after the cascade rebase |
| `gh stack link` | Pushes branches + creates/links PRs |
| `gh stack unstack` | Tears the stack down locally **and** on GitHub (API delete) |
| `gh stack sync --prune` | Deletes local branches for merged PRs |

If the user already approved the action, log the approval scope (per-command, per-session) and proceed. Approval for one push does not extend to the next.

## Committing inside a stack, hard rule

**Never use `gh stack add -Am` or `gh stack add -um`.** Both shortcuts run `git commit -m` internally, which:

- Produces freeform messages, bypassing Conventional Commits.
- Bypasses the `commit` skill entirely, so no review of subject length, body, or banned phrases.
- Bypasses the `wai:receiving-code-review` discipline if the commit is acting on review feedback.

The signoff trailer is handled by the global `prepare-commit-msg` hook (prereq #4), so no manual `-s` is required. Everything else (subject style, scope, body, no AI attribution, no plan labels like "Phase N" / "Dx") is on the commit message itself, which means it has to go through the `commit` skill or a hand-written `git commit -m "<conventional subject>"`.

**Always:**

```bash
gh stack add <branch>                    # creates and switches to the branch, no commit
# write code
git add <paths>                          # stage deliberately
/commit                                  # or: git commit -s -m "feat(scope): subject"
```

## Agent rules

Every `gh stack` call must be non-interactive. Each rule below exists because the prompted form will hang in a non-TTY session.

1. **Always supply branch names as positional arguments** to `init`, `add`, and `checkout`. The bare form prompts.
2. **When a prefix is set, pass only the suffix to `add`.** `gh stack add auth` with prefix `feat` → `feat/auth`. Passing `feat/auth` makes `feat/feat/auth`.
3. **Always `--auto` with `submit`.** Without it, `submit` prompts for a PR title per new PR.
4. **Always `--json` with `view`.** Without it, `view` launches an interactive TUI.
5. **Pass `--remote <name>`** when more than one remote is configured. The global `remote.pushDefault` already covers the common case.
6. **Avoid branches shared across multiple stacks.** A branch in two stacks → exit code 6. Check out a non-shared branch first.

**Never run any of these, each prompts:**

- `gh stack view` (use `--json`)
- `gh stack submit` (use `--auto`)
- `gh stack init` / `gh stack add` / `gh stack checkout` with no positional argument
- `gh stack checkout <pr-number>` when a different local stack already covers those branches (unbypassable conflict prompt, run `gh stack unstack` first, then retry)

## Worktree compatibility

Stacks work cleanly inside a `.claude/worktrees/<name>/` worktree, the stack metadata lives in the worktree's `.git` view. When starting a multi-layer feature, spin up an isolated worktree first via the `using-git-worktrees` skill, then `gh stack init` inside it. Don't `gh stack checkout <pr-number>` from outside a worktree if you're about to also work in a worktree, the local-tracking files will land in the wrong place.

## Quick reference

Common commands, in the order you typically reach for them. **Gated** rows require user authorization.

| Task | Command | Gated |
|------|---------|:-:|
| Create a stack with prefix | `gh stack init -p feat auth` | |
| Create a stack of multiple branches | `gh stack init auth api frontend` | |
| Add a branch (suffix only when prefix set) | `gh stack add api-routes` | |
| Push branches to remote | `gh stack push` | ✓ |
| Push + create draft PRs | `gh stack submit --auto` | ✓ |
| Push + create PRs ready for review | `gh stack submit --auto --open` | ✓ |
| Sync (fetch, rebase, push, PR state) | `gh stack sync` | ✓ |
| Sync + delete merged local branches | `gh stack sync --prune` | ✓ |
| Rebase entire stack (local only, no push) | `gh stack rebase` | |
| Rebase upstack only | `gh stack rebase --upstack` | |
| Continue after conflict | `gh stack rebase --continue` | |
| Abort rebase | `gh stack rebase --abort` | |
| View stack as JSON | `gh stack view --json` | |
| Move up / down the stack | `gh stack up [n]` / `gh stack down [n]` | |
| Jump to top / bottom | `gh stack top` / `gh stack bottom` | |
| Check out by PR number (pulls from GitHub) | `gh stack checkout 42` | |
| Check out by branch name (local only) | `gh stack checkout feature-auth` | |
| Link PRs into a stack (no local tracking) | `gh stack link branch-a branch-b` | ✓ |
| Tear down a stack to restructure it | `gh stack unstack` | ✓ |

Full reference for every flag, exit code, and output line, see [COMMANDS.md](./COMMANDS.md).

## Workflows

### Linear stack from scratch

```bash
# 1. Initialize a stack with the first branch
gh stack init -p feat auth
# → creates feat/auth, checks it out

# 2. Write code for the first layer, stage deliberately, commit via the commit skill
git add internal/auth/middleware.go internal/auth/token.go
/commit
# (or: git commit -s -m "feat(auth): add token validation middleware")

# 3. Add the next layer (suffix only, prefix is applied)
gh stack add api-routes

# 4. Write code, stage, commit
git add internal/api/routes.go
/commit

# 5. Add the top layer
gh stack add frontend
git add web/dashboard.tsx
/commit

# 6. Push + create draft PRs    -- gated, ask before running
gh stack submit --auto

# 7. Verify
gh stack view --json | jq '.branches[] | {name, pr: .pr.number, state: .pr.state}'
```

### Mid-stack changes and sync

When you're on a higher layer and realize you need a change in a lower layer, navigate down, change it there, rebase the rest of the stack on top.

```bash
# On feat/frontend, need a new API endpoint
gh stack down                     # or: gh stack checkout feat/api-routes

git add internal/api/users.go
/commit                           # feat(api): add get-user endpoint

gh stack rebase --upstack         # local rebase, not gated
gh stack top                      # back to where you were
```

If `rebase` hits a conflict (exit code 3), resolve files, `git add` them, then `gh stack rebase --continue`. To bail, `gh stack rebase --abort`. `git rerere` (already enabled globally) memorizes the resolution for the next cascade.

### Phased fan-out, the wai pattern for diamond-shaped plans

When the work has a shared base with two or more downstream arms (e.g. `T1 → {T2→T3, T4→T5→T6}`), gh-stack cannot model fan-outs in a single stack, GitHub's Stacked PRs UI is a strict ladder. Solve it by phasing:

**Phase 1**, land the shared base as a single PR.

```bash
git checkout -b feat/shared-base
git add <files for T1>
/commit
git push -u origin feat/shared-base     # gated
gh pr create --base main                # the shared PR
# review, merge through normal flow
```

**Phase 2**, after the shared base merges, create two stacks rooted on the updated `main`.

```bash
git checkout main && git pull --ff-only

gh stack init -p feat/arm-a t2          # → feat/arm-a/t2
gh stack add t3                         # → feat/arm-a/t3
# code + /commit per layer
gh stack submit --auto                  # gated

# different worktree or after the above is pushed, similarly:
gh stack init -p feat/arm-b t4          # → feat/arm-b/t4
gh stack add t5
gh stack add t6
# code + /commit per layer
gh stack submit --auto                  # gated
```

**Caveat when not enrolled in the Stacked PRs preview**, `submit` exits code 9, the Phase 2 arms become branch chains without GitHub's Stack UI. Use `gh pr create --base <previous-branch>` per layer instead, the dependency chain still works, the rendering does not.

## Exit codes

| Code | Meaning | Recovery |
|------|---------|----------|
| 0 | Success | — |
| 1 | Generic error | Read stderr, often a commit/push failure |
| 2 | Not in a stack | `gh stack init` first |
| 3 | Rebase conflict | Resolve files, `git add`, `gh stack rebase --continue` |
| 4 | GitHub API failure | `gh auth status`, retry |
| 5 | Invalid arguments | Fix the command, check flags |
| 6 | Branch in multiple stacks | Check out a non-shared branch first |
| 7 | Rebase already in progress | `--continue` or `--abort` |
| 8 | Stack file locked | Wait 5s, retry (another `gh stack` is writing) |
| 9 | Stacked PRs unavailable | Repo not enrolled in private preview, fall back to plain `gh pr create --base <prev>` |

## Known limitations

1. **Stacks are strictly linear.** One parent, one child per branch. Fan-outs need the phased pattern above.
2. **A branch cannot belong to two stacks.** Local tracking rejects it (exit code 6).
3. **Merging from the CLI is not supported.** Open the PR URL in a browser to merge.
4. **Remote checkout requires a PR number.** Branch-name checkout works for locally tracked stacks only.
5. **No custom PR title or body at submit time.** Edit afterwards with `gh pr edit`, or use the `wai:describe-pr` skill.
6. **GitHub Stacked PRs is in private preview.** Without enrollment, only local features work.

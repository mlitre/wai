# gh-stack Command Reference

Per-command flags, behavior, output, and exit codes. Companion to [SKILL.md](./SKILL.md), which holds the rules, gates, and workflows.

**Gated commands** require explicit one-off user authorization, the agent must ask before invoking. The `git-guardrails-claude-code` hook blocks them as well.

---

## `gh stack init`, create a stack

Creates a new stack. **Always provide at least one branch name as a positional argument**, the bare form prompts.

```
gh stack init [flags] <branches...>
```

```bash
# With a prefix (recommended, subsequent `add` calls take only the suffix)
gh stack init -p feat auth          # → creates feat/auth

# Multi-part prefix (slashes are fine, suffix-only rule still applies)
gh stack init -p monalisa/billing auth   # → creates monalisa/billing/auth

# Multiple branches at once, no prefix
gh stack init branch-a branch-b branch-c

# Different trunk
gh stack init --base develop branch-a branch-b

# Adopt existing branches (any pre-existing branch is reused, missing ones are created)
gh stack init existing-a existing-b new-one
```

| Flag | Description |
|------|-------------|
| `-b, --base <branch>` | Trunk branch (defaults to the repo's default branch) |
| `-p, --prefix <string>` | Branch name prefix, subsequent `add` calls only need the suffix |

**Behavior:**

- Existing branches are adopted, missing ones are created from the trunk.
- Checks out the last branch in the list.
- Enables `git rerere` if not already on (you've set `rerere.enabled=true` globally, so this is a no-op).

---

## `gh stack add`, add a branch on top

Add a new branch on top of the current stack. Must be run while on the topmost branch (or the trunk if the stack has no branches yet). **Always provide a branch name.**

```
gh stack add <branch>
```

```bash
# Create a new branch and switch to it (suffix only, prefix is applied)
gh stack add api-routes

# Then write code, stage, and commit using the commit skill
git add internal/api/routes.go internal/api/handlers.go
/commit
# or: git commit -s -m "feat(api): add user routes"
```

**The `-Am` and `-um` shortcuts are banned**, see [SKILL.md § Committing inside a stack](./SKILL.md#committing-inside-a-stack-hard-rule). Both bypass Conventional Commits and the `commit` skill review.

**Behavior:**

- **Prefix handling:** Pass only the suffix when a prefix is set. `gh stack add api` with prefix `todo` → `todo/api`. Passing `todo/api` creates `todo/todo/api`.
- If called from a branch that is not the topmost in the stack, exits with code 5 (`"can only add branches on top of the stack"`). Use `gh stack top` first.
- **Uncommitted changes carry over** to the new branch, standard git behavior, the working tree is not touched. Commit or stash on the current branch first if you want a clean start on the new one.

---

## `gh stack push`, push branches to remote — **gated**

Push all stack branches to the remote.

```
gh stack push [--remote <name>]
```

```bash
gh stack push                       # default remote (origin via global config)
gh stack push --remote upstream
```

**Behavior:**

- Pushes all active (non-merged) branches atomically with `--force-with-lease --atomic`.
- Does **not** create or update PRs, use `gh stack submit` for that.

**Output (stderr):** `Pushed N branches`.

---

## `gh stack submit`, push + create PRs — **gated, preview-only**

Push all stack branches and create PRs on GitHub. **Always `--auto`**, the bare form prompts for a PR title per new branch.

```
gh stack submit --auto [--open] [--remote <name>]
```

```bash
gh stack submit --auto              # draft PRs
gh stack submit --auto --open       # PRs ready for review
```

| Flag | Description |
|------|-------------|
| `--auto` | Auto-generate PR titles, **required** for non-interactive use |
| `--open` | Mark new and existing PRs as ready for review |
| `--remote <name>` | Remote (only needed if multiple remotes and global `remote.pushDefault` is not set) |

**Behavior:**

- Pushes all active branches atomically (`--force-with-lease --atomic`).
- Creates a new PR for each branch that lacks one, base set to the first non-merged ancestor.
- After creating PRs, links them as a **Stack** on GitHub (requires the repo to have the Stacked PRs feature enabled).
- Syncs PR metadata for branches that already have PRs.
- **Without preview access**: exits with code 9 (`Stacked PRs unavailable`). In interactive mode, offers to create regular (unstacked) PRs instead. In non-interactive mode (the agent), just fails. Fall back to plain `gh pr create --base <previous-branch>` per layer.

**PR title auto-generation (`--auto`):**

- Single commit on branch → uses the commit subject as the PR title, commit body as PR body.
- Multiple commits on branch → humanizes the branch name (hyphens/underscores → spaces) as the title.

For richer PR descriptions, run the `wai:describe-pr` skill after submit, then `gh pr edit --body-file ...`.

**Output (stderr):** `Created PR #N for <branch>` per new PR, `PR #N for <branch> is up to date` per existing, `Pushed and synced N branches` summary.

---

## `gh stack link`, link existing PRs as a stack — **gated, preview-only**

Link PRs into a stack on GitHub without creating any local tracking state. Use when branches are managed by another tool (jj, Sapling) or when retrofitting an existing branch chain.

```
gh stack link [flags] <branch-or-pr> <branch-or-pr> [...]
```

```bash
gh stack link branch-a branch-b branch-c                # bottom to top
gh stack link --base develop --open branch-a branch-b
gh stack link 10 20 30                                  # by PR number
gh stack link 42 43 feature-auth feature-ui             # mix
```

| Flag | Description |
|------|-------------|
| `--base <branch>` | Base for the bottom of the stack (default `main`) |
| `--open` | Mark new and existing PRs as ready for review |
| `--remote <name>` | Remote |

**Behavior:**

- Arguments are bottom to top.
- Numeric arguments are tried as PR numbers first, fall back to branch names.
- Branch arguments are pushed (non-force, atomic).
- For branches without open PRs, creates them with the correct base chain.
- Existing PRs whose base does not match the expected chain are corrected.
- Creates a new stack or updates an existing one (additive, never removes).
- Does **not** create or modify any local state.
- **Without preview access**, exits code 9.

**Output (stderr):** `Pushing N branches to <remote>...`, `Found PR #N for branch <name>`, `Created PR #N for <branch> (base: <base>)`, `Updated base branch for PR #N to <base>`, `Created stack with N PRs` or `Updated stack to N PRs`.

---

## `gh stack sync`, fetch + rebase + push + sync state — **gated**

The single command for routine synchronization after upstream movement.

```
gh stack sync [--remote <name>] [--prune]
```

| Flag | Description |
|------|-------------|
| `--remote <name>` | Remote to fetch from and push to |
| `--prune` | Delete local branches for merged PRs, **also gated** (separate destructive action) |

**What it does, in order:**

1. **Fetch** latest from the remote.
2. **Fast-forward trunk** to remote (skip if already up to date, warn if diverged).
3. **Cascade rebase** all stack branches onto their updated parents (only if trunk moved). Handles merged PRs via `git rebase --onto`. On conflict, all branches are restored to pre-rebase state and the command exits with code 3.
4. **Push** all active branches atomically.
5. **Sync PR state** from GitHub.
6. **Prune** with `--prune`, deletes local branches for merged PRs. In a TTY the bare form prompts, in a non-TTY (the agent), no prune unless `--prune` is passed.

**Conflict handling:** See [`gh stack rebase`](#gh-stack-rebase-rebase-the-stack).

**Output (stderr):** `✓ Fetched latest changes from origin`, `✓ Trunk main fast-forwarded to <sha>` or `✓ Trunk main is already up to date`, `✓ Rebased <branch> onto <base>` per branch (if base moved), `✓ Pushed N branches`, `✓ PR #N (<branch>) — Open` per branch, `Merged: #N, #M` for merged branches, `✓ Pruned <branch> (merged)` per pruned (when pruning), `✓ Stack synced`.

---

## `gh stack rebase`, rebase the stack

Pull from remote and cascade-rebase stack branches. Use when `sync` reports a conflict or you need finer control (rebase part of the stack only).

```
gh stack rebase [flags] [branch]
```

```bash
gh stack rebase                     # entire stack
gh stack rebase --downstack         # trunk → current branch
gh stack rebase --upstack           # current branch → top
gh stack rebase --continue          # after resolving conflicts
gh stack rebase --abort             # restore all branches
```

| Flag | Description |
|------|-------------|
| `--downstack` | Trunk to current branch |
| `--upstack` | Current branch to top |
| `--continue` | Continue after conflict resolution |
| `--abort` | Restore all branches to pre-rebase state |
| `--remote <name>` | Remote to fetch from |

| Argument | Description |
|----------|-------------|
| `[branch]` | Target branch (defaults to the current branch) |

**Not gated**, rebase does not push. However, conflict resolution and the eventual `gh stack push` afterwards are gated.

**Conflict resolution workflow:**

```bash
gh stack rebase
# exit 3 → parse stderr for conflicted paths
# open files, find <<<<<<< / ======= / >>>>>>> markers, edit
git add path/to/resolved-file.go
gh stack rebase --continue
# if more conflicts, repeat
# to bail:
gh stack rebase --abort
```

**Merged PR detection:** If a branch's PR was squash-merged on GitHub, the rebase uses `--onto` and correctly replays the remaining commits onto the merge target.

**Rerere:** Conflict resolutions are memorized (you have `rerere.enabled=true` globally), the next cascade reapplies them automatically.

---

## `gh stack view`, inspect the stack

Display branches, PR status, and recent commits. **Always pass `--json`**, the bare form launches an interactive TUI.

```bash
gh stack view --json
```

| Flag | Description |
|------|-------------|
| `--json` | JSON to stdout, **required** for non-interactive use |

**Output schema:**

```json
{
  "trunk": "main",
  "prefix": "feat",
  "currentBranch": "feat/api-routes",
  "branches": [
    {
      "name": "feat/auth",
      "head": "abc1234...",
      "base": "def5678...",
      "isCurrent": false,
      "isMerged": true,
      "needsRebase": false,
      "pr": {
        "number": 42,
        "url": "https://github.com/owner/repo/pull/42",
        "state": "MERGED"
      }
    }
  ]
}
```

Fields per branch:

- `name`, branch name.
- `head`, current HEAD SHA.
- `base`, parent branch's HEAD SHA at last sync.
- `isCurrent`, the checked-out branch.
- `isMerged`, PR has been merged.
- `needsRebase`, base is not an ancestor (non-linear history).
- `pr`, PR metadata (omitted if no PR exists). `state` is `OPEN` or `MERGED`.

Common `jq` filters:

```bash
output=$(gh stack view --json)

# Branches needing rebase
echo "$output" | jq '[.branches[] | select(.needsRebase == true)] | length'

# Open PR URLs
echo "$output" | jq -r '.branches[] | select(.pr.state == "OPEN") | .pr.url'

# Merged branches
echo "$output" | jq -r '.branches[] | select(.isMerged == true) | .name'

# Current branch
echo "$output" | jq -r '.currentBranch'

# Fully merged stack?
echo "$output" | jq '[.branches[] | .isMerged] | all'
```

---

## Navigation, `up` / `down` / `top` / `bottom`

```bash
gh stack up          # move up one branch (further from trunk)
gh stack up 3        # move up three
gh stack down        # move down one
gh stack down 2      # move down two
gh stack top         # furthest from trunk
gh stack bottom      # first non-merged branch above trunk
```

Clamps to stack bounds. Merged branches are skipped when navigating from active branches. Fully non-interactive.

---

## `gh stack checkout`, switch to a stack

Check out a stack from a PR number or branch name. **Always provide an argument**, the bare form opens an interactive picker.

```
gh stack checkout <pr-number | branch>
```

```bash
gh stack checkout 42                # by PR number, pulls from GitHub
gh stack checkout feature-auth      # by branch name, local only
```

**Behavior:**

- PR number → fetches the stack from GitHub, pulls the branches, sets up local tracking. If a matching local stack exists, switches to the branch.
- Branch name → resolves against locally tracked stacks only, safe for non-interactive use.

**Warning:** if the local and remote stacks have different branch compositions, this command triggers an unbypassable interactive prompt. Run `gh stack unstack` first to remove the conflicting local stack, then retry.

---

## `gh stack unstack`, tear down a stack — **gated, destructive**

Remove the stack so you can restructure (reorder, rename, drop a branch). Use `gh stack init` after to rebuild.

You must have a branch from the stack checked out, the command targets the active stack.

```
gh stack unstack [--local]
```

```bash
gh stack unstack                    # local AND GitHub
gh stack unstack --local            # local only, keep the stack on GitHub
```

| Flag | Description |
|------|-------------|
| `--local` | Only delete the stack locally |

Without `--local`, deletes the GitHub-side Stack via API. The branches and PRs themselves remain, only their stack-linking is removed.

---

## Output conventions

- **Status messages** → stderr with emoji prefixes (`✓` success, `✗` error, `⚠` warning, `ℹ` info).
- **Data output** (e.g. `view --json`) → stdout.
- Suppress status messages when piping data: `2>/dev/null`.

## Full exit code table

| Code | Meaning | Recovery |
|------|---------|----------|
| 0 | Success | — |
| 1 | Generic error | Read stderr, often a commit or push failure |
| 2 | Not in a stack | `gh stack init` first |
| 3 | Rebase conflict | Resolve, `git add`, `gh stack rebase --continue` |
| 4 | GitHub API failure | `gh auth status`, retry |
| 5 | Invalid arguments | Fix flags / arguments |
| 6 | Disambiguation required | Branch in multiple stacks, check out a non-shared branch |
| 7 | Rebase already in progress | `--continue` (after fixing) or `--abort` |
| 8 | Stack file locked | Another `gh stack` is writing, wait 5s, retry |
| 9 | Stacked PRs unavailable | Repo not enrolled in preview, fall back to plain `gh pr create --base <prev>` |

## Restructure a stack (remove, reorder, rename)

```bash
gh stack unstack                                # gated, tears down locally + on GitHub
git branch -m old-branch-1 new-branch-1
gh stack init --base main new-branch-1 new-branch-2 new-branch-3
```

## Squash-merge recovery

After a PR is squash-merged on GitHub, the original branch's commits no longer exist in the trunk's linear history. `gh stack` detects this and uses `git rebase --onto` to correctly replay remaining commits.

```bash
gh stack sync                                   # gated
# → fetches latest, detects the merge, fast-forwards trunk
# → rebases feat/api-routes onto updated trunk (skips merged branch)
# → rebases feat/frontend onto feat/api-routes
# → pushes updated branches
# → reports: "Merged: #1"

gh stack view --json
# → feat/auth shows isMerged: true, state: MERGED
# → upper branches show updated heads
```

If `sync` hits a conflict during this, it restores all branches to their pre-rebase state and exits code 3, resolve via `gh stack rebase --continue` per the rebase command above.

## Known limitations

1. **Stacks are strictly linear.** One parent, one child per branch. Fan-outs need the phased pattern in [SKILL.md § Phased fan-out](./SKILL.md#phased-fan-out-the-wai-pattern-for-diamond-shaped-plans).
2. **A branch cannot belong to two stacks.** Local tracking rejects it (exit code 6).
3. **Multiple remotes** require `--remote <name>` per command, or `remote.pushDefault` in git config (you have this set globally).
4. **Merging PRs from the CLI is not supported.** Open the PR URL in a browser.
5. **Remote stack checkout requires a PR number.** Branch-name checkout works for locally tracked stacks only.
6. **No custom PR title or body at submit time.** The title is generated from commit messages plus a footer. Use `gh pr edit` or the `wai:describe-pr` skill afterwards.
7. **GitHub Stacked PRs is in private preview.** Without enrollment, `submit` and `link` exit code 9. Local features (`init`, `add`, `rebase`, `push`, `navigate`) still work.
